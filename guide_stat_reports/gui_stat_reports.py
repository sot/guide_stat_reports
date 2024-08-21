#!/usr/bin/env python
"""
Generate acquisition statistics report.
"""

import argparse
import json
import os
from pathlib import Path

import jinja2
import matplotlib
import numpy as np
import scipy.stats

if __name__ == "__main__":
    # Matplotlib setup
    # Use Agg backend for command-line (non-interactive) operation
    matplotlib.use("Agg")

import matplotlib.pyplot as plt
import mica.stats.guide_stats
import ska_matplotlib
import ska_report_ranges
from chandra_aca.star_probs import binomial_confidence_interval
from chandra_time import DateTime
from ska_helpers import logging

SKA = Path(os.environ["SKA"])


jinja_env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(Path(__file__).parent / "templates" / "guide_stats")
)

logger = logging.basic_logger("acq_stat_reports", level="INFO")


def get_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.set_defaults()
    parser.add_argument(
        "--webdir",
        default="/proj/sot/ska/www/ASPECT/gui_stat_reports",
        help="Output web directory",
        type=Path,
    )
    parser.add_argument(
        "--datadir",
        default="/proj/sot/ska/data/gui_stat_reports",
        help="Output data directory",
        type=Path,
    )
    parser.add_argument(
        "--input-datadir",
        default=SKA / "data" / "gui_stat_reports",
        type=Path,
        help="Input data directory",
    )
    parser.add_argument("--url", default="/mta/ASPECT/gui_stat_reports/")
    parser.add_argument("--bad_thresh", type=float, default=0.05)
    parser.add_argument("--obc_bad_thresh", type=float, default=0.05)
    parser.add_argument("--days_back", default=30, type=int)

    verbosity_choices = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
    verbosity_choices += [v.lower() for v in verbosity_choices]
    parser.add_argument(
        "-v",
        default="INFO",
        choices=verbosity_choices,
        help="Verbosity (DEBUG, INFO, WARNING, ERROR, CRITICAL)",
    )
    return parser


def make_gui_plots(guis, bad_thresh, tstart=0, tstop=None, outdir="plots"):  # noqa: PLR0915
    """Make range of tracking statistics plots.

    Makes the following plots:
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
    if tstop is None:
        tstop = DateTime().secs

    outdir.mkdir(exist_ok=True, parents=True)

    figsize = (5, 2.5)
    tiny_y = 0.1
    range_guis = guis[
        (guis["kalman_tstart"] >= tstart) & (guis["kalman_tstart"] < tstop)
    ]

    # Scaled Failure Histogram, full mag range
    h = plt.figure(figsize=figsize)
    mag_bin = 0.1
    good = range_guis[(1.0 - range_guis["f_track"]) <= bad_thresh]
    # use unfilled histograms from a scipy example
    (bins, data) = ska_matplotlib.hist_outline(
        good["mag_aca"],
        bins=np.arange(5.5 - (mag_bin / 2), 12 + (mag_bin / 2), mag_bin),
    )
    plt.semilogy(bins, data + tiny_y, "k-")
    bad = range_guis[(1.0 - range_guis["f_track"]) > bad_thresh]
    (bins, data) = ska_matplotlib.hist_outline(
        bad["mag_aca"], bins=np.arange(5.5 - (mag_bin / 2), 12 + (mag_bin / 2), mag_bin)
    )
    plt.semilogy(bins, 100 * data + tiny_y, "r-")
    plt.xlabel("Star magnitude (mag)")
    plt.ylabel("N stars (red is x100)")
    plt.xlim(5, 12)
    plt.title("N good (black) and bad (red) stars vs Mag")
    plt.tight_layout()
    plt.savefig(outdir / "mag_histogram.png")
    plt.close(h)

    # Scaled Failure Histogram vs Color
    h = plt.figure(figsize=figsize)
    color_bin = 0.1
    # use unfilled histograms from a scipy example
    (bins, data) = ska_matplotlib.hist_outline(
        good["color"],
        bins=np.arange(-0.5 - (color_bin / 2), 2 + (color_bin / 2), color_bin),
    )
    plt.semilogy(bins, data + tiny_y, "k-")
    (bins, data) = ska_matplotlib.hist_outline(
        bad["color"],
        bins=np.arange(-0.5 - (color_bin / 2), 2 + (color_bin / 2), color_bin),
    )
    plt.semilogy(bins, 100 * data + tiny_y, "r-")
    plt.xlabel("Color (B-V)")
    plt.ylabel("N stars (red is x100)")
    plt.xlim(-0.5, 2)
    plt.title("N good (black) and bad (red) stars vs Color")
    plt.tight_layout()
    plt.savefig(outdir / "color_histogram.png")
    plt.close(h)

    # Delta Mag vs Mag
    h = plt.figure(figsize=figsize)
    tracked = range_guis[range_guis["f_track"] > 0]
    plt.plot(
        tracked["mag_aca"],
        tracked["aoacmag_mean"] - tracked["mag_aca"],
        "k.",
        markersize=2,
    )
    plt.xlabel("AGASC magnitude (mag)")
    plt.ylabel("Observed - AGASC mag")
    plt.title("Delta Mag vs Mag")
    plt.grid(True)
    plt.ylim(
        np.min([-4, np.min(tracked["aoacmag_mean"] - tracked["mag_aca"])]),
        np.max([4, np.max(tracked["aoacmag_mean"] - tracked["mag_aca"])]),
    )
    plt.tight_layout()
    plt.savefig(outdir / "delta_mag_vs_mag.png")
    plt.close(h)

    # Delta Mag vs Color
    h = plt.figure(figsize=figsize)
    plt.plot(
        tracked["color"],
        tracked["aoacmag_mean"] - tracked["mag_aca"],
        "k.",
        markersize=2,
    )
    plt.xlabel("Color (B-V)")
    plt.ylabel("Observed - AGASC mag")
    plt.title("Delta Mag vs Color")
    plt.grid(True)
    plt.ylim(
        np.min([-4, np.min(tracked["aoacmag_mean"] - tracked["mag_aca"])]),
        np.max([4, np.max(tracked["aoacmag_mean"] - tracked["mag_aca"])]),
    )
    plt.tight_layout()
    plt.savefig(outdir / "delta_mag_vs_color.png")
    plt.close(h)

    or_obs = range_guis["obsid"] < 38000
    er_obs = ~or_obs

    # Fraction not tracking vs Mag
    h = plt.figure(figsize=figsize)
    plt.semilogy(
        range_guis["mag_aca"][or_obs],
        1.0 - range_guis["f_track"][or_obs],
        "b.",
        alpha=0.5,
        markersize=4,
        label="OR",
    )
    plt.semilogy(
        range_guis["mag_aca"][er_obs],
        1.0 - range_guis["f_track"][er_obs],
        "r.",
        alpha=0.5,
        markersize=4,
        label="ER",
    )
    plt.xlabel("AGASC magnitude (mag)")
    plt.ylabel("Fraction Not Tracking")
    plt.title("Fraction Not tracking vs Mag")
    plt.legend(
        loc="upper left",
        fontsize="x-small",
        numpoints=1,
        labelspacing=0.1,
        handletextpad=0.1,
    )
    plt.grid(True)
    plt.ylim(1e-5, 5)
    plt.tight_layout()
    plt.savefig(outdir / "frac_not_track_vs_mag.png")
    plt.close(h)

    # Fraction bad status vs Mag
    h = plt.figure(figsize=figsize)
    plt.semilogy(
        range_guis["mag_aca"][or_obs],
        range_guis["f_obc_bad"][or_obs],
        "b.",
        alpha=0.5,
        markersize=4,
        label="OR",
    )
    plt.semilogy(
        range_guis["mag_aca"][er_obs],
        range_guis["f_obc_bad"][er_obs],
        "r.",
        alpha=0.5,
        markersize=4,
        label="ER",
    )
    plt.xlabel("AGASC magnitude (mag)")
    plt.ylabel("Frac obc bad stat")
    plt.legend(
        loc="upper left",
        fontsize="x-small",
        numpoints=1,
        labelspacing=0.1,
        handletextpad=0.1,
    )
    plt.title("Frac obc bad stat vs mag")
    plt.grid(True)
    plt.ylim(1e-5, 5)
    plt.tight_layout()
    plt.savefig(outdir / "frac_bad_obc_status.png")
    plt.close(h)


def make_html(nav_dict, rep_dict, pred_dict, outdir):
    """
    Render and write the basic page.

    nav_dict is a dictionary of the
    navigation elements (locations of UP_TO_MAIN, NEXT, PREV), rep_dict is
    a dictionary of the main data elements (n failures etc), fail_dict
    contains the elements required for the extra table of failures at the
    bottom of the page, and outdir is the destination directory.
    """

    template = jinja_env.get_template("index.html")
    page = template.render(
        nav=nav_dict, rep=rep_dict, by_mag=rep_dict["by_mag"], pred=pred_dict
    )
    with open(outdir / "index.html", "w") as fh:
        fh.write(page)


class NoStarError(Exception):
    """
    Special error for the case when no acquisition stars are found.
    """


def star_info(
    stars,
    predictions,
    bad_thresh,
    obc_bad_thresh,
    tname,
    range_datestart,
    range_datestop,
    outdir,
):
    """
    Generate a report dictionary for the time range.

    :param acqs: recarray of all acquisition stars available in the table
    :param tname: timerange string (e.g. 2010-M05)
    :param range_datestart: chandra_time DateTime of start of reporting interval
    :param range_datestop: chandra_time DateTime of end of reporting interval
    :param pred_start: date for beginning of time range for predictions based
    on average from pred_start to now()

    :rtype: dict of report values
    """

    rep = {
        "datestring": tname,
        "datestart": DateTime(range_datestart).date,
        "datestop": DateTime(range_datestop).date,
        "human_date_start": "{}-{}-{}".format(
            range_datestart.caldate[0:4],
            range_datestart.caldate[4:7],
            range_datestart.caldate[7:9],
        ),
        "human_date_stop": "{}-{}-{}".format(
            range_datestop.caldate[0:4],
            range_datestop.caldate[4:7],
            range_datestop.caldate[7:9],
        ),
    }

    rep["n_stars"] = len(stars)
    rep["fail_types"] = []
    if not len(stars):
        raise NoStarError("No acq stars in range")

    fail_stars = {
        "bad_trak": stars[(1.0 - stars["f_track"]) > bad_thresh],
        "obc_bad": stars[stars["f_obc_bad"] > obc_bad_thresh],
        "no_trak": stars[stars["f_track"] == 0],
    }

    fail_types = ["bad_trak", "no_trak", "obc_bad"]
    for ftype in fail_types:
        n_stars = len(fail_stars[ftype])
        r, low, high = binomial_confidence_interval(n_stars, rep["n_stars"])
        trep = {}
        trep["type"] = ftype
        trep["n_stars"] = n_stars
        trep["rate"] = float(r)
        trep["rate_err_high"], trep["rate_err_low"] = high - r, r - low

        trep["n_stars_pred"] = predictions[f"{ftype}_rate"] * rep["n_stars"]
        trep["rate_pred"] = predictions[f"{ftype}_rate"]
        trep["p_less"] = scipy.stats.poisson.cdf(trep["n_stars"], trep["n_stars_pred"])
        trep["p_more"] = 1 - scipy.stats.poisson.cdf(
            trep["n_stars"] - 1, trep["n_stars_pred"]
        )

        flat_fails = [
            {
                "id": star["agasc_id"],
                "obsid": star["obsid"],
                "mag": star["mag_aca"],
                "mag_obs": star["aoacmag_mean"],
                "bad_track": (1.0 - star["f_track"]),
                "obc_bad_status": star["f_obc_bad"],
                "color": star["color"],
            }
            for star in fail_stars[ftype]
        ]

        outfile = outdir / f"{ftype}_stars_list.html"
        trep["fail_url"] = outfile.name
        rep["fail_types"].append(trep)
        make_fail_html(flat_fails, outfile)

    rep["by_mag"] = []
    # looping first over mag and then over fail type for a better
    # data structure
    bin = 0.1
    for tmag_start in np.arange(10.0, 10.8, 0.1):
        mag_range_stars = stars[
            (stars["mag_aca"] >= tmag_start) & (stars["mag_aca"] < (tmag_start + bin))
        ]
        mag_rep = {
            "mag_start": tmag_start,
            "mag_stop": (tmag_start + bin),
            "n_stars": len(mag_range_stars),
        }
        for ftype in fail_types:
            mag_range_fails = fail_stars[ftype][
                (fail_stars[ftype]["mag_aca"] >= tmag_start)
                & (fail_stars[ftype]["mag_aca"] < (tmag_start + bin))
            ]
            flat_fails = [
                {
                    "id": star["agasc_id"],
                    "obsid": star["obsid"],
                    "mag": star["mag_aca"],
                    "mag_obs": star["aoacmag_mean"],
                    "bad_track": (1.0 - star["f_track"]),
                    "obc_bad_status": star["f_obc_bad"],
                    "color": star["color"],
                }
                for star in mag_range_fails
            ]
            failed_star_file = f"{ftype}_{tmag_start:.1f}_stars_list.html"
            make_fail_html(flat_fails, outdir / failed_star_file)
            mag_rep[f"{ftype}_n_stars"] = len(mag_range_fails)
            mag_rep[f"{ftype}_fail_url"] = failed_star_file
            if len(mag_range_stars) == 0:
                mag_rep[f"{ftype}_rate"] = 0
            else:
                mag_rep[f"{ftype}_rate"] = (
                    len(mag_range_fails) * 1.0 / len(mag_range_stars)
                )
        rep["by_mag"].append(mag_rep)

    return rep


def make_fail_html(fails, outfile):
    """
    Render and write the expanded table of failed stars
    """
    nav_dict = {
        "star_cgi": "https://icxc.harvard.edu/cgi-bin/aspect/get_stats/get_stats.cgi?id=",
        "starcheck_cgi": "https://icxc.harvard.edu/cgi-bin/aspect/starcheck_print/starcheck_print.cgi?sselect=obsid;obsid1=",
    }
    template = jinja_env.get_template("stars.html")
    page = template.render(nav=nav_dict, fails=fails)
    f = open(outfile, "w")
    f.write(page)
    f.close()


def main():
    """
    Update star statistics plots.

    Mission averages are computed with all stars from 2003:001 to the end of the interval.
    """
    opt = get_parser().parse_args()

    logger.setLevel(opt.v.upper())

    to_update = ska_report_ranges.get_update_ranges(opt.days_back)

    for tname in sorted(to_update.keys()):
        logger.debug(f"Attempting to update {tname}")

        webout = (
            opt.webdir / f"{to_update[tname]['year']}" / f"{to_update[tname]['subid']}"
        )

        logger.debug(f"Writing reports to {webout}")
        webout.mkdir(exist_ok=True, parents=True)

        logger.debug(f"Writing data to {webout}")
        dataout = (
            opt.datadir / f"{to_update[tname]['year']}" / f"{to_update[tname]['subid']}"
        )
        dataout.mkdir(exist_ok=True, parents=True)

        range_datestart = DateTime(to_update[tname]["start"])
        range_datestop = DateTime(to_update[tname]["stop"])

        try:
            stars = mica.stats.guide_stats.get_stats()
            stars = stars[
                (stars["kalman_tstart"] >= DateTime(range_datestart).secs)
                & (stars["kalman_tstart"] < DateTime(range_datestop).secs)
            ]

            pred = {
                "obc_bad": json.load(open(opt.input_datadir / "obc_bad_fitfile.json")),
                "bad_trak": json.load(
                    open(opt.input_datadir / "bad_trak_fitfile.json")
                ),
                "no_trak": json.load(open(opt.input_datadir / "no_trak_fitfile.json")),
            }

            old_pred = {"obc_bad": 0.07, "bad_trak": 0.005, "no_trak": 0.001}

            half_date = range_datestart + (range_datestop - range_datestart) / 2
            half_frac_year = half_date.frac_year
            predictions = {}
            for ftype in pred:
                if half_frac_year >= DateTime(pred[ftype]["datestart"]).frac_year:
                    predictions[ftype + "_rate"] = (
                        pred[ftype]["m"]
                        * (
                            half_frac_year
                            - DateTime(pred[ftype]["datestart"]).frac_year
                        )
                        + pred[ftype]["b"]
                    )
                else:
                    predictions[ftype + "_rate"] = old_pred[ftype]

            rep = star_info(
                stars,
                predictions,
                opt.bad_thresh,
                opt.obc_bad_thresh,
                tname,
                range_datestart,
                range_datestop,
                webout,
            )

            rep_file = open(dataout / "rep.json", "w")
            rep_file.write(json.dumps(rep, sort_keys=True, indent=4))
            rep_file.close()

            prev_range = ska_report_ranges.get_prev(to_update[tname])
            next_range = ska_report_ranges.get_next(to_update[tname])
            nav = {
                "main": opt.url,
                "next": f"{opt.url}/{next_range['year']}/{next_range['subid']}/index.html",
                "prev": f"{opt.url}/{prev_range['year']}/{prev_range['subid']}/index.html",
            }
            make_gui_plots(
                stars,
                opt.bad_thresh,
                tstart=range_datestart.secs,
                tstop=range_datestop.secs,
                outdir=webout,
            )
            make_html(nav, rep, predictions, outdir=webout)
        except NoStarError:
            print(f"ERROR: Unable to process {tname}")
            webout.rmdir()
            dataout.rmdir()


if __name__ == "__main__":
    main()
