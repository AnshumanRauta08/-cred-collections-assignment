#!/usr/bin/env python3
"""
CRED Collections — Golden pipeline (tracked source of truth).

Reads RAW CSVs -> writes GOLDEN CSVs + monthly_kpi + stats + daily series.
This is the script that actually produced solution/golden/*.csv/.json
(the SQL in sql/01_* mirrors this logic for warehouse deployment).

Usage:
    python build_golden.py [--data-dir PATH] [--out-dir PATH]
    CRED_DATA_DIR env var also honoured. Defaults are relative so the
    repo runs anywhere (no /Users/... hardcodes).

Example:
    python solution/build_golden.py --data-dir ./collections_30k_dataset --out-dir ./solution/golden
"""
from __future__ import annotations
import argparse
import json
import os
import sys
from pathlib import Path

import pandas as pd

DAYS = {
    "2026-01": 31, "2026-02": 28, "2026-03": 31, "2026-04": 30,
    "2026-05": 31, "2026-06": 30, "2026-07": 31,
}

def resolve_dirs(cli_data: str | None, cli_out: str | None) -> tuple[Path, Path]:
    here = Path(__file__).resolve().parent  # solution/
    default_data = Path(os.environ.get(
        "CRED_DATA_DIR",
        here.parent / "collections_30k_dataset (4)",
    ))
    # Fallback: sibling without " (4)" (e.g. after unzip rename)
    candidates = [Path(cli_data)] if cli_data else [default_data]
    if not cli_data:
        candidates.append(here.parent / "collections_30k_dataset")
        candidates.append(here / "collections_30k_dataset (4)")
    data_dir = next((c for c in candidates if c.exists()), candidates[0])
    out_dir = Path(cli_out) if cli_out else Path(os.environ.get("CRED_OUT_DIR", here / "golden"))
    return data_dir, out_dir


def build(data_dir: Path, out_dir: Path) -> dict:
    if not data_dir.exists():
        sys.exit(f"DATA DIR NOT FOUND: {data_dir}\nSet --data-dir or CRED_DATA_DIR.")
    out_dir.mkdir(parents=True, exist_ok=True)

    # ---- Payments (money truth) ----
    pay_raw = pd.read_csv(data_dir / "payments.csv", low_memory=False)
    raw_n = len(pay_raw)
    raw_success = (pay_raw["payment_status"] == "SUCCESS").sum()
    raw_sum = float(pay_raw.loc[pay_raw["payment_status"] == "SUCCESS", "amount"].sum())
    pay = pay_raw.drop_duplicates().drop_duplicates(subset=["payment_id"], keep="first")
    gold = pay[pay["payment_status"] == "SUCCESS"].copy()
    gold["event_at_utc"] = pd.to_datetime(gold["event_at"], utc=True)
    gold["event_ist"] = gold["event_at_utc"].dt.tz_convert("Asia/Kolkata")
    gold["month"] = gold["event_at_utc"].dt.to_period("M").astype(str)
    gold.to_csv(out_dir / "golden_payments.csv", index=False)

    # ---- Calls (effort truth) ----
    calls = pd.read_csv(data_dir / "calls.csv", low_memory=False)
    calls_g = calls.drop_duplicates().drop_duplicates(subset=["call_id"], keep="first").copy()
    calls_g["event_at_utc"] = pd.to_datetime(calls_g["event_at"], utc=True)
    calls_g["event_ist"] = calls_g["event_at_utc"].dt.tz_convert("Asia/Kolkata")
    calls_g.to_csv(out_dir / "golden_calls.csv", index=False)

    # ---- Borrowers (entity resolution: keep earliest created_at per ID) ----
    brw = pd.read_csv(data_dir / "borrowers.csv", low_memory=False)
    brw["created_at_dt"] = pd.to_datetime(brw["created_at"], utc=True, errors="coerce")
    brw_g = brw.sort_values("created_at_dt").drop_duplicates(subset=["borrower_id"], keep="first")
    brw_g.to_csv(out_dir / "golden_borrowers.csv", index=False)

    # ---- Agents (entity resolution: keep MIN(joined_at) per ID) ----
    agents = pd.read_csv(data_dir / "agents.csv", low_memory=False)
    agents["joined_at_dt"] = pd.to_datetime(agents["joined_at"], utc=True, errors="coerce")
    agents_g = agents.sort_values("joined_at_dt").drop_duplicates(subset=["agent_id"], keep="first")
    agents_g.to_csv(out_dir / "golden_agents.csv", index=False)

    # ---- Monthly KPI (Jan–Jul only; Aug partial excluded) ----
    targ = pd.read_csv(data_dir / "daily_targeting.csv")
    targ["month"] = pd.to_datetime(targ["target_date"]).dt.to_period("M").astype(str)
    kpi = (
        gold[gold["month"].isin(DAYS)]
        .groupby("month")
        .agg(total=("amount", "sum"), n=("amount", "size"), uniq_accts=("account_id", "nunique"))
    )
    kpi["per_day"] = kpi["total"] / kpi.index.map(DAYS)
    kpi["target_rows"] = targ.groupby("month").size()
    kpi["per_row"] = kpi["total"] / kpi["target_rows"]
    kpi["mom_raw"] = kpi["total"].pct_change() * 100
    kpi["mom_perday"] = kpi["per_day"].pct_change() * 100
    kpi.to_csv(out_dir / "monthly_kpi.csv")

    # ---- Daily series (for formal Feb-vs-Mar test) ----
    daily = gold.groupby(gold["event_at_utc"].dt.date)["amount"].sum()
    pd.DataFrame({"date": list(daily.index), "total": list(daily.values)}).to_csv(
        out_dir / "daily_recovery.csv", index=False
    )

    stats = {
        "raw_rows": int(raw_n),
        "raw_success_n": int(raw_success),
        "raw_success_sum": raw_sum,
        "gold_success_n": int(len(gold)),
        "gold_success_sum": float(gold["amount"].sum()),
        "removed_n": int(raw_success - len(gold)),
        "removed_pct": float((raw_success - len(gold)) / raw_success * 100),
        "gold_calls_n": int(len(calls_g)),
        "gold_borrowers_n": int(len(brw_g)),
        "gold_agents_n": int(len(agents_g)),
        "kpi": {
            k: {
                "total": float(v.total), "per_day": float(v.per_day),
                "per_row": float(v.per_row),
                "mom_raw": float(v.mom_raw) if pd.notna(v.mom_raw) else None,
                "mom_perday": float(v.mom_perday) if pd.notna(v.mom_perday) else None,
            }
            for k, v in kpi.iterrows()
        },
    }
    (out_dir / "stats.json").write_text(json.dumps(stats, indent=2))
    print(f"golden_payments {len(gold)} | calls {len(calls_g)} | "
          f"borrowers {len(brw_g)} | agents {len(agents_g)} -> {out_dir}")
    return stats


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default=None)
    ap.add_argument("--out-dir", default=None)
    a = ap.parse_args()
    data_dir, out_dir = resolve_dirs(a.data_dir, a.out_dir)
    print(f"data: {data_dir}\nout:  {out_dir}")
    build(data_dir, out_dir)


if __name__ == "__main__":
    main()
