-- 04_forensic_H.sql — Priority discrimination + stratified uplift (REVIEW 09-Sep)
-- H: per-target 7-day SUCCESS conversion by priority 1-10 (expect flat ~1.8%)
WITH targ AS (
  SELECT target_id, account_id, target_date::timestamptz AS t, priority
  FROM staging.daily_targeting
),
pay AS (
  SELECT account_id, event_at AS p FROM golden.fact_payment  -- SUCCESS only
)
SELECT priority,
  COUNT(*) AS n,
  COUNT(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM pay
    WHERE pay.account_id = targ.account_id
      AND pay.p BETWEEN targ.t AND targ.t + INTERVAL '7 days'
  ))::float / COUNT(*) AS conv_7d
FROM targ GROUP BY 1 ORDER BY 1;
-- Expect: 0.0156-0.0216, chi2 p=0.345 (no trend). If p<0.05 + monotonic, scoring discriminates.

-- Stratified targeted-vs-never ever-paid (DPD bucket x risk, golden Jan-Jul)
-- Overall: targeted 43.05% vs never 43.69% (diff -0.64pp, p=0.35, CI [-2.00pp,+0.70pp]);
-- MH-adjusted -0.65pp same CI => zero lift. See golden/stratified_uplift.json.
WITH elig AS (
  SELECT a.account_id, a.dpd_bucket, a.risk_segment,
    (t.account_id IS NOT NULL) AS ever_targeted,
    (p.account_id IS NOT NULL) AS ever_paid
  FROM golden.dim_account a
  LEFT JOIN (SELECT DISTINCT account_id FROM staging.daily_targeting) t USING (account_id)
  LEFT JOIN (SELECT DISTINCT account_id FROM golden.fact_payment) p USING (account_id)
)
SELECT dpd_bucket, risk_segment, ever_targeted,
  COUNT(*), AVG(ever_paid::float) AS conv
FROM elig GROUP BY 1,2,3 ORDER BY 1,2,3;
