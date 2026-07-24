#!/usr/bin/env python3
"""RescueTime incremental fetcher — ONE implementation used by BOTH the
GitHub Action and the local Fetch-Data.ps1 wrapper.

Why it exists
=============
Data older than today never changes, so it is downloaded ONCE into
docs/archive.json and kept forever. Every later run only:

  1. re-fetches the last few days (default 3) with the per-day `rank`
     endpoint — the FRESH endpoint that matches the rescuetime.com
     dashboard (the old interval/productivity endpoint serves stale,
     cached numbers and is no longer used anywhere), and
  2. re-fetches the hourly rows for the rolling last-24h card/pulse,

then rebuilds docs/data.json entirely from the archive. That drops the
API traffic from ~19 calls per run to ~5 and fixes the "site lags hours
behind rescuetime.com" problem in one move.

If docs/archive.json is missing (or --rebuild is given) the full history
is backfilled month by month until RescueTime stops returning data — on
a Lite plan that is ~3 months; after upgrading to premium run once with
--rebuild to pull the complete history.

Usage
=====
    python3 scripts/fetch-addition.py [--rebuild] [--refresh-days N]

The API key comes from the RT_KEY environment variable, or from a
`key=...` line in Secrets.ini next to the repo root (gitignored).
Dates use the LOCAL timezone — the GitHub Action sets TZ=Europe/Copenhagen.
"""

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
ARCHIVE_PATH = DOCS / "archive.json"
DATA_PATH = DOCS / "data.json"

API = "https://www.rescuetime.com/anapi/data"
SLEEP = 1.0          # pause between API calls: stay friendly with the rate limiter
BACKFILL_CAP = 240   # never walk more than 20 years back
EMPTY_MONTHS_STOP = 2  # stop backfill after this many consecutive empty months


# ------------------------------------------------- dictionary type overrides
# docs/dictionary.json can re-type activities for THIS site only (RescueTime is
# not touched). Two optional sections drive the SEMANTIC part (display renames
# are applied client-side):
#   "Apps":       [ { "OriginalName": ["ffx","ffx-2"], "NewName": "Final Fantasy 10",
#                     "NewCategory": "Games" } ]   -> assigns a category to apps
#   "Categories": [ { "OriginalName": ["Games","General Entertainment"],
#                     "NewName": "Fun", "NewType": "Personal" } ]  -> re-types a
#                     category (NewType/NewCategory optional)
# The archive stays RAW (real RescueTime data); the override is applied every
# run while data.json is rebuilt, so editing the dictionary takes effect on the
# next fetch. NewType -> productivity value:
TYPE_PROD = {"work": 2, "productive": 1, "neutral": 0, "personal": -1, "distracting": -2}
APP_CAT = {}    # lowercased raw app name  -> category to assign
CAT_TYPE = {}   # lowercased raw category  -> productivity value to force
APP_TYPE = {}   # lowercased raw app name  -> productivity value to force (wins over category)


def _orig_names(g):
    o = g.get("OriginalName")
    return o if isinstance(o, list) else ([o] if o else [])


def _prod_of(g):
    """A productivity override written as EITHER `type` OR `NewType`."""
    t = g.get("type", g.get("NewType"))
    return TYPE_PROD.get(str(t).strip().lower()) if t is not None else None


def load_overrides():
    """Read the override maps from docs/dictionary.json (best-effort)."""
    app_cat, cat_type, app_type = {}, {}, {}
    try:
        d = json.loads((DOCS / "dictionary.json").read_text(encoding="utf-8"))
    except Exception:
        return app_cat, cat_type, app_type
    for g in d.get("Apps", []) or []:
        cat, prod = g.get("NewCategory"), _prod_of(g)
        for n in _orig_names(g):
            k = str(n).lower()
            if cat:              app_cat[k] = cat
            if prod is not None: app_type[k] = prod
    for g in d.get("Categories", []) or []:
        prod = _prod_of(g)
        if prod is not None:
            for n in _orig_names(g):
                cat_type[str(n).lower()] = prod
            # also key by NewName so an app's NewCategory can point at a renamed
            # category (e.g. NewCategory:"Fun") and still inherit its type
            if g.get("NewName"):
                cat_type[str(g["NewName"]).lower()] = prod
    return app_cat, cat_type, app_type


def translate(act, cat, prod):
    """app->category, then type (app's own type wins over its category's).
    Returns (cat, prod)."""
    a = str(act).lower() if act is not None else None
    cat2 = APP_CAT.get(a, cat) if a is not None else cat
    prod2 = APP_TYPE.get(a) if a is not None else None
    if prod2 is None:
        prod2 = CAT_TYPE.get(str(cat2).lower(), prod) if cat2 is not None else prod
    return cat2, prod2


# ---------------------------------------------------------------- api helpers
def api_key() -> str:
    key = os.environ.get("RT_KEY", "").strip()
    if not key:
        ini = ROOT / "Secrets.ini"
        if ini.exists():
            for line in ini.read_text(encoding="utf-8-sig").splitlines():
                if line.strip().lower().startswith("key"):
                    _, _, val = line.partition("=")
                    key = val.strip()
                    break
    if not key:
        sys.exit("No API key: set RT_KEY or put key=... in Secrets.ini")
    return key


def fetch(key: str, label: str, **params):
    """One API call. Returns the parsed JSON body, or None on any failure."""
    qs = urllib.parse.urlencode({"key": key, "format": "json", **params})
    try:
        with urllib.request.urlopen(f"{API}?{qs}", timeout=60) as r:
            body = json.loads(r.read().decode("utf-8"))
        print(f"OK: {label} ({len(body.get('rows', []))} rows)")
        return body
    except Exception as e:  # HTTP errors, timeouts, bad JSON — all mean "no data"
        print(f"FAILED: {label}: {e}", file=sys.stderr)
        return None


def rank_day(key: str, day: str):
    """Fresh per-app rows for ONE day: [rank, sec, people, activity, cat, prod]."""
    return fetch(key, f"apps on {day}", perspective="rank",
                 restrict_kind="activity", restrict_begin=day, restrict_end=day)


def interval_days(key: str, begin: str, end: str, label: str):
    """Per-day per-app rows for a RANGE: [date, sec, people, activity, cat, prod]."""
    return fetch(key, label, perspective="interval", resolution_time="day",
                 restrict_kind="activity", restrict_begin=begin, restrict_end=end)


# ------------------------------------------------------------------- archive
# archive.json shape:
#   { "format": 1,
#     "days":       { "YYYY-MM-DD": [[sec, activity, category, prod], ...] },
#     "day_levels": { "YYYY-MM-DD": {"2": sec, ...} },   # seeded days without app rows
#     "day_parts":  { "YYYY-MM-DD": [night, morning, afternoon, evening] },
#                   # seconds logged 0-6 / 6-12 / 12-18 / 18-24 (v81, from
#                   # hourly data — feeds the Total page's Averages tab)
#     "history_start": "YYYY-MM-DD" | null,
#     "backfill_done": true|false,
#     "updated_at": iso8601 }
def load_archive() -> dict:
    if ARCHIVE_PATH.exists():
        try:
            a = json.loads(ARCHIVE_PATH.read_text(encoding="utf-8"))
            if a.get("format") == 1:
                a.setdefault("day_parts", {})   # archives written before v81
                return a
        except Exception as e:
            print(f"archive.json unreadable ({e}) - rebuilding", file=sys.stderr)
    return {"format": 1, "days": {}, "day_levels": {}, "day_parts": {},
            "history_start": None, "backfill_done": False, "updated_at": None}


def add_day_parts(archive: dict, hourly_rows) -> None:
    """Aggregate hourly rows (any shape whose row[0] is an ISO timestamp and
    row[1] the seconds) into per-day [night, morning, afternoon, evening]
    quarters (0-6 / 6-12 / 12-18 / 18-24). Days present in the rows are
    rebuilt from scratch, so a re-run never double-counts."""
    per_day = {}
    for row in hourly_rows:
        t = row[0]
        day, hour = t[:10], int(t[11:13])
        per_day.setdefault(day, [0, 0, 0, 0])[hour // 6] += row[1]
    archive.setdefault("day_parts", {}).update(per_day)


def compact_rows(rank_rows) -> list:
    """rank/interval rows -> [sec, activity, category, prod] (drop rank/people/date)."""
    return [[r[1], r[3], r[4], r[5]] for r in rank_rows]


def month_windows(today: date):
    """(first_day, last_day) of the current month, then walking backwards."""
    first = today.replace(day=1)
    while True:
        yield first, min(today, (first + timedelta(days=40)).replace(day=1) - timedelta(days=1))
        first = (first - timedelta(days=1)).replace(day=1)


def backfill(archive: dict, key: str, today: date):
    """Walk backwards month by month until RescueTime runs out of history."""
    empty_streak, seen_any, months = 0, False, 0
    for first, last in month_windows(today):
        months += 1
        if months > BACKFILL_CAP:
            break
        time.sleep(SLEEP)
        body = interval_days(key, first.isoformat(), last.isoformat(),
                             f"backfill {first:%Y-%m}")
        if body is None:          # HTTP error: usually the plan's history limit
            print(f"History limit reached at {first:%Y-%m} - stopping backfill")
            break
        per_day = {}
        for row in body.get("rows", []):
            per_day.setdefault(row[0][:10], []).append(row)
        if not per_day:
            empty_streak += 1
            if seen_any and empty_streak >= EMPTY_MONTHS_STOP:
                break
            if not seen_any and empty_streak >= EMPTY_MONTHS_STOP + 4:
                break             # brand-new account with no data at all
            continue
        empty_streak, seen_any = 0, True
        for day, rows in per_day.items():
            archive["days"][day] = compact_rows(rows)
            archive["day_levels"].pop(day, None)
        # v81: hourly TOTALS for the same month (no restrict_kind — one row
        # per hour+productivity, small) -> per-day time-of-day quarters for
        # the Total page's Averages tab. A failure just leaves the month
        # without day_parts; everything else still works.
        time.sleep(SLEEP)
        hb = fetch(key, f"backfill hours {first:%Y-%m}",
                   perspective="interval", resolution_time="hour",
                   restrict_begin=first.isoformat(), restrict_end=last.isoformat())
        if hb:
            add_day_parts(archive, hb.get("rows", []))
    archive["backfill_done"] = True


def refresh_recent(archive: dict, key: str, today: date, n_days: int) -> bool:
    """Re-fetch the last n_days (incl. today) with the FRESH rank endpoint.
    Returns False if today's fetch failed — then data.json must not be built."""
    ok_today = False
    for i in range(n_days - 1, -1, -1):
        day = (today - timedelta(days=i)).isoformat()
        time.sleep(SLEEP)
        body = rank_day(key, day)
        if body is None:
            if i == 0:
                return False
            continue                      # keep whatever the archive already has
        archive["days"][day] = compact_rows(body.get("rows", []))
        archive["day_levels"].pop(day, None)
        if i == 0:
            ok_today = True
    return ok_today


def recompute_bounds(archive: dict):
    dates = sorted(set(archive["days"]) | set(archive["day_levels"]))
    archive["history_start"] = dates[0] if dates else None
    archive["updated_at"] = datetime.now(timezone.utc).isoformat()


# -------------------------------------------------------------- data.json
def day_level_totals(archive: dict, day: str) -> dict:
    rows = archive["days"].get(day)
    if rows is not None:
        lv = {}
        for sec, _act, _cat, prod in rows:
            _c, p = translate(_act, _cat, prod)   # apply dictionary re-typing
            lv[str(p)] = lv.get(str(p), 0) + sec
        return lv
    # day_levels (pre-premium days with no per-activity detail) carry no
    # category, so a category->type override can't reach them; they stay raw
    return archive["day_levels"].get(day, {})


def rank_shape(compact) -> list:
    """[sec, act, cat, prod] -> the UI's rank row shape [i, sec, 1, act, cat, prod],
    applying the dictionary's app->category / category->type overrides."""
    out = []
    for i, (sec, act, cat, prod) in enumerate(compact):
        cat2, prod2 = translate(act, cat, prod)
        out.append([i + 1, sec, 1, act, cat2, prod2])
    return out


def merge_days(archive: dict, days: list) -> list:
    """Merge several days' compact rows into one rank-shaped list (per app+level)."""
    acc = {}
    for day in days:
        for sec, act, cat, prod in archive["days"].get(day, []):
            k = (act, prod)
            if k in acc:
                acc[k][0] += sec
            else:
                acc[k] = [sec, act, cat, prod]
    merged = sorted(acc.values(), key=lambda r: -r[0])
    return rank_shape(merged)


def build_data(archive: dict, hour_rows: list, today: date) -> dict:
    iso = lambda d: d.isoformat()
    span = lambda n, end=None: [iso((end or today) - timedelta(days=i))
                               for i in range(n - 1, -1, -1)]
    # rows_daily: last 92 days of per-level totals, derived from FRESH rank data
    rows_daily = []
    for day in span(92):
        for lvl, sec in sorted(day_level_totals(archive, day).items(),
                               key=lambda kv: -int(kv[0])):
            if sec:
                rows_daily.append([day + "T00:00:00", sec, 1, int(lvl)])
    # last full Mon-Sun week
    off = today.isoweekday() % 7 or 7          # Sunday -> previous Sunday
    last_sun = today - timedelta(days=off)
    week_days = span(7, last_sun)
    return {
        "rows_daily": rows_daily,
        "week_activities": merge_days(archive, week_days),
        "month_activities": merge_days(archive, span(30)),
        "day_activities": {d: rank_shape(archive["days"].get(d, []))
                           for d in span(30) if d in archive["days"]},
        # hour rows are rank-shaped [hour, sec, people, act, cat, prod]; re-type
        # them too so the rolling-24h pulse matches the rest of the site
        "hour_activities": [([r[0], r[1], r[2], r[3], *translate(r[3], r[4], r[5])]
                             if len(r) >= 6 else r) for r in hour_rows],
        "history_start": archive.get("history_start"),
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


# ------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rebuild", action="store_true",
                    help="ignore the existing archive and backfill everything "
                         "(run once after upgrading to premium)")
    ap.add_argument("--refresh-days", type=int, default=3,
                    help="re-fetch this many recent days incl. today (default 3)")
    args = ap.parse_args()

    key = api_key()
    today = date.today()

    archive = load_archive() if not args.rebuild else {
        "format": 1, "days": {}, "day_levels": {}, "day_parts": {},
        "history_start": None, "backfill_done": False, "updated_at": None}

    if not archive["backfill_done"]:
        print("No complete archive - backfilling full history (one-time)...")
        backfill(archive, key, today)

    if not refresh_recent(archive, key, today, max(1, args.refresh_days)):
        sys.exit("Today's fetch failed - archive.json/data.json NOT updated.")

    # hourly rows: 6 days back (= 7 calendar days incl. today) so the Offline
    # page's 7-day calendar can populate every hour; the rolling last-24h card,
    # the pulse's prior-24h compare, and the Trends Daily group all still read
    # their own sub-windows out of this.
    time.sleep(SLEEP)
    hourly = fetch(key, "hourly apps", perspective="interval",
                   resolution_time="hour", restrict_kind="activity",
                   restrict_begin=(today - timedelta(days=6)).isoformat(),
                   restrict_end=today.isoformat())
    hour_rows = (hourly or {}).get("rows", [])
    if hour_rows:                      # v81: keep the time-of-day quarters
        add_day_parts(archive, hour_rows)   # fresh for the fetched days

    recompute_bounds(archive)
    ARCHIVE_PATH.write_text(json.dumps(archive, separators=(",", ":")),
                            encoding="utf-8")
    # load the dictionary overrides now (archive was written RAW just above;
    # only data.json gets the re-typing applied)
    global APP_CAT, CAT_TYPE, APP_TYPE
    APP_CAT, CAT_TYPE, APP_TYPE = load_overrides()
    DATA_PATH.write_text(json.dumps(build_data(archive, hour_rows, today),
                                    separators=(",", ":")), encoding="utf-8")
    n_days = len(archive["days"]) + len(archive["day_levels"])
    print(f"SUCCESS - archive.json ({n_days} days, since "
          f"{archive['history_start']}) and data.json written.")


if __name__ == "__main__":
    main()
