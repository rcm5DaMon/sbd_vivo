"""Import mode refresh for every SBD area: fill sql/sbd_template.sql per area, run it once, write data/<area>.json.

Runs in GitHub Actions (see .github/workflows/refresh.yml). Credentials come from
the GCP_SA_KEY secret via google-github-actions/auth, so nothing secret is in the repo.

To add or change an area: edit EVENTS below (dates, target table, reference periods).
Local run (optional):  pip install google-cloud-bigquery
                       gcloud auth application-default login
                       python scripts/refresh.py            # all areas
                       python scripts/refresh.py tangban    # one area
"""
import json
import os
import pathlib
import sys

from google.cloud import bigquery

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = os.environ.get("BQ_PROJECT", "e-smart-433113")
MAX_GB = float(os.environ.get("MAX_GB", "2"))  # safety cap per query

EVENTS = {
    "jakarta": {
        "START": "2026-11-01", "END": "2026-11-30",
        "TARGET_TABLE": "master_data.target_sbd_vivo_jakarta",
        "V80_TARGET": "0",                                   # no V80 Lite target in Jakarta
        "PREV_START": "2026-10-01", "PREV_END": "2026-10-31", "PREV_LABEL": "Oct-26",
        "LY_LABEL": "Nov-25",
    },
    "tangban": {
        "START": "2026-11-15", "END": "2026-12-31",
        "TARGET_TABLE": "master_data.target_sbd_vivo_tangban",
        "V80_TARGET": "`Target V80 Lite`",
        "PREV_START": "2026-09-29", "PREV_END": "2026-11-14", "PREV_LABEL": "Prev 47 days",   # same length, just before
        "LY_LABEL": "15 Nov-31 Dec 25",
    },
}

template = (ROOT / "sql" / "sbd_template.sql").read_text(encoding="utf-8")
client = bigquery.Client(project=PROJECT, location="asia-southeast2")
wanted = sys.argv[1:] or list(EVENTS)

for name in wanted:
    cfg = dict(EVENTS[name], EVENT=name)
    sql = template
    for k, v in cfg.items():
        sql = sql.replace(f"@@{k}@@", v)
    if "@@" in sql:
        sys.exit(f"{name}: unfilled placeholder in template")

    # 1) dry run = free cost check
    dry = client.query(sql, job_config=bigquery.QueryJobConfig(dry_run=True, use_query_cache=False))
    gb = dry.total_bytes_processed / 1e9
    print(f"[{name}] dry run: will scan {gb:.2f} GB")
    if gb > MAX_GB:
        sys.exit(f"[{name}] aborting: scan {gb:.2f} GB is above MAX_GB={MAX_GB}")

    # 2) real run, capped so a bad edit can never bill more than MAX_GB
    job = client.query(sql, job_config=bigquery.QueryJobConfig(
        maximum_bytes_billed=int(MAX_GB * 1e9), labels={"app": "sbd-vivo-dashboard", "area": name}))
    data = json.loads(next(iter(job.result()))["j"])
    print(f"[{name}] billed {job.total_bytes_billed / 1e9:.2f} GB · targets {len(data['targets'])} · "
          f"sales rows {len(data['sales'])} · today rows {len(data['today'])} · borongan {len(data['borongan'])}")

    out = ROOT / "data" / f"{name}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[{name}] wrote {out.relative_to(ROOT)} ({out.stat().st_size / 1024:.1f} KB)")
