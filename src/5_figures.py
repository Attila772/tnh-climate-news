"""Step 5: figures of the paper and the Supplementary Information.

Output (results/figures/), each as PDF, SVG and 300 dpi PNG:
  trajectories          daily relative support of the conference-associated configurations (main text)
  S1_threshold          maximal itemsets vs. support threshold, COP28 (SI S1)
  S3_self_information   daily mean self-information of the selected configurations (SI S3)
  table_conference_associated.csv   colours and s_P / s_C / s_Q of the selected configurations (Table 2, SI Table S3)
The hypergraph drawings are made with the viewer (see viewer/) and converted by hypergraph_pdf.py.
"""
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from common import RESULTS

OUT = RESULTS / "figures"
OUT.mkdir(parents=True, exist_ok=True)
# No dates and fixed SVG ids: a rerun gives byte-identical files.
FORMATS = [("pdf", {"metadata": {"CreationDate": None}}), ("svg", {"metadata": {"Date": None}}), ("png", {"dpi": 300})]

# One colour per configuration, identical across years (keys: item ids of config/items.csv).
COLORS = {"37 100": "#E69F00", "31 33 100": "#0072B2", "47 82 100": "#009E73", "7 57": "#CC79A7", "7 47": "#882255",
          "21": "#56B4E9", "7 100": "#D55E00", "80 100 102": "#332288", "41": "#999933", "60 62 92 100": "#000000", "27 31 100": "#AA4499"}
SHORT = {"Short-lived Climate Pollutants (SLCPs)": "Short-lived Climate Pollutants",
         "Health Emergency Preparedness and Disaster Response": "Health Emergency Prep. and Disaster Response",
         "Oil and Gas Policy, Strategy and Institutions": "Oil and Gas Policy, Strategy and Inst."}


def label(themes):
    return " + ".join(SHORT.get(x, x) for x in themes.split(" | "))


def save(fig, name, **kw):
    plt.rcParams["svg.hashsalt"] = "tnh"
    for ext, extra in FORMATS:
        fig.savefig(OUT / f"{name}.{ext}", **kw, **extra)
    plt.close(fig)


d = pd.read_csv(RESULTS / "daily_supports.csv", dtype={"items": str})
hot = pd.read_csv(RESULTS / "hot_candidates.csv", dtype={"items": str})
hot = hot[hot.selected]
v = pd.read_csv(RESULTS / "windows_summary.csv").set_index("year")


def decorate(ax, y):
    s, e = v.loc[y, "start_index_zero"], v.loc[y, "end_index_zero"]
    ax.axvspan(s - .5, e + .5, color="#ececec", zorder=0, lw=0)
    if y == 2022:   # 10-11 Nov 2022: only partially covered by the GDELT archive
        for i in (31, 32):
            ax.axvspan(i - .5, i + .5, color="#fbe3c0", zorder=0, lw=0)
    for x in (s, e):
        ax.axvline(x, color="black", ls="--", lw=.6, zorder=1)
    ax.set_xlim(-.5, v.loc[y, "days"] - .5)
    ax.grid(axis="y", color="#dddddd", lw=.4)
    ax.set_xlabel(f"Day (0 = {pd.Timestamp(str(v.loc[y, 'observation_start'])):%d %b %Y})")


plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 7, "axes.spines.top": False, "axes.spines.right": False,
                     "pdf.fonttype": 42, "ps.fonttype": 42, "axes.linewidth": 0.6, "xtick.major.width": 0.6, "ytick.major.width": 0.6})

# Trajectories (main text)
fig = plt.figure(figsize=(6.85, 9.0))
gs = fig.add_gridspec(6, 2, height_ratios=[1, .33] * 3, width_ratios=[1.7, 1], hspace=.45, wspace=.28, left=.08, right=.985, top=.97, bottom=.04)
axes = [[fig.add_subplot(gs[2 * r, 0]), fig.add_subplot(gs[2 * r, 1])] for r in range(3)]
legends = [fig.add_subplot(gs[2 * r + 1, :]) for r in range(3)]
for row, y in enumerate((2021, 2022, 2023)):
    a, b = axes[row]
    s = d[d.year == y]
    for _, h in hot[hot.year == y].sort_values("rank").iterrows():
        t = s[s["items"] == h["items"]].sort_values("day_index_zero")
        a.plot(t.day_index_zero, t.support_percent, color=COLORS[h["items"]], lw=1.1, label=label(h.themes), zorder=3)
    a.axhline(1, color="#555555", ls=":", lw=.7, zorder=2)
    a.set_ylabel("Daily relative support (%)")
    a.set_ylim(0, None)
    n = s.groupby("day_index_zero").frequent.sum()
    b.step(n.index, n.values, where="mid", color="black", lw=1, zorder=3)
    b.set_ylim(-.2, 5.4)
    b.set_yticks(range(6))
    b.set_ylabel("Configurations with $s_d \\geq 1\\%$")
    decorate(a, y)
    decorate(b, y)
    a.set_title(f"COP{y - 1995} ({y})", loc="left", fontweight="bold", fontsize=8)
    L = legends[row]
    L.axis("off")
    handles, labels = a.get_legend_handles_labels()
    L.legend(handles, labels, loc="upper left", ncol=1, fontsize=6.3, frameon=False, handlelength=1.6, columnspacing=1.2, borderaxespad=0)
save(fig, "trajectories", bbox_inches="tight", pad_inches=0.03)

# S3: daily mean self-information of the five configurations
fig, axes = plt.subplots(1, 3, figsize=(6.85, 2.3), layout="constrained", sharey=True)
for ax, y in zip(axes, (2021, 2022, 2023)):
    s = d[d.year == y].groupby("day_index_zero").self_information_bits.mean()
    ax.plot(s.index, s.values, color="black", lw=1)
    ax.axhline(-np.log2(.01), color="#555555", ls=":", lw=.7)
    decorate(ax, y)
    ax.set_title(f"COP{y - 1995}", loc="left", fontweight="bold", fontsize=8)
    ax.xaxis.label.set_size(6)
axes[0].set_ylabel("Mean self-information (bits)")
save(fig, "S3_self_information", bbox_inches="tight")

# S1: maximal itemsets vs. threshold (from step 4)
df = pd.read_csv(RESULTS / "sensitivity" / "threshold_S1.csv")
plt.rcdefaults()
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 8, "axes.spines.top": False, "axes.spines.right": False,
                     "pdf.fonttype": 42, "ps.fonttype": 42})
fig, ax = plt.subplots(figsize=(4.5, 2.8))
ax.plot(df.threshold_percent, df.maximal, color="black", marker="o", ms=3, lw=1)
ax.axvline(1, color="#555555", ls=":", lw=.8)
ax.set_xscale("log")
ax.invert_xaxis()
ax.set_xticks([10, 5, 2, 1, 0.5, 0.2, 0.1])
ax.set_xticklabels(["10", "5", "2", "1", "0.5", "0.2", "0.1"])
ax.set_xlabel("Relative-support threshold $\\theta$ (%)")
ax.set_ylabel("Maximal frequent itemsets")
ax.grid(color="#dddddd", lw=.4)
save(fig, "S1_threshold", bbox_inches="tight")

pd.DataFrame([dict(year=h.year, rank=h["rank"], themes=h.themes, color=COLORS[h["items"]], s_pre=round(100 * h.pre_support, 2),
                   s_conf=round(100 * h.conference_support, 2), s_post=round(100 * h.post_support, 2)) for _, h in hot.iterrows()]
             ).to_csv(OUT / "table_conference_associated.csv", index=False)
print("figures written to", OUT)
