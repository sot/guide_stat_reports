#!/usr/bin/env python

from __future__ import division
import os
import sys
import numpy as np
from Chandra.Time import DateTime
from Ska.report_ranges import timerange, get_next, in_range
import Ska.DBI
import sherpa.ui as ui
import asciitable
import json


task = 'gui_stat_reports'
#TASK_SHARE = os.path.join(os.environ['SKA'],'share', task)
TASK_SHARE = "."

from star_error import high_low_rate


trend_type = 'semi'
data_start = '2001:001:00:00:00.000'
data_stop = DateTime().date

now_unit = in_range(trend_type, DateTime().mxDateTime)

dbh = Ska.DBI.DBI(dbi='sybase', server='sybase', user='aca_read', database='aca')

stars = dbh.fetchall("""select kalman_tstart as tstart, n_samples,
not_tracking_samples, obc_bad_status_samples
from trak_stats_data
where type != 'FID' and color is not null and
kalman_tstart >= %f and kalman_tstart < %f"""
                     % (DateTime(data_start).secs, DateTime(data_stop).secs))

failures = dict(bad_trak=( stars['not_tracking_samples']*1.0/stars['n_samples']
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


for ftype in failures:

    dtable = open("by%s_data_%s.txt" % (trend_type, ftype), 'w' )
    dtable.write("time,rate,err,n_stars,n_fail,err_hi,err_low\n")

    curr_unit = in_range(trend_type, DateTime(data_start).mxDateTime)
    while (curr_unit != now_unit ):
        range = timerange(curr_unit)
        range_mask = ((stars['tstart'] >= DateTime(range['start']).secs)
                      & (stars['tstart'] < DateTime(range['stop']).secs))
        range_stars = stars[range_mask]
        range_fail = failures[ftype][range_mask]
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

        next_range = get_next(timerange(curr_unit))
        curr_unit = in_range(trend_type, next_range['start'])

    dtable.close()

                

