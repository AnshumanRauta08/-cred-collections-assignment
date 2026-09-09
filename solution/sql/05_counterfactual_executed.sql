-- 05_counterfactual_executed.sql — Executed PSM + DiD spec (matches golden/counterfactual_did.json)
-- Produced by solution/run_analysis.py (sklearn LogisticRegression, seed 7). Result: DiD -1.29pp, 95% CI [-4.01pp,+1.40pp], 2717 pairs. Null/weak first stage.
-- Design: Mar cutover; treat = Mar targeting under v2/v3; control = Mar legacy/v1-only;
--   pre = Jan-Feb ever-paid, post = Apr-May ever-paid (Mar skipped as transition).
--   1:1 nearest-neighbour PSM, caliper 0.05, on dpd / outstanding_amount / risk_segment / loan_type.

-- 1) Arm assignment (edit cutover here for sensitivity: '2026-03-01' / v2,v3 vs legacy,v1)
WITH mar AS (
  SELECT dt.account_id,
         MAX(CASE WHEN c.strategy_version IN ('v2','v3') THEN 1 ELSE 0 END) AS ever_new
  FROM staging.daily_targeting dt
  JOIN staging.campaigns c USING (campaign_id)
  WHERE dt.target_date >= DATE '2026-03-01' AND dt.target_date < DATE '2026-04-01'
  GROUP BY 1
),
base AS (
  SELECT a.account_id, a.dpd, a.outstanding_amount, a.risk_segment, a.loan_type,
         CASE WHEN m.ever_new = 1 THEN 1 ELSE 0 END AS treat,
         CASE WHEN EXISTS (SELECT 1 FROM golden.fact_payment p
                           WHERE p.account_id = a.account_id
                             AND p.event_at >= TIMESTAMPTZ '2026-01-01 UTC'
                             AND p.event_at <  TIMESTAMPTZ '2026-03-01 UTC') THEN 1 ELSE 0 END AS pre,
         CASE WHEN EXISTS (SELECT 1 FROM golden.fact_payment p
                           WHERE p.account_id = a.account_id
                             AND p.event_at >= TIMESTAMPTZ '2026-04-01 UTC'
                             AND p.event_at <  TIMESTAMPTZ '2026-06-01 UTC') THEN 1 ELSE 0 END AS post
  FROM golden.dim_account a
  JOIN mar m USING (account_id)
)
-- 2) PSM scores come from run_analysis.py (LogisticRegression on standardised dpd/outstanding + one-hot risk/loan);
--    join scores back here for audit, then 1:1 match within caliper 0.05 (see python for matcher).
-- 3) DiD on matched pairs with bootstrap CI (python, B=10k):
--    DiD = (treat_post - treat_pre) - (control_post - control_pre).
--    Executed: treat 14.39%->14.06%, control 14.76%->15.72%, DiD -1.29pp [-4.01pp,+1.40pp].
SELECT
  AVG(post - pre) FILTER (WHERE treat = 1)
    - AVG(post - pre) FILTER (WHERE treat = 0) AS did_pp_unmatched_naive
FROM base;
-- NOTE: the naive unmatched DiD above is NOT the reported estimate; the reported -1.29pp uses
-- the 2,717 caliper-matched pairs (balance |SMD|<0.05, see MEMO_APPENDIX.md §D). Re-run python for the matched CI.
