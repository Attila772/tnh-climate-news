"""Step 2: encode the downloaded records as transactions (sets of SDG 13 item ids).

Input : data/raw/<year>/<YYYYMMDD>.tsv.gz (step 1)
Output: data/transactions_rebuilt/<year>/<YYYYMMDD>.json, the same format as the shipped
        cache in data/transactions: [[sorted item ids, multiplicity], ...].
Each rebuilt day is compared with the shipped cache. With --replace the shipped cache is
overwritten, so that steps 3-5 run on the newly downloaded data.
"""
from collections import Counter
import argparse, json, re, shutil
import pandas as pd
from common import CONFIG, DATA, TRANSACTIONS

THEME = re.compile(r"(?:^|;)WB_(\d+)_")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--replace", action="store_true")
    a = p.parse_args()
    items = pd.read_csv(CONFIG / "items.csv")
    lookup = dict(zip(items.WB_SHORT, items.item_id))
    out = DATA / "transactions_rebuilt"
    same = differ = new = 0
    for raw in sorted((DATA / "raw").glob("*/*.tsv.gz")):
        year, day = raw.parent.name, raw.name[:8]
        records = pd.read_csv(raw, sep="\t", dtype=str, keep_default_na=False, quoting=3)
        counts = Counter()
        for themes, locations in zip(records.V1THEMES, records.V1LOCATIONS):
            t = tuple(sorted({lookup["WB_" + c + "_"] for c in THEME.findall(themes) if "WB_" + c + "_" in lookup}))
            if t and locations.strip():
                counts[t] += 1
        target = out / year / f"{day}.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        text = json.dumps([[list(k), v] for k, v in sorted(counts.items())])
        target.write_text(text)
        shipped = TRANSACTIONS / year / f"{day}.json"
        if not shipped.exists():
            new += 1
        elif shipped.read_text() == text:
            same += 1
        else:
            differ += 1
            print(day, "differs from the shipped cache:", sum(counts.values()), "transactions")
    print(f"{same} days identical to the shipped cache, {differ} different, {new} not in the cache")
    if a.replace:
        for f in out.glob("*/*.json"):
            (TRANSACTIONS / f.parent.name).mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, TRANSACTIONS / f.parent.name / f.name)
        print("shipped cache replaced")
