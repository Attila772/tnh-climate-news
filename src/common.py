"""Shared definitions of the TNH pipeline: paths, windows, mining and pattern export.

Transactions are stored per day as JSON lists of [sorted item ids, multiplicity];
identical transactions are compressed, never deduplicated. Item ids follow
config/items.csv (zero based). All date boundaries are inclusive.
"""
from pathlib import Path
from collections import Counter
from decimal import Decimal, ROUND_CEILING
import json, math
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config"
DATA = ROOT / "data"
TRANSACTIONS = DATA / "transactions"
RESULTS = ROOT / "results"

WINDOWS = {k: v for k, v in json.loads((CONFIG / "windows.json").read_text()).items() if not k.startswith("_")}
YEARS = list(WINDOWS)
THRESHOLD = "0.01"   # theta = 1 %


def item_names():
    return pd.read_csv(CONFIG / "items.csv").WB_NAME.str.strip().tolist()


def read_counts(path):
    return Counter({tuple(k): v for k, v in json.loads(Path(path).read_text())})


def load_days(year):
    """{YYYYMMDD: Counter} for every day of the observation window, in date order."""
    return {f.stem: read_counts(f) for f in sorted((TRANSACTIONS / year).glob("*.json"))}


def period(date, start, end):
    return "pre" if date < start else "post" if date > end else "conference"


def support(counts, pattern):
    """Support count: number of transactions that contain every item of the pattern."""
    wanted = set(pattern)
    return sum(n for t, n in counts.items() if wanted.issubset(t))


def mine(counts, threshold=THRESHOLD):
    """Maximal frequent itemsets with relative support >= threshold.

    Frequent itemsets are enumerated exactly with weighted vertical intersections
    (Eclat-style); the maximal ones are then filtered exactly. The result is the
    same set as SPMF FPMax returns. Returns ({itemset: support count}, number of frequent itemsets).
    """
    n = sum(counts.values())
    if not n:
        raise ValueError("Empty mining window")
    minimum = int((Decimal(str(threshold)) * n).to_integral_value(rounding=ROUND_CEILING))
    weights = np.array(list(counts.values()), dtype=np.int64)
    vertical = {}
    for tid, t in enumerate(counts):
        for item in t:
            vertical.setdefault(item, []).append(tid)
    vertical = {i: np.array(v, dtype=np.int32) for i, v in vertical.items()}
    candidates = [(i, v) for i, v in sorted(vertical.items()) if int(weights[v].sum()) >= minimum]
    frequent = {}

    def visit(prefix, candidates):
        for pos, (i, tids) in enumerate(candidates):
            itemset = prefix + (i,)
            frequent[itemset] = int(weights[tids].sum())
            tail = []
            for j, other in candidates[pos + 1:]:
                both = np.intersect1d(tids, other, assume_unique=True)
                if int(weights[both].sum()) >= minimum:
                    tail.append((j, both))
            if tail:
                visit(itemset, tail)

    visit((), candidates)
    maxima, masks = {}, []
    for pat in sorted(frequent, key=lambda x: (-len(x), x)):
        mask = sum(1 << i for i in pat)
        if not any(mask & m == mask for m in masks):
            maxima[pat] = frequent[pat]
            masks.append(mask)
    return dict(sorted(maxima.items())), len(frequent)


def dump_patterns(folder, patterns, n, names):
    """Write one hypergraph: patterns.txt (HyperGodot input), spmf_patterns.txt, edges.csv, nodes.csv.

    In patterns.txt each line is one hyperedge; theme labels use a no-break space
    inside names because HyperGodot splits items on ASCII spaces. #WEIGHT is the
    relative support in parts per million (rounded half up); #GROUP is the year.
    """
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "spmf_patterns.txt").write_text("".join(" ".join(map(str, p)) + f" #SUP: {c}\n" for p, c in patterns.items()))
    group = next((s for s in reversed(folder.parts) if s in WINDOWS), "1")
    lines = []
    for p, c in patterns.items():
        labels = [names[i].replace(" ", " ") for i in p]
        weight = (2 * c * 1000000 + n) // (2 * n)
        lines.append(" ".join(labels) + f" #WEIGHT: {weight} #GROUP {group}\n")
    (folder / "patterns.txt").write_text("".join(lines), encoding="utf-8")
    rows = [dict(items=" ".join(map(str, p)), themes=" | ".join(names[i] for i in p), support_count=c, N=n,
                 relative_support=c / n, support_percent=100 * c / n, self_information_bits=-math.log2(c / n))
            for p, c in patterns.items()]
    pd.DataFrame(rows).to_csv(folder / "edges.csv", index=False)
    degree = Counter(i for p in patterns for i in p)
    pd.DataFrame([dict(item_id=i, theme=names[i], hyperdegree=degree[i]) for i in sorted(degree)]).to_csv(folder / "nodes.csv", index=False)
