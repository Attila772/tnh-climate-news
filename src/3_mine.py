"""Step 3: mine the hypergraphs and select the conference-associated configurations.

Input : data/transactions/<year>/<YYYYMMDD>.json
Output (results/):
  hypergraphs/<year>/<full|pre|conference|post>/   maximal frequent itemsets of each window (theta = 1 %)
  hypergraphs/<a>_<b>/<full|conference>/           difference hypergraphs of consecutive COPs (Eq. 6)
  hot_candidates.csv     configurations with s_C > s_P and s_C > s_Q, ranked by s_C (top 5 = selected)
  daily_supports.csv     daily relative support of the selected configurations (Fig. trajectories, S3)
  temporal_summary.csv   per period: range of daily supports, how many selected configurations are frequent
  windows_summary.csv    N per window, day indices of the conference period (Table 1)
  analysis_summary.json  the same in machine-readable form
"""
from collections import Counter
import json, math
import pandas as pd
from common import RESULTS, WINDOWS, item_names, load_days, mine, support, dump_patterns, period

names = item_names()
H = RESULTS / "hypergraphs"
summaries, maxima = {}, {"full": {}, "conference": {}}
hot_rows, daily_rows = [], []

for year, w in WINDOWS.items():
    start, end = w["conference"]
    days = load_days(year)
    groups = {g: Counter() for g in ("full", "pre", "conference", "post")}
    for date, counts in days.items():
        groups["full"].update(counts)
        groups[period(date, start, end)].update(counts)
    ns = {g: sum(c.values()) for g, c in groups.items()}
    result = {}
    for group, counts in groups.items():
        patterns, n_frequent = mine(counts)
        result[group] = patterns
        dump_patterns(H / year / group, patterns, ns[group], names)
        print(year, group, "N =", ns[group], "maximal =", len(patterns), "frequent =", n_frequent, flush=True)
    maxima["full"][year], maxima["conference"][year] = result["full"], result["conference"]

    # Conference-associated configurations (Eq. 7): s_C > s_P and s_C > s_Q, top 5 by s_C.
    candidates = []
    for p, c in result["conference"].items():
        cp, cq = support(groups["pre"], p), support(groups["post"], p)
        if c * ns["pre"] > cp * ns["conference"] and c * ns["post"] > cq * ns["conference"]:
            candidates.append((p, c, cp, cq))
    candidates.sort(key=lambda v: (-v[1], v[0]))
    selected = [p for p, *_ in candidates[:5]]
    for rank, (p, c, cp, cq) in enumerate(candidates, 1):
        hot_rows.append(dict(year=year, rank=rank, selected=rank <= 5, items=" ".join(map(str, p)), themes=" | ".join(names[i] for i in p),
                             conference_count=c, conference_N=ns["conference"], conference_support=c / ns["conference"],
                             pre_support=cp / ns["pre"], post_support=cq / ns["post"]))

    # Daily trajectories: support counted directly on every day, maximal or not.
    order = list(days)
    for date, counts in days.items():
        n = sum(counts.values())
        daily_max, _ = mine(counts)
        for p in selected:
            c = support(counts, p)
            s = c / n
            daily_rows.append(dict(year=year, date=date, day_index_zero=order.index(date), period=period(date, start, end),
                                   items=" ".join(map(str, p)), themes=" | ".join(names[i] for i in p), N=n, support_count=c,
                                   relative_support=s, support_percent=100 * s, frequent=c * 100 >= n, maximal=p in daily_max,
                                   self_information_bits=-math.log2(s) if s else float("inf")))
    summaries[year] = dict(N=ns, days=len(days), start=min(days), end=max(days), conference_start=start, conference_end=end,
                           conference_start_index_zero=order.index(start), conference_end_index_zero=order.index(end),
                           maximal_counts={k: len(v) for k, v in result.items()}, eligible_hot_patterns=len(candidates),
                           selected=[list(p) for p in selected])
    print(year, "finished", flush=True)

# Difference hypergraphs of consecutive conferences (Eq. 6): shared hyperedges removed.
for source, collection in maxima.items():
    for a, b in [("2021", "2022"), ("2022", "2023")]:
        common = set(collection[a]) & set(collection[b])
        degree = Counter()
        dest = H / f"{a}_{b}" / source
        for y in (a, b):
            unique = {p: c for p, c in collection[y].items() if p not in common}
            dump_patterns(dest / y, unique, summaries[y]["N"][source], names)
            degree.update(i for p in unique for i in p)
        (dest / "patterns.txt").write_text("".join((dest / y / "patterns.txt").read_text(encoding="utf-8") for y in (a, b)), encoding="utf-8")
        pd.DataFrame([dict(item_id=i, theme=names[i], hyperdegree=v) for i, v in degree.most_common()]).to_csv(dest / "difference_degrees.csv", index=False)

pd.DataFrame(hot_rows).to_csv(RESULTS / "hot_candidates.csv", index=False)
daily = pd.DataFrame(daily_rows)
daily.to_csv(RESULTS / "daily_supports.csv", index=False)

temporal = []
for (year, per), g in daily.groupby(["year", "period"]):
    day = g.groupby("date")[["frequent", "maximal"]].sum()
    temporal.append(dict(year=year, period=per, minimum_support_percent=g.support_percent.min(), maximum_support_percent=g.support_percent.max(),
                         min_frequent=day.frequent.min(), max_frequent=day.frequent.max(), median_frequent=day.frequent.median(),
                         min_maximal=day.maximal.min(), max_maximal=day.maximal.max(), median_maximal=day.maximal.median()))
pd.DataFrame(temporal).to_csv(RESULTS / "temporal_summary.csv", index=False)

pd.DataFrame([dict(year=y, observation_start=v["start"], observation_end=v["end"], days=v["days"], N_observation=v["N"]["full"],
                   conference_start=v["conference_start"], conference_end=v["conference_end"], N_conference=v["N"]["conference"],
                   N_pre=v["N"]["pre"], N_post=v["N"]["post"], maximal_full=v["maximal_counts"]["full"],
                   maximal_conference=v["maximal_counts"]["conference"], start_index_zero=v["conference_start_index_zero"],
                   end_index_zero=v["conference_end_index_zero"]) for y, v in summaries.items()]).to_csv(RESULTS / "windows_summary.csv", index=False)
(RESULTS / "analysis_summary.json").write_text(json.dumps(summaries, indent=2))
print("done")
