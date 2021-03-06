#!/usr/bin/env python
from __future__ import division

import os
import sys
import numpy as np
import logging
from glob import glob
import json
import jinja2

# Matplotlib setup
# Use Agg backend for command-line (non-interactive) operation
import matplotlib
if __name__ == '__main__':
        matplotlib.use('Agg')
import matplotlib.pyplot as plt

from Chandra.Time import DateTime


task = 'gui_stat_reports'
TASK_SHARE = os.path.join(os.environ['SKA'],'share', task)


from star_error import high_low_rate

datadir = os.path.join(os.environ['SKA'], 'data', task)
plotdir = os.path.join(os.environ['SKA'], 'www', 'ASPECT', task, 'summary')

time_pad = .05

data = { 'month': glob(os.path.join(datadir, '????', 'M??', 'rep.json')),
         'quarter': glob(os.path.join(datadir, '????', 'Q?', 'rep.json')),
         'semi': glob(os.path.join(datadir, '????', 'S?', 'rep.json')),
         'year': glob(os.path.join(datadir, '????', 'YEAR', 'rep.json')),}

figmap = { 'bad_trak' : 1,
           'obc_bad' : 2,
           'no_trak' : 3 }




for d in data.keys():


    data[d].sort()
    rates =  dict([ (ftype, dict(time=np.array([]),
                                rate=np.array([]),
                                err_h=np.array([]),
                                err_l=np.array([])))
                    for ftype in ['bad_trak', 'no_trak', 'obc_bad']])

   
    for p in data[d]:
        rep_file = open(p, 'r')
        rep_text = rep_file.read()
        rep = json.loads(rep_text)
        for ftype in rates.keys():
            datetime = DateTime((DateTime(rep['datestart']).secs
                                 + DateTime(rep['datestop']).secs) / 2)
            frac_year = datetime.frac_year
            rates[ftype]['time'] = np.append(rates[ftype]['time'],
                                             frac_year)
            for fblock in rep['fail_types']:
                if fblock['type'] == ftype:
                    rates[ftype]['rate'] = np.append(rates[ftype]['rate'],
                                                     fblock['rate'])
                    rates[ftype]['err_h'] = np.append(rates[ftype]['err_h'],
                                                      fblock['rate_err_high'])
                    rates[ftype]['err_l'] = np.append(rates[ftype]['err_l'],
                                                      fblock['rate_err_low'])

    

    for ftype in ['no_trak', 'bad_trak', 'obc_bad',]:

        
        fig1 = plt.figure(1,figsize=(5,3))
        ax1 = fig1.gca()
        fig2 = plt.figure(2,figsize=(5,3))
        ax2 = fig2.gca()

        ax1.plot(rates[ftype]['time'],
                 rates[ftype]['rate'],
                 color = 'black',
                 linestyle='',
                 marker='.',
                 markersize=5)
        ax1.grid()
        ax2.errorbar(rates[ftype]['time'],
                     rates[ftype]['rate'],
                     yerr = np.array([rates[ftype]['err_l'],
                                     rates[ftype]['err_h']]),
                     color = 'black',
                     linestyle='',
                     marker='.',
                     markersize=5)
        ax2.grid()
        fit_file = open(os.path.join(datadir, "%s_fitfile.json" % ftype), 'r')
        fit_text = fit_file.read()
        fit = json.loads(fit_text)
        trend_start_frac = DateTime(fit['datestart']).frac_year
        m = fit['m']
        b = fit['b']
        now_frac = DateTime().frac_year
        for ax in [ax1, ax2]:
            ax.plot( [trend_start_frac,
                      now_frac + 1],
                     [ b,
                       m * ((now_frac + 1) - trend_start_frac) + b],
                     'r-')
        ax2_ylim = ax2.get_ylim()
        # pad a bit below 0 relative to ylim range
        ax2.set_ylim(ax2_ylim[0] - 0.025*(ax2_ylim[1] - ax2_ylim[0]))
        ax1.set_ylim(ax2.get_ylim())
        
        for ax in [ax1, ax2]:
            dxlim = now_frac - 2000
            ax.set_xlim(2000,
                        now_frac + time_pad * dxlim)
            #    ax = fig.get_axes()[0]
            labels = ax.get_xticklabels() + ax.get_yticklabels()
            for label in labels:
                label.set_size('small')
            ax.set_ylabel('Rate', fontsize=12)
            ax.set_title("%s %s" % (d,ftype), fontsize=12)

        fig1.subplots_adjust(left=.15)
        fig2.subplots_adjust(left=.15)
        fig1.savefig(os.path.join(plotdir, "summary_%s_%s.png" % (d, ftype)))
        fig2.savefig(os.path.join(plotdir, "summary_%s_%s_eb.png" % (d, ftype)))
        plt.close(fig1)
        plt.close(fig2)                                 





jinja_env = jinja2.Environment(
	loader=jinja2.FileSystemLoader(os.path.join(TASK_SHARE, 'templates')))

outfile = os.path.join(plotdir, 'guide_summary.html')
template = jinja_env.get_template('summary.html')
page = template.render()
f = open(outfile, 'w')
f.write(page)
f.close()
                
