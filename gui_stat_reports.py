#!/usr/bin/env python

# Acquisition Statistics Report generation

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

import jinja2
import scipy.stats

import Ska.DBI
from Chandra.Time import DateTime
import Ska.Matplotlib
import Ska.report_ranges
from star_error import high_low_rate

task = 'gui_stat_reports'
TASK_SHARE = os.path.join(os.environ['SKA'],'share', task)
TASK_DATA = os.path.join(os.environ['SKA'], 'data', task)
#TASK_SHARE = "."

jinja_env = jinja2.Environment(
	loader=jinja2.FileSystemLoader(os.path.join(TASK_SHARE, 'templates')))

logger = logging.getLogger(task)
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(message)s')


def get_options():
    from optparse import OptionParser
    parser = OptionParser()
    parser.set_defaults()
    parser.add_option("--webdir",
                      default="/proj/sot/ska/www/ASPECT/gui_stat_reports",
                      help="Output web directory")
    parser.add_option("--datadir",
                      default="/proj/sot/ska/data/gui_stat_reports",
                      help="Output data directory")
    parser.add_option("--url",
		      default="/mta/ASPECT/gui_stat_reports/")
    parser.add_option("--verbose",
                      type='int',
                      default=1,
                      help="Verbosity (0=quiet, 1=normal, 2=debug)")
    parser.add_option("--bad_thresh",
		      type='float',
		      default=0.05)
    parser.add_option("--obc_bad_thresh",
		      type='float',
		      default=0.05)
    parser.add_option("--days_back",
		      default=30,
		      type='int'),
    opt, args = parser.parse_args()
    return opt, args




def make_gui_plots( guis, bad_thresh, tstart=0, tstop=DateTime().secs, outdir="plots"):
    """Make range of tracking statistics plots:
    mag_histogram.png - histogram of track failures vs magnitude
    color_histogram.png - histogram of track failuers vs color
    delta_mag_vs_mag.png
    delta_mag_vs_color.png
    frac_not_track_vs_mag.png
    frac_not_track_plus_status.png

    :param guis: all mission gui stars as recarray from Ska.DBI.fetchall
    :param tstart: range of interest tstart (Chandra secs)
    :param tstop: range of interest tstop (Chandra secs)
    :param outdir: output directory for pngs
    :rtype: None
    
    """
    

    if not os.path.exists(outdir):
        os.makedirs(outdir)

    figsize=(5,2.5)
    tiny_y = .1
    range_guis = guis[ (guis['kalman_tstart'] >= tstart) & (guis['kalman_tstart'] < tstop ) ]

    # Scaled Failure Histogram, full mag range
    h=plt.figure(figsize=figsize)
    mag_bin = .1
    good = range_guis[range_guis['not_tracking_samples']*1.0/(range_guis['n_samples']) <= bad_thresh]
    # use unfilled histograms from a scipy example
    (bins, data) = Ska.Matplotlib.hist_outline(good['mag_exp'],
					       bins=np.arange(5.5-(mag_bin/2),
							      12+(mag_bin/2),mag_bin))
    plt.semilogy(bins, data+tiny_y, 'k-')
    bad = range_guis[range_guis['not_tracking_samples']*1.0/(range_guis['n_samples']) > bad_thresh]
    (bins, data) = Ska.Matplotlib.hist_outline(bad['mag_exp'],
					       bins=np.arange(5.5-(mag_bin/2),
							      12+(mag_bin/2),mag_bin))
    plt.semilogy(bins, 100*data+tiny_y, 'r-')
    plt.xlabel('Star magnitude (mag)')
    plt.ylabel('N stars (red is x100)')
    plt.xlim(5,12)
    plt.title('N good (black) and bad (red) stars vs Mag')
    plt.subplots_adjust(top=.85, bottom=.17, right=.97)
    plt.savefig(os.path.join(outdir, 'mag_histogram.png'))
    plt.close(h)

    # Scaled Failure Histogram vs Color
    h=plt.figure(figsize=figsize)
    color_bin = .1
    # use unfilled histograms from a scipy example
    (bins, data) = Ska.Matplotlib.hist_outline(good['color'],
					       bins=np.arange(-0.5-(color_bin/2),
							      2+(color_bin/2),color_bin))
    plt.semilogy(bins, data+tiny_y, 'k-')
    bad = range_guis[range_guis['not_tracking_samples']*1.0/(range_guis['n_samples']) > bad_thresh]
    (bins, data) = Ska.Matplotlib.hist_outline(bad['color'],
					       bins=np.arange(-0.5-(color_bin/2),
							      2+(color_bin/2),color_bin))
    plt.semilogy(bins, 100*data+tiny_y, 'r-')
    plt.xlabel('Color (B-V)')
    plt.ylabel('N stars (red is x100)')
    plt.xlim(-0.5,2)
    plt.title('N good (black) and bad (red) stars vs Color')
    plt.subplots_adjust(top=.85, bottom=.17, right=.97)
    plt.savefig(os.path.join(outdir, 'color_histogram.png'))
    plt.close(h)

    # Delta Mag vs Mag
    h=plt.figure(figsize=figsize)
    tracked = range_guis[range_guis['not_tracking_samples']
			 < range_guis['n_samples']]
    plt.plot(tracked['mag_exp'], tracked['aoacmag_mean']
	     -tracked['mag_exp'], 'k.')
    plt.xlabel('AGASC magnitude (mag)')
    plt.ylabel('Observed - AGASC mag')
    plt.title('Delta Mag vs Mag')
    plt.grid(True)
    plt.subplots_adjust(top=.85, bottom=.17, right=.97)
    plt.savefig(os.path.join(outdir, 'delta_mag_vs_mag.png'))
    plt.close(h)

    # Delta Mag vs Color
    h=plt.figure(figsize=figsize)
    plt.plot(tracked['color'], tracked['aoacmag_mean']
    	     -tracked['mag_exp'], 'k.')
    plt.xlabel('Color (B-V)')
    plt.ylabel('Observed - AGASC mag')
    plt.title('Delta Mag vs Color')
    plt.grid(True)
    plt.subplots_adjust(top=.85, bottom=.17, right=.97)
    plt.savefig(os.path.join(outdir, 'delta_mag_vs_color.png'))
    plt.close(h)

    # Fraction not tracking vs Mag
    h=plt.figure(figsize=figsize)
    trak_frac = (range_guis['not_tracking_samples']*1.0/
		 range_guis['n_samples'])
    plt.semilogy(range_guis['mag_exp'], trak_frac, 'k.')
    plt.xlabel('AGASC magnitude (mag)')
    plt.ylabel('Fraction Not Tracking')
    plt.title('Fraction Not tracking vs Mag')
    plt.grid(True)
    plt.ylim(1e-5, 1.1)
    plt.subplots_adjust(top=.85, bottom=.17, right=.97)
    plt.savefig(os.path.join(outdir, 'frac_not_track_vs_mag.png'))
    plt.close(h)

    # Fraction not tracking plus bad status vs Mag
    h=plt.figure(figsize=figsize)
    trak_frac = ((range_guis['not_tracking_samples']
		  + range_guis['obc_bad_status_samples'])*1.0
		 / range_guis['n_samples'])
    plt.semilogy(range_guis['mag_exp'], trak_frac, 'k.')
    plt.xlabel('AGASC magnitude (mag)')
    plt.ylabel('Frac notrak or obc bad stat')
    plt.title('Frac notrak or obc bad stat vs mag')
    plt.grid(True)
    plt.ylim(1e-5, 1.1)
    plt.subplots_adjust(top=.85, bottom=.17, right=.97)
    plt.savefig(os.path.join(outdir, 'frac_not_track_plus_status.png'))
    plt.close(h)


def make_html( nav_dict, rep_dict, pred_dict, outdir):
    """
    Render and write the basic page, where nav_dict is a dictionary of the
    navigation elements (locations of UP_TO_MAIN, NEXT, PREV), rep_dict is
    a dictionary of the main data elements (n failures etc), fail_dict
    contains the elements required for the extra table of failures at the
    bottom of the page, and outdir is the destination directory.
    """

    template = jinja_env.get_template('index.html')
    page = template.render(nav=nav_dict, rep=rep_dict, by_mag=rep_dict['by_mag'], pred=pred_dict)
    f = open(os.path.join(outdir, 'index.html'), 'w')
    f.write(page)
    f.close()


class NoStarError(Exception):
    """
    Special error for the case when no acquisition stars are found.
    """
    pass


def star_info(stars, predictions, bad_thresh, obc_bad_thresh,
	       tname, mxdatestart, mxdatestop, outdir):
		
    """
    Generate a report dictionary for the time range.

    :param acqs: recarray of all acquisition stars available in the table
    :param tname: timerange string (e.g. 2010-M05)
    :param mxdatestart: mx.DateTime of start of reporting interval
    :param mxdatestop: mxDateTime of end of reporting interval
    :param pred_start: date for beginning of time range for predictions based
    on average from pred_start to now()

    :rtype: dict of report values
    """
	
    rep = { 'datestring' : tname,
            'datestart' : DateTime(mxdatestart).date,
            'datestop' : DateTime(mxdatestop).date,
            'human_date_start' : mxdatestart.strftime("%d-%B-%Y"),
            'human_date_stop' : mxdatestop.strftime("%d-%B-%Y"),
	    }

    rep['n_stars'] = len(stars)
    rep['fail_types'] = []
    if not len(stars):
        raise NoStarError("No acq stars in range")


    fail_stars = dict(bad_trak = stars[stars['not_tracking_samples']*1.0/stars['n_samples']
                                       > bad_thresh ],
                      obc_bad = stars[stars['obc_bad_status_samples']*1.0/stars['n_samples']
                                      > obc_bad_thresh ],
                      no_trak = stars[stars['not_tracking_samples'] == stars['n_samples']
        ])

    fail_types = ['bad_trak', 'no_trak', 'obc_bad']
    for ftype in fail_types:
        trep={}
        trep['type']=ftype
        trep['n_stars'] = len(fail_stars[ftype])
        trep['rate'] = len(fail_stars[ftype])*1.0/rep['n_stars']
        trep['rate_err_high'], trep['rate_err_low'] = high_low_rate(trep['n_stars'],rep['n_stars'])
        
        trep['n_stars_pred'] = predictions['%s_rate' % ftype ]*rep['n_stars']
        trep['rate_pred'] = predictions['%s_rate' % ftype]
        trep['p_less'] = scipy.stats.poisson.cdf(
		    trep['n_stars'], trep['n_stars_pred'])
        trep['p_more'] = 1 - scipy.stats.poisson.cdf(
                trep['n_stars'] - 1, trep['n_stars_pred'])

        flat_fails = [dict(id=star['id'],
                           obsid=star['obsid'],
                           mag=star['mag_exp'],
                           mag_obs=star['aoacmag_mean'],
                           bad_track=(star['not_tracking_samples']*1.0
                                      /star['n_samples']),
                           obc_bad_status=(star['obc_bad_status_samples']*1.0
                                           /star['n_samples']),
                           color=star['color'])
                      for star in fail_stars[ftype]]
        outfile = os.path.join(outdir, "%s_stars_list.html" % ftype)
        trep['fail_url'] = "%s_stars_list.html" % ftype
        rep['fail_types'].append(trep)
        make_fail_html(flat_fails, outfile)

    rep['by_mag'] = []
    # looping first over mag and then over fail type for a better
    # data structure
    bin = .1
    for tmag_start in np.arange(10.0,10.8,.1):
        mag_range_stars = stars[ (stars['mag_exp'] >= tmag_start)
                                 & (stars['mag_exp'] < (tmag_start + bin))]
        mag_rep=dict(mag_start=tmag_start,
                     mag_stop=(tmag_start + bin),
                     n_stars=len(mag_range_stars))
        for ftype in fail_types:
            mag_range_fails = fail_stars[ftype][
                (fail_stars[ftype]['mag_exp'] >= tmag_start)
                & (fail_stars[ftype]['mag_exp'] < (tmag_start + bin))]
            flat_fails = [ dict(id=star['id'],
                                obsid=star['obsid'],
                                mag=star['mag_exp'],
                                mag_obs=star['aoacmag_mean'],
                                bad_track=(star['not_tracking_samples']*1.0
                                           /star['n_samples']),
                                obc_bad_status=(star['obc_bad_status_samples']*1.0
                                                    /star['n_samples']),
				color=star['color'])
			   for star in mag_range_fails]
            failed_star_file = "%s_%.1f_stars_list.html" % (ftype, tmag_start)
	    make_fail_html(flat_fails, os.path.join(outdir, failed_star_file))
	    mag_rep["%s_n_stars" % ftype] = len(mag_range_fails)
            mag_rep["%s_fail_url" % ftype] = failed_star_file
            if len(mag_range_stars) == 0:
                mag_rep["%s_rate" % ftype] = 0
            else:
                mag_rep["%s_rate" % ftype] = len(mag_range_fails)*1.0/len(mag_range_stars)
        rep['by_mag'].append(mag_rep)


    return rep

def make_fail_html( fails, outfile):
    """
    Render and write the expanded table of failed stars
    """
    nav_dict = dict(star_cgi='https://icxc.harvard.edu/cgi-bin/aspect/get_stats/get_stats.cgi?id=',
		    starcheck_cgi='https://icxc.harvard.edu/cgi-bin/aspect/starcheck_print/starcheck_print.cgi?sselect=obsid;obsid1=')
    template = jinja_env.get_template('stars.html')
    page = template.render(nav=nav_dict, fails=fails)
    f = open(outfile, 'w')
    f.write(page)
    f.close()



def main(opt):
    """
    Update star statistics plots.  Mission averages are computed with all stars
    from 2003:001 to the end of the interval.
    """
    
    sqlaca = Ska.DBI.DBI(dbi='sybase', server='sybase', user='aca_read', database='aca', numpy=True)
    min_time = DateTime('2003:001:00:00:00.000')

    data_table = 'trak_stats_data'


    # use the acq_stats_id_by_obsid view for a quick count of the number of ID/NOID
    # stars in each obsid.  Used by make_id_plots()
    #all_id = sqlaca.fetchall('select * from acq_stats_id_by_obsid where tstart >= %f' % 
    #                         min_acq_time.secs )

    to_update = Ska.report_ranges.get_update_ranges(opt.days_back)


    for tname in sorted(to_update.keys()):
        logger.debug("Attempting to update %s" % tname )

	webout = os.path.join(opt.webdir,
			      "%s" % to_update[tname]['year'],
			      to_update[tname]['subid'])
	
	logger.debug("Writing reports to %s" % webout)
	if not os.path.exists(webout):
		os.makedirs(webout)
		
	dataout = os.path.join(opt.datadir,
			       "%s" % to_update[tname]['year'],
			       to_update[tname]['subid'])
	if not os.path.exists(dataout):
		os.makedirs(dataout)

	mxdatestart = to_update[tname]['start']
	mxdatestop = to_update[tname]['stop']

        try:

            stars = sqlaca.fetchall("""select * from %s
            where kalman_tstart >= %f
            and kalman_tstart < %f
            and type != 'FID'
            and color is not NULL
            """
                                    % (data_table,
                                       DateTime(mxdatestart).secs,
                                       DateTime(mxdatestop).secs))




            import json
            pred = dict(obc_bad=json.load(open(os.path.join(TASK_DATA, 'obc_bad_fitfile.json'))),
                        bad_trak=json.load(open(os.path.join(TASK_DATA, 'bad_trak_fitfile.json'))),
                        no_trak=json.load(open(os.path.join(TASK_DATA, 'no_trak_fitfile.json'))),
                        )  

            old_pred = dict(obc_bad=0.07,
                            bad_trak=0.005,
                            no_trak=0.001)


            half_mxd = mxdatestart + ((mxdatestop-mxdatestart)/2)
            half_frac_year = half_mxd.year + half_mxd.day_of_year / 365.25
            predictions = {}
            for ftype in pred:
                if half_frac_year >= DateTime(pred[ftype]['datestart']).frac_year:
                    predictions[ftype + '_rate'] = (
                        pred[ftype]['m'] * (half_frac_year - DateTime(pred[ftype]['datestart']).frac_year)
                        + pred[ftype]['b'])
                else:
                    predictions[ftype + '_rate'] = old_pred[ftype]

            
            rep = star_info(stars, predictions, opt.bad_thresh, opt.obc_bad_thresh,
                            tname, mxdatestart, mxdatestop, webout)

            import json
            rep_file = open(os.path.join(dataout, 'rep.json'), 'w')
            rep_file.write(json.dumps(rep, sort_keys=True, indent=4))
            rep_file.close()


            prev_range = Ska.report_ranges.get_prev(to_update[tname])
            next_range = Ska.report_ranges.get_next(to_update[tname])
            nav = dict(main=opt.url,
                       next="%s/%s/%s/%s" % (opt.url,
                                             next_range['year'],
                                             next_range['subid'],
                                             'index.html'),
                       prev="%s/%s/%s/%s" % (opt.url,
                                             prev_range['year'],
                                             prev_range['subid'],
                                             'index.html'),
                       )
            make_gui_plots( stars,
                        opt.bad_thresh,
                        tstart=DateTime(mxdatestart).secs,
                        tstop=DateTime(mxdatestop).secs,
                        outdir=webout)
            make_html(nav, rep, predictions, outdir=webout)
        except NoStarError:
            print "ERROR: Unable to process %s" % tname
            os.rmdir(webout)
            os.rmdir(dataout)
	



if __name__ == '__main__':
    opt, args = get_options()
    ch = logging.StreamHandler()
    ch.setLevel(logging.WARN)
    if opt.verbose == 2:
	    ch.setLevel(logging.DEBUG)
    if opt.verbose == 0:
	    ch.setLevel(logging.ERROR)
    logger.addHandler(ch) 
    main(opt)
