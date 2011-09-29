#!/usr/bin/env python

from __future__ import division
import os
import sys
import numpy as np
import logging

# Matplotlib setup
# Use Agg backend for command-line (non-interactive) operation
import matplotlib
if __name__ == '__main__':
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

from Ska.Matplotlib import plot_cxctime
from glob import glob
import json
from Chandra.Time import DateTime
import sherpa.ui as ui

import Ska.DBI

trend_date_start = '2006:292:00:00:00.000'
trend_start = DateTime(trend_date_start).secs
trend_date_stop = DateTime().date
trend_stop = DateTime().secs
#trend_stop = DateTime("2011:050:00:00:00.000").secs
csec_year = 86400 * 365.25

dbh = Ska.DBI.DBI(dbi='sybase', server='sybase', user='aca_read', database='aca')
stars = dbh.fetchall("""select kalman_tstart as tstart, n_samples,
                               not_tracking_samples, obc_bad_status_samples
                               from trak_stats_data
                               where type != 'FID' and color is not null and
                               kalman_tstart >= %f and kalman_tstart < %f"""
                     % (trend_start, trend_stop))
times = (stars['tstart'] - trend_start) / csec_year


figmap = { 'bad_trak' : 1,
           'obc_bad' : 2,
           'no_trak' : 3 }


# masks of the stars matching the thresholds we've set (5% and 100% hardcoded)
masks = dict(bad_trak=( stars['not_tracking_samples']*1.0/stars['n_samples']
                        >= .05 ),
             obc_bad=( stars['obc_bad_status_samples']*1.0/stars['n_samples']
                       >= .05 ),
             no_trak=( stars['not_tracking_samples'] == stars['n_samples']))



# a log likelihood sum to be used as the user statistic
def llh(data, model, staterror=None,syserror=None,weight=None):
    prob = p(times, data, model)
    return (np.sum(-np.log(prob)), np.ones_like(times))

# the probability per acquisition based on the given probability
# line... return the probability as a vector of the same length
# as the boolean acquisition and the times
def p( times, fail_mask, model):
    # I tried ones_like here, but didn't have an easy dtype option...
    prob = np.ones(len(times),dtype=np.float64)
    fail_prob = model
    success_prob = prob - fail_prob
    prob[fail_mask == False] = success_prob[fail_mask == False] 
    prob[fail_mask] = fail_prob[fail_mask]
    return prob

# I've got nothing for error ...
def my_err(data):
    return np.ones_like(data)


for ftype in masks.keys():

    fail_mask = masks[ftype]
    data_id = figmap[ftype]
    ui.set_method('simplex')
    ui.polynom1d.ypoly
    ui.set_model(data_id, 'ypoly')
    ui.thaw(ypoly.c0)
    ui.thaw(ypoly.c1)
    ypoly.c0.val = 0.02
    ypoly.c1.min = 0
    ypoly.c1.max = (1 - ypoly.c0.val) / (times[-1] - times[0])

    times[-1] - times[0]
    ui.load_arrays(data_id,
                   times,
                   masks[ftype])
    #ui.set_staterror(data_id,
    #                 np.max([rates[d]['fail']['err_h'][time_ok],
    #                         rates[d]['fail']['err_l'][time_ok]], axis=0))

    ui.load_user_stat("loglike", llh, my_err)
    ui.set_stat(loglike)
    ui.fit(data_id)
    myfit = ui.get_fit_results()
    axplot = ui.get_model_plot(data_id)

    if myfit.succeeded:
        import pickle
        pickle.dump(myfit, open('%s_fitfile.pkl' % ftype, 'w'))

        rep_file = open('%s_fitfile.json' % ftype, 'w')
        rep_file.write(json.dumps(dict(time0=trend_start,
                                       datestop=trend_date_stop,
                                       datestart=trend_date_start,
                                       data=ftype,
                                       bin='unbinned_likelihood',
                                       m=ypoly.c1.val,
                                       b=ypoly.c0.val,
                                       comment="mx+b with b at time0 and m = (delta rate)/year"),
                                      sort_keys=True,
                                  indent=4))
        rep_file.close()
    else:
        raise ValueError("Not fit")

    ui.clean()
