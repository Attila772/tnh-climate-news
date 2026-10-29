"""Step 4: sensitivity analyses reported in the paper and the Supplementary Information.

Output (results/sensitivity/):
  threshold_S1.csv                maximal itemsets vs. theta, COP28 conference period (Fig./Table S1)
  threshold_full_and_conference.csv  the same on a finer grid for the COP28 full and conference windows
  actual_close.csv, actual_close_top5.csv   conference periods ending on the actual closing dates
  missing_day.csv, missing_day_top5.csv     COP27 without the partially archived 10-11 Nov 2022
  hypergraphs/                    the corresponding maximal itemsets
"""
from collections import Counter
import pandas as pd
from common import RESULTS, WINDOWS, item_names, load_days, mine, support, dump_patterns, period

names = item_names()
OUT = RESULTS / "sensitivity"
OUT.mkdir(parents=True, exist_ok=True)


def windows(days, start, end, excluded=()):
    groups = {g: Counter() for g in ("pre", "conference", "post")}
    for d, c in days.items():
        if d not in excluded:
            groups[period(d, start, end)].update(c)
    return groups, {g: sum(c.values()) for g, c in groups.items()}


def top5(groups, ns, patterns):
    eligible = []
    for p, c in patterns.items():
        pre, post, s = support(groups["pre"], p) / ns["pre"], support(groups["post"], p) / ns["post"], c / ns["conference"]
        if s > pre and s > post:
            eligible.append((p, c, pre, post))
    return sorted(eligible, key=lambda v: (-v[1], v[0]))[:5]


days = {y: load_days(y) for y in WINDOWS}

# Support threshold (Section 2.3, Fig. S1): COP28 conference period.
start, end = WINDOWS["2023"]["conference"]
groups, ns = windows(days["2023"], start, end)
grid = ['0.10', '0.095', '0.09', '0.085', '0.08', '0.075', '0.07', '0.065', '0.06', '0.055', '0.05', '0.045', '0.04', '0.035',
        '0.03', '0.025', '0.02', '0.015', '0.01', '0.005', '0.004', '0.003', '0.002', '0.001']
pd.DataFrame([dict(threshold_percent=float(t) * 100, maximal=len(mine(groups["conference"], t)[0]), N=ns["conference"]) for t in grid]
             ).to_csv(OUT / "threshold_S1.csv", index=False)
full = sum((c for c in days["2023"].values()), Counter())
rows = []
for name, counts in [("full", full), ("conference", groups["conference"])]:
    for t in ['0.10', '0.09', '0.08', '0.07', '0.06', '0.05', '0.04', '0.03', '0.025', '0.02', '0.015', '0.01', '0.009', '0.008',
              '0.007', '0.006', '0.005', '0.004', '0.003', '0.002', '0.0015', '0.001']:
        pat, num = mine(counts, t)
        rows.append(dict(year="2023", window=name, threshold=float(t), N=sum(counts.values()), maximal_count=len(pat), frequent_count=num))
pd.DataFrame(rows).to_csv(OUT / "threshold_full_and_conference.csv", index=False)
print("threshold done", flush=True)

# Conference periods ending on the actual closing dates (Section 2.1).
rows, hot = [], []
for year, w in WINDOWS.items():
    start, close = w["conference"][0], w["actual_close"]
    groups, ns = windows(days[year], start, close)
    pats, _ = mine(groups["conference"])
    dump_patterns(OUT / "hypergraphs" / year / "actual_close", pats, ns["conference"], names)
    for rank, (p, c, pre, post) in enumerate(top5(groups, ns, pats), 1):
        hot.append(dict(year=year, actual_close=close, rank=rank, themes=" | ".join(names[i] for i in p),
                        conference_support=c / ns["conference"], pre_support=pre, post_support=post))
    rows.append(dict(year=year, start=start, actual_close=close, N=ns["conference"], maximal_count=len(pats)))
pd.DataFrame(rows).to_csv(OUT / "actual_close.csv", index=False)
pd.DataFrame(hot).to_csv(OUT / "actual_close_top5.csv", index=False)
print("actual close done", flush=True)

# COP27 without the two partially archived days (Section 4.5); no imputation.
start, end = WINDOWS["2022"]["conference"]
records, summary = [], []
for label, excluded in [("baseline", set()), ("exclude_10_11", {"20221110", "20221111"})]:
    groups, ns = windows(days["2022"], start, end, excluded)
    pats, _ = mine(groups["conference"])
    summary.append(dict(scenario=label, N=ns["conference"], maximal_count=len(pats)))
    for rank, (p, c, pre, post) in enumerate(top5(groups, ns, pats), 1):
        records.append(dict(scenario=label, rank=rank, items=" ".join(map(str, p)), themes=" | ".join(names[i] for i in p), support_count=c,
                            N=ns["conference"], conference_support=c / ns["conference"], pre_support=pre, post_support=post))
    dump_patterns(OUT / "hypergraphs" / "2022" / label, pats, ns["conference"], names)
pd.DataFrame(records).to_csv(OUT / "missing_day_top5.csv", index=False)
pd.DataFrame(summary).to_csv(OUT / "missing_day.csv", index=False)
print("missing day done")
