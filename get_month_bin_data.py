#!/usr/bin/env python

# Acquisition Statistics Report generation

from __future__ import division
import os
import sys
import numpy as np
#import logging
#import json

# Matplotlib setup
# Use Agg backend for command-line (non-interactive) operation
#import matplotlib
#if __name__ == '__main__':
#    matplotlib.use('Agg')
#    import matplotlib.pyplot as plt

#from Ska.Matplotlib import plot_cxctime

from Chandra.Time import DateTime

#import sherpa.ui as ui
from Ska.report_ranges import timerange, get_next, in_range
import scipy.stats
import Ska.DBI



task = 'gui_stat_reports'
#TASK_SHARE = os.path.join(os.environ['SKA'],'share', task)
TASK_SHARE = "."

from star_error import high_low_rate


trend_type = 'month'
trend_date_start = '2006:292:00:00:00.000'
trend_stop = DateTime().secs 
trend_mxd = DateTime(trend_date_start).mxDateTime
trend_start_unit = in_range(trend_type, trend_mxd)
trend_start_range = timerange(trend_start_unit)
#trend_start = trend_start_range['start'].year + trend_start_range['start'].day_of_year/365.25
trend_start = DateTime(trend_start_range['start']).frac_year

now = DateTime().mxDateTime
now_unit = in_range(trend_type, now)

#csec_year = 86400 * 365.25
dbh = Ska.DBI.DBI(dbi='sybase', server='sybase', user='aca_read', database='aca')
stars = dbh.fetchall("""select kalman_tstart as tstart, n_samples,
                        not_tracking_samples, obc_bad_status_samples
                        from trak_stats_data
                        where type != 'FID' and color is not null and
                        kalman_tstart >= %f and kalman_tstart < %f"""
                     % (DateTime(trend_date_start).secs, trend_stop))
times = DateTime(stars['tstart']).frac_year - trend_start

masks = dict(bad_trak=( stars['not_tracking_samples']*1.0/stars['n_samples']
                                                >= .05 ),
             obc_bad=( stars['obc_bad_status_samples']*1.0/stars['n_samples']
                       >= .05 ),
             no_trak=( stars['not_tracking_samples'] == stars['n_samples']))


class NoStarError(Exception):
    """
    Special error for the case when no acquisition stars are found.
    """
    def __init__(self, value):
        self.value = value
    def __str__(self):
        return repr(self.value) 


for ftype in masks:


    dtable = open("bymonth_data_%s.txt" % ftype, 'w' )
    dtable.write("time,rate,err,n_stars,n_fail,err_hi,err_low\n")
#    print "time,rate,err,n_stars,n_fail,err_hi,err_low"

    #rates = dict(time=[],
    #             rate=[],
    #             err_h=[],
    #             err_l=[])

    curr_unit = trend_start_unit
    while (curr_unit != now_unit ):
        range = timerange(curr_unit)
        range_mask = ((stars['tstart'] >= DateTime(range['start']).secs)
                      & (stars['tstart'] < DateTime(range['stop']).secs))
        range_stars = stars[range_mask]
        range_fail = masks[ftype][range_mask]
        if not len(range_stars):
            raise NoStarError("No stars in range")
        n_stars = len(range_stars)
        n_failed = len(np.flatnonzero(range_fail))
        fail_rate = n_failed/n_stars
        err_high, err_low = high_low_rate( n_failed, n_stars )
        mid_frac =((DateTime(range['start']).frac_year
                   +DateTime(range['stop']).frac_year)/2)
        dtable.write("%.2f,%.6f,%.6f,%d,%d,%.4f,%.4f\n" % (
            mid_frac, fail_rate, np.max([err_high, err_low]),
            n_stars, n_failed, err_high, err_low)) 
#        print "%.2f,%.6f,%.6f,%d,%d,%.4f,%.4f" % (
#            mid_frac, fail_rate, np.max([err_high, err_low]),
#            n_stars, n_failed, err_high, err_low)
        #rates['time'].append(mid_frac)
        #rates['rate'].append(fail_rate)
        #rates['err_h'].append(err_high)
        #rates['err_l'].append(err_low)

        next_range = get_next(timerange(curr_unit))
        curr_unit = in_range(trend_type, next_range['start'])

    dtable.close()

