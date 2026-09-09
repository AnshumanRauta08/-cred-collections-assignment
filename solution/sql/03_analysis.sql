-- ============================================================================
-- 03_analysis.sql — Q1–Q4 analytical queries (Postgres 14+)
-- ============================================================================
-- DEPENDS ON: 01_golden_cleaning.sql, 02_metrics.sql.
-- Grain notes: money = golden.payments (SUCCESS, deduped); time = IST civil
--   month/day (event_at_ist); population frame always stated (targeted vs all).
-- ============================================================================

-- ============================================================================
-- Q1 · MONTHLY RECOVERY: raw vs golden vs per-day normalised
-- Forensic headline: Feb→Mar raw recovery rises +11.03%, but Feb has 28 days
--   and Mar has 31 (31/28 = +10.71% calendar lift). Per-day recovery rises only
--   +0.29% → NO operational improvement; the "growth" is a calendar artefact.
-- Naive error: charting raw monthly SUM (and worse, raw incl. dups/PENDING)
--   and narrating +11% MoM as performance. Always show all three columns.
-- ============================================================================
WITH raw_monthly AS (
    -- RAW: as-naively-summed (dups + all statuses). For debunk comparison only.
    SELECT DATE_TRUNC('month', (event_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata') AS mon,
           SUM(amount) AS raw_amt
    FROM staging.payments
    GROUP BY 1
),
golden_monthly AS (
    SELECT DATE_TRUNC('month', event_at_ist) AS mon,
           SUM(amount) AS golden_amt,
           COUNT(*) AS golden_payments_n
    FROM golden.payments
    GROUP BY 1
),
per_day AS (
    SELECT g.*,
           EXTRACT(DAY FROM (g.mon + INTERVAL '1 month' - INTERVAL '1 day'))::INT AS days_in_month,
           g.golden_amt / EXTRACT(DAY FROM (g.mon + INTERVAL '1 month' - INTERVAL '1 day'))::INT AS golden_per_day
    FROM golden_monthly g
)
SELECT r.mon,
       r.raw_amt,
       p.golden_amt,
       (p.golden_amt - r.raw_amt) AS dup_and_nonsuccess_phantom,  -- negative = raw overstates
       p.days_in_month,
       ROUND(p.golden_per_day, 2) AS golden_per_day,
       ROUND(100.0 * (p.golden_amt / NULLIF(LAG(p.golden_amt) OVER (ORDER BY p.mon), 0) - 1), 2) AS mom_raw_pct,
       ROUND(100.0 * (p.golden_per_day / NULLIF(LAG(p.golden_per_day) OVER (ORDER BY p.mon), 0) - 1), 2) AS mom_per_day_pct
FROM raw_monthly r
JOIN per_day p USING (mon)
ORDER BY r.mon;
-- Expected read: Feb→Mar mom_raw_pct ≈ +11.03, mom_per_day_pct ≈ +0.29.

-- Q1b · Feb→Mar spotlight (one-row viva exhibit)
WITH m AS (
    SELECT DATE_TRUNC('month', event_at_ist) AS mon, SUM(amount) AS amt
    FROM golden.payments GROUP BY 1
),
feb AS (SELECT amt FROM m WHERE mon = DATE_TRUNC('month', TO_DATE('2026-02-01','YYYY-MM-DD'))),
mar AS (SELECT amt FROM m WHERE mon = DATE_TRUNC('month', TO_DATE('2026-03-01','YYYY-MM-DD')))
SELECT ROUND(100.0 * ((SELECT amt FROM mar) / NULLIF((SELECT amt FROM feb), 0) - 1), 2) AS raw_mom_pct,
       ROUND(100.0 * (((SELECT amt FROM mar) / 31.0) / NULLIF(((SELECT amt FROM feb) / 28.0), 0) - 1), 2) AS per_day_mom_pct,
       '31/28 = +10.71% pure calendar lift; residual ≈ +0.29% is noise'::TEXT AS verdict;

-- ============================================================================
-- Q2 · MIX ANALYSIS: DPD band / risk segment / loan type / state
-- Question: is recovery moving because of EFFORT or because the MIX shifted
--   (more low-DPD / LOW-risk / BNPL paper, friendlier states)?
-- Method: recovery per account + recovery rate WITHIN each mix cell, plus the
--   cell's share of outstanding. A rising headline with flat within-cell rates
--   = mix effect, not performance. DPD bands use standard buckets.
-- Naive error: comparing absolute recovery across segments with different
--   outstanding balances (big book always "wins") or pooling DPD 0–180.
-- ============================================================================
-- Q2a · DPD band × risk segment matrix (within-cell efficiency)
WITH base AS (
    SELECT a.account_id, a.outstanding_amount,
           CASE WHEN a.dpd <= 0 THEN 'CURRENT'
                WHEN a.dpd BETWEEN 1 AND 30 THEN 'DPD 1-30'
                WHEN a.dpd BETWEEN 31 AND 60 THEN 'DPD 31-60'
                WHEN a.dpd BETWEEN 61 AND 90 THEN 'DPD 61-90'
                WHEN a.dpd BETWEEN 91 AND 180 THEN 'DPD 91-180'
                ELSE 'DPD 180+' END AS dpd_band,
           a.risk_segment, a.loan_type
    FROM staging.accounts a
),
rec AS (
    SELECT account_id, SUM(amount) AS recovered_amt
    FROM golden.payments GROUP BY account_id
)
SELECT b.dpd_band, b.risk_segment,
       COUNT(*) AS accounts_n,
       COUNT(r.account_id) AS recovered_accounts_n,
       ROUND(100.0 * COUNT(r.account_id)::NUMERIC / NULLIF(COUNT(*), 0), 2) AS recovery_rate_pct,
       ROUND(COALESCE(SUM(r.recovered_amt), 0) / NULLIF(COUNT(*), 0), 2) AS recovery_per_account,
       ROUND(COALESCE(SUM(r.recovered_amt), 0) / NULLIF(SUM(b.outstanding_amount), 0), 4) AS recovery_per_outstanding_rupee
FROM base b
LEFT JOIN rec r USING (account_id)
GROUP BY b.dpd_band, b.risk_segment
ORDER BY b.dpd_band, recovery_rate_pct DESC;

-- Q2b · Loan type × state (top states by book; flags geographic concentration)
WITH base AS (
    SELECT a.account_id, a.loan_type,
           COALESCE(NULLIF(TRIM(b.state), ''), 'UNKNOWN') AS state,
           a.outstanding_amount
    FROM staging.accounts a
    LEFT JOIN clean.borrowers b USING (borrower_id)
),
rec AS (
    SELECT account_id, SUM(amount) AS recovered_amt
    FROM golden.payments GROUP BY account_id
)
SELECT b.loan_type, b.state,
       COUNT(*) AS accounts_n,
       ROUND(100.0 * COUNT(r.account_id)::NUMERIC / NULLIF(COUNT(*), 0), 2) AS recovery_rate_pct,
       ROUND(COALESCE(SUM(r.recovered_amt), 0) / NULLIF(COUNT(*), 0), 2) AS recovery_per_account
FROM base b
LEFT JOIN rec r USING (account_id)
GROUP BY b.loan_type, b.state
ORDER BY accounts_n DESC
LIMIT 30;

-- ============================================================================
-- Q3 · TARGETING: volume vs efficiency (selection-bias aware)
-- Forensic: 45,000 targeting rows → 23,344 distinct accounts; 6,656 accounts
--   NEVER targeted. Targeted cohorts skew toward contactable paper, so a raw
--   targeted-vs-untargeted gap is partly cherry-picking.
-- Method: (a) daily volume vs next-7-day conversion; (b) targeted vs
--   never-targeted recovery side-by-side; (c) priority/channel efficiency.
-- Naive error: reporting CONTACTED-rate on targeted only as "campaign ROI".
-- ============================================================================
-- Q3a · Daily targeting volume vs next-7-day payment conversion
WITH daily_vol AS (
    SELECT target_date, COUNT(*) AS targets_n,
           COUNT(DISTINCT account_id) AS accounts_targeted_n
    FROM clean.targeting GROUP BY 1
),
daily_conv AS (
    SELECT t.target_date,
           COUNT(DISTINCT t.account_id) AS targeted_n,
           COUNT(DISTINCT g.account_id) AS paid_7d_n
    FROM (SELECT DISTINCT target_date, account_id FROM clean.targeting) t
    LEFT JOIN golden.payments g
      ON g.account_id = t.account_id
     AND g.event_at_utc::DATE BETWEEN t.target_date AND (t.target_date + INTERVAL '7 days')::DATE
    GROUP BY 1
)
SELECT v.target_date, v.targets_n, v.accounts_targeted_n,
       c.paid_7d_n,
       ROUND(100.0 * c.paid_7d_n::NUMERIC / NULLIF(c.targeted_n, 0), 2) AS conv_7d_pct
FROM daily_vol v
JOIN daily_conv c USING (target_date)
ORDER BY v.target_date;

-- Q3b · Targeted vs never-targeted (bias-explicit benchmark)
WITH targeted AS (
    SELECT DISTINCT account_id FROM clean.targeting
),
rec AS (
    SELECT account_id, SUM(amount) AS recovered_amt
    FROM golden.payments GROUP BY account_id
)
SELECT 'TARGETED' AS cohort, COUNT(*) AS accounts_n,
       COUNT(r.account_id) AS recovered_n,
       ROUND(100.0 * COUNT(r.account_id)::NUMERIC / NULLIF(COUNT(*), 0), 2) AS recovery_rate_pct
FROM targeted t LEFT JOIN rec r USING (account_id)
UNION ALL
SELECT 'NEVER_TARGETED', COUNT(*), COUNT(r.account_id),
       ROUND(100.0 * COUNT(r.account_id)::NUMERIC / NULLIF(COUNT(*), 0), 2)
FROM quarantine.never_targeted_accounts n
LEFT JOIN rec r USING (account_id);
-- Read: if TARGETED ≫ NEVER_TARGETED, part of the gap is selection (they were
--   chosen BECAUSE they looked collectable) — do not present as pure lift.

-- Q3c · Priority × recommended channel efficiency
SELECT t.priority, t.recommended_channel,
       COUNT(DISTINCT t.account_id) AS targeted_n,
       COUNT(DISTINCT g.account_id) AS paid_7d_n,
       ROUND(100.0 * COUNT(DISTINCT g.account_id)::NUMERIC
             / NULLIF(COUNT(DISTINCT t.account_id), 0), 2) AS conv_7d_pct
FROM (SELECT DISTINCT target_date, account_id, priority, recommended_channel FROM clean.targeting) t
LEFT JOIN golden.payments g
  ON g.account_id = t.account_id
 AND g.event_at_utc::DATE BETWEEN t.target_date AND (t.target_date + INTERVAL '7 days')::DATE
GROUP BY t.priority, t.recommended_channel
ORDER BY t.priority, conv_7d_pct DESC;

-- ============================================================================
-- Q4 · COUNTERFACTUAL / DiD SCAFFOLD (what would recovery be WITHOUT the action?)
-- Use when leadership asks "did strategy v2 / the March push WORK?" — a before/
-- after on the treated group alone is confounded by calendar + mix (see Q1/Q2).
-- Design: TREATMENT = accounts exposed to the new strategy/campaign after
--   cutoff; CONTROL = matched unexposed accounts (same DPD band + risk + loan
--   type, never-targeted pool is a natural candidate — see 01 STEP 8).
--   DiD = (T_post − T_pre) − (C_post − C_pre), per-day normalised.
-- Naive error: post-vs-pre on treated only (absorbs Feb28→Mar31 artefact), or
--   control = all untargeted (mix-mismatched). Match on DPD/risk/loan first.
-- STATUS: scaffold — fill treatment_rule + cutoff, then run. Parallel-trends
--   check (pre-period gaps ≈ flat) is REQUIRED before trusting the estimate.
-- ============================================================================
-- Q4a · DiD template: set ::cutoff and the treatment flag, then run as one query
--   Suggested treatment_rule example: campaign_id IN (…v2 campaigns…) OR
--   strategy_version = 'v2' AND target_date >= cutoff. Control: matched
--   never-targeted or legacy-strategy accounts in the same DPD/risk/loan cell.
WITH params AS (
    SELECT DATE '2026-03-01' AS cutoff, INTERVAL '28 days' AS window_len
),
treated AS (
    SELECT DISTINCT t.account_id
    FROM clean.targeting t
    JOIN staging.campaigns c USING (campaign_id)
    WHERE c.strategy_version = 'v2'   -- <<< EDIT: treatment rule
),
population AS (
    SELECT a.account_id,
           (t.account_id IS NOT NULL) AS is_treated,
           CASE WHEN a.dpd <= 30 THEN 'LOW_DPD'
                WHEN a.dpd BETWEEN 31 AND 90 THEN 'MID_DPD'
                ELSE 'HIGH_DPD' END AS dpd_band,
           a.risk_segment, a.loan_type
    FROM staging.accounts a
    LEFT JOIN treated t USING (account_id)
),
period_recovery AS (
    SELECT p.*,
           CASE WHEN g.event_at_utc::DATE < (SELECT cutoff FROM params) THEN 'PRE' ELSE 'POST' END AS period,
           (g.amount / (SELECT EXTRACT(DAY FROM (SELECT window_len FROM params)))) AS amt_per_day_norm
    FROM population p
    LEFT JOIN golden.payments g ON g.account_id = p.account_id
        AND g.event_at_utc::DATE BETWEEN (SELECT cutoff FROM params) - (SELECT window_len FROM params)
                                     AND (SELECT cutoff FROM params) + (SELECT window_len FROM params) - INTERVAL '1 day'
)
SELECT is_treated, period,
       COUNT(DISTINCT account_id) AS accounts_n,
       COALESCE(SUM(amount), 0) AS recovered_amt,
       -- per-day normalisation neutralises unequal PRE/POST window lengths
       ROUND(COALESCE(SUM(amount), 0) / (SELECT EXTRACT(DAY FROM (SELECT window_len FROM params))), 2) AS recovered_per_day
FROM period_recovery
GROUP BY is_treated, period
ORDER BY is_treated DESC, period;
-- DiD estimate (per day) = (T_POST − T_PRE) − (C_POST − C_PRE). Compute from the
-- four cells above. REQUIREMENT: re-run grouped by week over PRE to confirm
-- parallel trends; if T and C diverge pre-cutoff, rematch the control pool.

-- Q4b · Parallel-trends check (run BEFORE trusting Q4a: weekly gap must be flat)
SELECT DATE_TRUNC('week', g.event_at_utc)::DATE AS wk,
       COUNT(DISTINCT CASE WHEN t.account_id IS NOT NULL THEN g.account_id END) AS treated_paid_n,
       COUNT(DISTINCT CASE WHEN t.account_id IS NULL THEN g.account_id END)     AS control_paid_n
FROM golden.payments g
LEFT JOIN (SELECT DISTINCT t.account_id FROM clean.targeting t
           JOIN staging.campaigns c USING (campaign_id)
           WHERE c.strategy_version = 'v2') t USING (account_id)
WHERE g.event_at_utc::DATE < DATE '2026-03-01'   -- PRE window only; match Q4a cutoff
GROUP BY 1
ORDER BY 1;
