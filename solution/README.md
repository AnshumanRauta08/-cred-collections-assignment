# CRED Collections — Data Analyst Assignment

**Verdict:** March's "+11% MoM" is a calendar illusion — per-day growth +0.29%, statistically flat (perm p=0.93). Invest ₹10 Cr in better targeting **as a capped experiment** (see `EXECUTIVE_MEMO_1PAGE.md`).

## Reproduce (any machine — no hardcoded paths)

```bash
pip install -r requirements.txt
python solution/build_golden.py      # raw CSVs -> solution/golden/ (or CRED_DATA_DIR=... )
python solution/run_analysis.py      # tests + stratified + executed DiD -> golden/*.json
jupyter lab solution/analysis_notebook.ipynb   # narrated reasoning (13 cells, executes clean)
```

`CRED_DATA_DIR` / `CRED_OUT_DIR` env vars (or `--data-dir` / `--out-dir` / `--golden-dir`) override the relative defaults (`../collections_30k_dataset*` next to `solution/`).

## Deliverables map (brief §Deliverables)

| Asked | File |
|---|---|
| SQL repository | `solution/sql/01_golden_cleaning.sql`, `02_metrics.sql`, `03_analysis.sql`, `04_forensic_H.sql`, `05_counterfactual_executed.sql` |
| Analysis notebook (reasoning) | `solution/analysis_notebook.ipynb` (+ legacy `analysis_notebook.py`) |
| Golden dataset / pipeline | `solution/build_golden.py` → `solution/golden/golden_{payments,calls,borrowers,agents}.csv`, `monthly_kpi.csv`, `stats.json`, `daily_recovery.csv` |
| Data Quality Report | `solution/DATA_QUALITY_REPORT.md` |
| Executive dashboard (1 screen, 60-sec) | `solution/dashboard.html` (+ `dashboard_spec.md`) |
| Executive memo (≤2 pp) | `solution/EXECUTIVE_MEMO_1PAGE.md` (CEO) + `solution/memo.md` (full) + `solution/MEMO_APPENDIX.md` (stats) |
| Architecture diagram | `solution/architecture.md` + `solution/architecture.mmd` |
| Counterfactual (executed) | `solution/run_analysis.py` → `solution/golden/counterfactual_did.json` (DiD −1.29pp, CI [−4.01pp,+1.40pp], 2,717 pairs — null) |
| Viva companion (bonus) | `CRED_Viva_Report.html` |

## Key numbers (all recomputed by the scripts above)

- Raw SUCCESS Feb ₹170.14M → Mar ₹188.91M (+10.99%; +11.03% deduped) → per-day +0.29% (p≈0.93).
- Dedup 17,880 → 17,534 (−346, −1.94%, ~₹2.9Cr); Jan–Jul golden ₹126.8Cr; 76,187 agent-hrs → ₹16,649/hr.
- Targeted 23,344 / never 6,656; stratified lift −0.65pp (p=0.35); priority 7d flat p=0.345.
