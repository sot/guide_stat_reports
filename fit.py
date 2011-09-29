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
                               where kalman_tstart >= %f and kalman_tstart < %f"""
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

#for type in ['obc_bad',]:
ftype = 'obc_bad'
#for type in masks.keys():

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

##myx = axplot.x.copy()
##myy = axplot.y.copy()
##!/usr/bin/env python
#
## Acquisition Statistics Report generation
#
#
#import os
#import sys
#import numpy as np
#import logging
#import json
#
## Matplotlib setup
## Use Agg backend for command-line (non-interactive) operation
#import matplotlib
#if __name__ == '__main__':
#        matplotlib.use('Agg')
#        import matplotlib.pyplot as plt
#
#from Ska.Matplotlib import plot_cxctime
#
#from Chandra.Time import DateTime
#
#import sherpa.ui as ui
#from Ska.report_ranges import timerange, get_next, in_range
#import scipy.stats
#import Ska.DBI
#
#
#
#task = 'gui_stat_reports'
##TASK_SHARE = os.path.join(os.environ['SKA'],'share', task)
#TASK_SHARE = "."
#
#from star_error import high_low_rate
#
#    
#
#
#trend_type = 'month'
#trend_date_start = '2006:292:00:00:00.000'
#trend_mxd = DateTime(trend_date_start).mxDateTime
#trend_start_unit = in_range(trend_type, trend_mxd)
#trend_start_range = timerange(trend_start_unit)
#trend_start = trend_start_range['start'].year + trend_start_range['start'].day_of_year/365.25
#
#now = DateTime().mxDateTime
#now_unit = in_range(trend_type, now)
#
#csec_year = 86400 * 365.25
#dbh = Ska.DBI.DBI(dbi='sybase', server='sybase', user='aca_read', database='aca')
##stars = dbh.fetchall("""select kalman_tstart as tstart, n_samples,
##                        not_tracking_samples, obc_bad_status_samples
##                        from trak_stats_data
##                        where kalman_tstart >= %f"""
##                     % (DateTime(trend_date_start).secs))
##times = (stars['tstart'] - trend_start) / csec_year
#
##masks = dict(bad_trak=( stars['not_tracking_samples']*1.0/stars['n_samples']
##                                                >= .05 ),
##             obc_bad=( stars['obc_bad_status_samples']*1.0/stars['n_samples']
##                       >= .05 ),
##             no_trak=( stars['not_tracking_samples'] == stars['n_samples']))
#
#
#class NoStarError(Exception):
#    """
#    Special error for the case when no acquisition stars are found.
#    """
#    def __init__(self, value):
#        self.value = value
#    def __str__(self):
#        return repr(self.value) 
#
#ftype = type
#
#
#rates = dict(time=[],
#             rate=[],
#             err_h=[],
#             err_l=[])
#
#curr_unit = trend_start_unit
#while (curr_unit != now_unit ):
#    next_range = get_next(timerange(curr_unit))
#    curr_unit = in_range(trend_type, next_range['start'])
#
#    range = timerange(curr_unit)
#    range_mask = ((stars['tstart'] >= DateTime(range['start']).secs)
#                  & (stars['tstart'] < DateTime(range['stop']).secs))
#    range_stars = stars[range_mask]
#    range_fail = masks[ftype][range_mask]
#    if not len(range_stars):
#        continue
#    #raise NoStarError("No stars in range")
#    n_stars = len(range_stars)
#    n_failed = len(np.flatnonzero(range_fail))
#    fail_rate = n_failed/n_stars
#    err_high, err_low = high_low_rate( n_failed, n_stars )
#    mid_time = DateTime((DateTime(range['start']).secs+DateTime(range['stop']).secs)/2).mxDateTime
#    mid_frac = mid_time.year + mid_time.day_of_year / 365.25
#    rates['time'].append(mid_frac)  
#    rates['rate'].append(fail_rate) 
#    rates['err_h'].append(err_high)
#    rates['err_l'].append(err_low)
#
#
#for rkey in rates:
#    rates[rkey] = np.array(rates[rkey])
#
#data_id = 0
#ui.set_method('simplex')
#ui.load_arrays(data_id,
#               rates['time'] - trend_start,
#               rates['rate'])
#ui.set_staterror(data_id,
#                 np.max([rates['err_h'],
#                         rates['err_l']], axis=0))
#ui.polynom1d.bpoly
#ui.set_model(data_id, 'bpoly')
#ui.thaw(bpoly.c0)
#ui.thaw(bpoly.c1)
##ui.load_user_stat("loglike", llh, my_err)
#ui.set_stat('chi2gehrels')
#ui.fit(data_id)
#myfit = ui.get_fit_results()
#axplot = ui.get_model_plot(data_id)
if myfit.succeeded:
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



#import pickle
#pickle.dump(myfit, open('%s_fitfile.pkl' % type, 'w'))
#import json
#if myfit.succeeded:
#    rep_file = open('%s_fitfile.json' % type, 'w')
#    rep_file.write(json.dumps(dict(time0=trend_start,
#                                   date0=date_start,
#                                   date_end=DateTime().date,
#                                   m=ypoly.c1.val,
#                                   b=ypoly.c0.val,
#                                   comment="mx+b with b at time0 and m = (delta rate)/year"),
#                              sort_keys=True,
#                              indent=4))
#    rep_file.close()
#else:
#    raise ValueError("Not fit")
    
