#!/usr/bin/env python
"""
Write summary page for guide stats.
"""

import argparse
import json
import os
from pathlib import Path

import jinja2

# Matplotlib setup
# Use Agg backend for command-line (non-interactive) operation
import matplotlib
import numpy as np

if __name__ == "__main__":
    matplotlib.use("Agg")
import matplotlib.pyplot as plt
from chandra_time import DateTime

SKA = Path(os.environ["SKA"])


JINJA_ENV = jinja2.Environment(
    loader=jinja2.FileSystemLoader(Path(__file__).parent / "templates" / "guide_stats")
)


def get_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--webdir",
        default=SKA / "www" / "ASPECT" / "gui_stat_reports",
        help="Output web directory",
        type=Path,
    )
    parser.add_argument(
        "--datadir",
        default=SKA / "data" / "gui_stat_reports",
        help="Output data directory",
        type=Path,
    )
    parser.add_argument(
        "--input-datadir",
        default=SKA / "data" / "gui_stat_reports",
        type=Path,
        help="Input data directory",
    )
    return parser


def main():  # noqa: PLR0915
    args = get_parser().parse_args()

    datadir = args.datadir
    plotdir = args.webdir / "summary"
    plotdir.mkdir(exist_ok=True, parents=True)

    time_pad = 0.05

    data = {
        "month": datadir.glob("????/M??/rep.json"),
        "quarter": datadir.glob("????/Q?/rep.json"),
        "semi": datadir.glob("????/S?/rep.json"),
        "year": datadir.glob("????/YEAR/rep.json"),
    }

    # figmap = {"bad_trak": 1, "obc_bad": 2, "no_trak": 3}
    for d in data:
        data[d] = sorted(data[d])
        rates = {
            ftype: {
                "time": np.array([]),
                "rate": np.array([]),
                "err_h": np.array([]),
                "err_l": np.array([]),
            }
            for ftype in ["bad_trak", "no_trak", "obc_bad"]
        }

        for p in data[d]:
            with open(p, "r") as rep_file:
                rep_text = rep_file.read()
            rep = json.loads(rep_text)
            for ftype in rates:
                datetime = DateTime(
                    (DateTime(rep["datestart"]).secs + DateTime(rep["datestop"]).secs)
                    / 2
                )
                frac_year = datetime.frac_year
                rates[ftype]["time"] = np.append(rates[ftype]["time"], frac_year)
                for fblock in rep["fail_types"]:
                    if fblock["type"] == ftype:
                        rates[ftype]["rate"] = np.append(
                            rates[ftype]["rate"], fblock["rate"]
                        )
                        rates[ftype]["err_h"] = np.append(
                            rates[ftype]["err_h"], fblock["rate_err_high"]
                        )
                        rates[ftype]["err_l"] = np.append(
                            rates[ftype]["err_l"], fblock["rate_err_low"]
                        )

        for ftype in [
            "no_trak",
            "bad_trak",
            "obc_bad",
        ]:
            fig1 = plt.figure(1, figsize=(5, 3))
            ax1 = fig1.gca()
            fig2 = plt.figure(2, figsize=(5, 3))
            ax2 = fig2.gca()

            ax1.plot(
                rates[ftype]["time"],
                rates[ftype]["rate"],
                color="black",
                linestyle="",
                marker=".",
                markersize=5,
            )
            ax1.grid()
            ax2.errorbar(
                rates[ftype]["time"],
                rates[ftype]["rate"],
                yerr=np.array([rates[ftype]["err_l"], rates[ftype]["err_h"]]),
                color="black",
                linestyle="",
                marker=".",
                markersize=5,
            )
            ax2.grid()
            with open(args.input_datadir / f"{ftype}_fitfile.json", "r") as fit_file:
                fit_text = fit_file.read()
            fit = json.loads(fit_text)
            trend_start_frac = DateTime(fit["datestart"]).frac_year
            m = fit["m"]
            b = fit["b"]
            now_frac = DateTime().frac_year
            for ax in [ax1, ax2]:
                ax.plot(
                    [trend_start_frac, now_frac + 1],
                    [b, m * ((now_frac + 1) - trend_start_frac) + b],
                    "r-",
                )
            ax2_ylim = ax2.get_ylim()
            # pad a bit below 0 relative to ylim range
            ax2.set_ylim(ax2_ylim[0] - 0.025 * (ax2_ylim[1] - ax2_ylim[0]))
            ax1.set_ylim(ax2.get_ylim())

            for ax in [ax1, ax2]:
                dxlim = now_frac - 2000
                ax.set_xlim(2000, now_frac + time_pad * dxlim)
                #    ax = fig.get_axes()[0]
                labels = ax.get_xticklabels() + ax.get_yticklabels()
                for label in labels:
                    label.set_size("small")
                ax.set_ylabel("Rate", fontsize=12)
                ax.set_title(f"{d} {ftype}", fontsize=12)

            fig1.subplots_adjust(left=0.15)
            fig2.subplots_adjust(left=0.15)
            fig1.savefig(plotdir / f"summary_{d}_{ftype}.png")
            fig2.savefig(plotdir / f"summary_{d}_{ftype}_eb.png")
            plt.close(fig1)
            plt.close(fig2)

    outfile = plotdir / "guide_summary.html"
    template = JINJA_ENV.get_template("summary.html")
    page = template.render()
    with open(outfile, "w") as fh:
        fh.write(page)


if __name__ == "__main__":
    main()
