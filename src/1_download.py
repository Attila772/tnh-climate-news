"""Step 1 (optional, ~1.5 GB compressed output, several hours): download the GDELT GKG records.

For every 15-minute update file of the English GDELT 2.0 GKG stream in the observation
windows of config/windows.json, the records with at least one SDG 13 theme (config/
world_bank_to_sdg.csv) in V1THEMES and a non-empty V1LOCATIONS are kept, with the fields
GKGRECORDID, V2DOCUMENTIDENTIFIER, V1THEMES, V1LOCATIONS, V15TONE.

Output: data/raw/<year>/<YYYYMMDD>.tsv.gz and data/raw/<year>/<YYYYMMDD>.log.csv (one line
per update file: HTTP status, number of source and retained records, SHA-256 of the ZIP).
Finished days are skipped on a rerun. Unavailable files (HTTP 404) are logged, never filled.
In October 2026, 88 update files of 10-11 Nov 2022 were unavailable; see the paper, Section 4.5.

Usage:  python src/1_download.py                      # all three windows
        python src/1_download.py --days 20221110      # selected days only
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
import argparse, csv, gzip, hashlib, io, re, time, urllib.error, urllib.request, zipfile
import pandas as pd
from common import CONFIG, DATA, WINDOWS

URL = "https://data.gdeltproject.org/gdeltv2/{slot}00.gkg.csv.zip"
FIELDS = {"GKGRECORDID": 0, "V2DOCUMENTIDENTIFIER": 4, "V1THEMES": 7, "V1LOCATIONS": 9, "V15TONE": 15}
THEME = re.compile(r"(?:^|;)WB_(\d+)_")


def sdg13_codes():
    mapping = pd.read_csv(CONFIG / "world_bank_to_sdg.csv", sep="\t")
    return set(mapping.loc[mapping.SDG.eq(13), "WB_SHORT"])


def fetch(slot, codes, cache=None):
    """Download one update file and return (log entry, retained rows)."""
    info = dict(slot=slot, url=URL.format(slot=slot))
    for attempt in range(3):
        try:
            target = cache / f"{slot}00.gkg.csv.zip" if cache else None
            if target and target.exists():
                payload = target.read_bytes()
            else:
                with urllib.request.urlopen(info["url"], timeout=60) as response:
                    payload = response.read()
                if target:
                    target.write_bytes(payload)
            with zipfile.ZipFile(io.BytesIO(payload)) as z:
                if z.testzip() is not None:
                    raise ValueError("ZIP CRC error")
                members = [n for n in z.namelist() if n.endswith(".gkg.csv")]
                if len(members) != 1:
                    raise ValueError("unexpected ZIP members")
                raw = z.read(members[0])
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("latin1")
            kept, total = [], 0
            for row in csv.reader(io.StringIO(text), delimiter="\t", quoting=csv.QUOTE_NONE):
                total += 1
                if len(row) != 27:
                    raise ValueError(f"expected 27 fields, got {len(row)}")
                themes = {"WB_" + x + "_" for x in THEME.findall(row[7])}
                if row[9].strip() and themes & codes:
                    kept.append([row[i] for i in FIELDS.values()])
            info.update(status="available", http_status=200, sha256=hashlib.sha256(payload).hexdigest(),
                        source_records=total, sdg13_records=len(kept))
            return info, kept
        except urllib.error.HTTPError as e:
            info.update(status="unavailable" if e.code in (404, 410) else "http_error", http_status=e.code)
            if e.code in (404, 410):
                return info, []
        except Exception as e:
            info.update(status="error", error=repr(e))
        time.sleep(2 * (attempt + 1))
    return info, []


def days_of(start, end):
    d, last = datetime.strptime(start, "%Y%m%d"), datetime.strptime(end, "%Y%m%d")
    while d <= last:
        yield d.strftime("%Y%m%d")
        d += timedelta(days=1)


def download_day(year, day, codes, workers, cache):
    out = DATA / "raw" / year
    out.mkdir(parents=True, exist_ok=True)
    target, log = out / f"{day}.tsv.gz", out / f"{day}.log.csv"
    if target.exists() and log.exists():
        print(day, "already downloaded")
        return
    begin = datetime.strptime(day, "%Y%m%d")
    slots = [(begin + timedelta(minutes=15 * k)).strftime("%Y%m%d%H%M") for k in range(96)]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(lambda s: fetch(s, codes, cache), slots))
    failed = [i["slot"] for i, _ in results if i["status"] in ("error", "http_error")]
    if failed:   # transient failures: do not write a day that could look complete
        raise RuntimeError(f"{day}: {len(failed)} update files failed, rerun to retry: {failed[:5]}")
    tmp = target.with_suffix(".tmp")
    with gzip.open(tmp, "wt", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar=None, lineterminator="\n")
        w.writerow(FIELDS)
        for _, rows in results:
            w.writerows(rows)
    tmp.replace(target)
    pd.DataFrame([i for i, _ in results]).to_csv(log, index=False)
    print(day, sum(len(r) for _, r in results), "records,", sum(i["status"] == "unavailable" for i, _ in results), "files unavailable", flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--years", nargs="+", default=list(WINDOWS))
    p.add_argument("--days", nargs="+", help="download only these days (YYYYMMDD)")
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--keep-zips", action="store_true", help="also keep the original ZIP files in data/gdelt_zips")
    a = p.parse_args()
    codes = sdg13_codes()
    cache = DATA / "gdelt_zips" if a.keep_zips else None
    if cache:
        cache.mkdir(parents=True, exist_ok=True)
    for year in a.years:
        for day in days_of(*WINDOWS[year]["observation"]):
            if not a.days or day in a.days:
                download_day(year, day, codes, a.workers, cache)
