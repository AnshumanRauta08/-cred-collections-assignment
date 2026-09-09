-- ============================================================================
-- 02_metrics.sql — independent metric definitions (Postgres 14+)
-- ============================================================================
-- DEPENDS ON: 01_golden_cleaning.sql (clean.* / golden.* views).
-- Each metric is a standalone CTE ending in a final SELECT per metric, plus a
-- unified monthly KPI mart at the end. All denominators use GOLDEN (deduped)
-- objects; every definition states the NAIVE version and what it gets wrong.
--
-- RPC codebook (stable across legacy/v1/v2 — see 01 STEP 6):
--   RPC (right-party contact) = PROMISE_TO_PAY, PTP, PAID, CALLBACK, DISPUTE,
--     REFUSED — a human conversation happened.
--   NON-RPC connects = NO_CONTACT, WRONG_NUMBER. PTP_BROKEN is a follow-up
--     outcome counted in kept-rate, not in RPC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- M1 · CONTACT RATE = ANSWERED calls / deduped calls
-- Why: measures dialler+pickup efficiency on real dials.
-- Naive error: ANSWERED / raw calls (incl. 1,271 full dups + 1,350 dup call_id)
--   inflates dials; or ANSWERED / call_attempts (attempt legs ≠ calls) which
--   mixes RINGING/FAILED legs into the denominator.
-- ----------------------------------------------------------------------------
WITH golden_calls AS (
    SELECT * FROM golden.calls
),
contact_rate AS (
    SELECT
        COUNT(*) FILTER (WHERE call_status = 'ANSWERED')::NUMERIC
        / NULLIF(COUNT(*), 0) AS contact_rate,
        COUNT(*) FILTER (WHERE call_status = 'ANSWERED') AS answered_n,
        COUNT(*) AS deduped_calls_n
    FROM golden_calls
)
SELECT 'contact_rate' AS metric, contact_rate AS value, answered_n, deduped_calls_n
FROM contact_rate;

-- ----------------------------------------------------------------------------
-- M2 · RPC RATE = distinct RPC-disposition calls / ANSWERED calls (connects)
-- Why: of the humans reached, how many were the right party. Distinct call_id
--   numerator avoids double-counting multi-disposition edits on one call.
-- Naive error: RPC dispositions / ALL calls (dilutes with never-answered dials)
--   or counting disposition rows instead of distinct calls (multi-save bias).
-- ----------------------------------------------------------------------------
WITH connects AS (
    SELECT call_id FROM golden.calls WHERE call_status = 'ANSWERED'
),
rpc_calls AS (
    SELECT DISTINCT d.call_id
    FROM clean.dispositions d
    JOIN connects c USING (call_id)
    WHERE d.is_rpc
)
SELECT 'rpc_rate' AS metric,
       (SELECT COUNT(*)::NUMERIC FROM rpc_calls)
       / NULLIF((SELECT COUNT(*) FROM connects), 0) AS value,
       (SELECT COUNT(*) FROM rpc_calls) AS rpc_calls_n,
       (SELECT COUNT(*) FROM connects)  AS connects_n;

-- ----------------------------------------------------------------------------
-- M3 · PTP RATE = distinct PTP-logged calls / RPC calls
-- Why: promise skill conditional on actually reaching the right party.
-- Naive error: PTPs / all calls (punishes teams with bad lists, not bad pitch)
--   or PTP disposition rows / connects (double-counts PTP+PROMISE_TO_PAY dual
--   saves on the same call — the conformed is_ptp_logged flag fixes this).
-- ----------------------------------------------------------------------------
WITH rpc_calls AS (
    SELECT DISTINCT d.call_id
    FROM clean.dispositions d
    JOIN golden.calls c USING (call_id)
    WHERE c.call_status = 'ANSWERED' AND d.is_rpc
),
ptp_calls AS (
    SELECT DISTINCT d.call_id
    FROM clean.dispositions d
    JOIN golden.calls c USING (call_id)
    WHERE c.call_status = 'ANSWERED' AND d.is_ptp_logged
)
SELECT 'ptp_rate' AS metric,
       (SELECT COUNT(*)::NUMERIC FROM ptp_calls)
       / NULLIF((SELECT COUNT(*) FROM rpc_calls), 0) AS value,
       (SELECT COUNT(*) FROM ptp_calls) AS ptp_calls_n,
       (SELECT COUNT(*) FROM rpc_calls) AS rpc_calls_n;

-- ----------------------------------------------------------------------------
-- M4 · PTP KEPT RATE (VALIDATED) = cash-validated PTPs / all PTPs
-- Why: honour = SUCCESS payment within [promised_date-1d, +7d] (01 STEP 7).
-- Naive error: status='KEPT' / all PTPs — self-reported; counts KEPT with no
--   cash and misses 4,415 OPEN rows (4,128 stale) that actually paid.
-- ----------------------------------------------------------------------------
WITH ptp AS (
    SELECT * FROM golden.ptp_validated
)
SELECT 'ptp_kept_rate_validated' AS metric,
       AVG(is_kept_validated::INT)::NUMERIC AS value,
       COUNT(*) FILTER (WHERE is_kept_validated) AS kept_validated_n,
       COUNT(*) AS ptps_n,
       -- disagreement audit: self-reported KEPT with NO cash found
       COUNT(*) FILTER (WHERE reported_status = 'KEPT' AND NOT is_kept_validated) AS kept_claimed_unvalidated_n
FROM ptp;

-- ----------------------------------------------------------------------------
-- M5 · RECOVERY RATE (account-level) = accounts with ≥1 SUCCESS / active base
-- M6 · RECOVERY PER ACCOUNT = SUCCESS amount / accounts in base
-- Why (both): money metrics run ONLY on golden.payments (SUCCESS, deduped).
--   Base = accounts ever ACTIVE/DELINQUENT (excludes never-due artefacts).
-- Naive error: SUM over raw payments (+486 full dups, +500 dup IDs, PENDING as
--   cash) and / all accounts rows incl. CLOSED/WRITEOFF (denominator bias).
-- ----------------------------------------------------------------------------
WITH base AS (
    SELECT DISTINCT account_id FROM staging.accounts
    WHERE status IN ('ACTIVE', 'DELINQUENT', 'PTP', 'NPA')
),
recovered AS (
    SELECT account_id, SUM(amount) AS recovered_amt
    FROM golden.payments
    GROUP BY account_id
)
SELECT 'recovery_rate_accounts' AS metric,
       COUNT(r.account_id)::NUMERIC / NULLIF((SELECT COUNT(*) FROM base), 0) AS value,
       COUNT(r.account_id) AS recovered_accounts_n,
       (SELECT COUNT(*) FROM base) AS base_accounts_n
FROM recovered r
UNION ALL
SELECT 'recovery_per_account',
       COALESCE(SUM(r.recovered_amt), 0) / NULLIF((SELECT COUNT(*) FROM base), 0),
       NULL, NULL
FROM recovered r;

-- ----------------------------------------------------------------------------
-- M7 · RECOVERY PER AGENT HOUR = SUCCESS amount / agent talk-hours
-- Why: effort denominator = SUM(agent_sessions logout-login) for VOICE/FIELD
--   agents, IST-normalised; numerator restricted to agent-attributed SUCCESS
--   payments linked via calls/direct agent tag. NULL-agent system legs excluded.
-- Naive error: / headcount (ignores part-time/logged-off rosters) or / raw call
--   count (rewards redialling, not collecting).
-- ----------------------------------------------------------------------------
WITH agent_hours AS (
    SELECT agent_id,
           SUM(EXTRACT(EPOCH FROM (logout_at - login_at)) / 3600.0) AS hours_n
    FROM staging.agent_sessions
    WHERE logout_at > login_at
    GROUP BY agent_id
),
agent_recovery AS (
    SELECT c.agent_id, SUM(g.amount) AS recovered_amt
    FROM golden.payments g
    JOIN golden.calls c
      ON c.account_id = g.account_id
     AND c.agent_id IS NOT NULL
     AND c.event_at_utc <= g.event_at_utc
     AND c.event_at_utc >= g.event_at_utc - INTERVAL '14 days'
    GROUP BY c.agent_id
)
SELECT 'recovery_per_agent_hour' AS metric,
       SUM(a.recovered_amt)::NUMERIC / NULLIF(SUM(h.hours_n), 0) AS value,
       SUM(a.recovered_amt) AS attributed_recovery_amt,
       SUM(h.hours_n) AS total_agent_hours
FROM agent_recovery a
JOIN agent_hours h USING (agent_id);

-- ----------------------------------------------------------------------------
-- M8 · COST PER RUPEE = telephony+field cost / SUCCESS recovery
-- Why: unit economics of collection. Cost inputs live OUTSIDE the event dump
--   (vendor rate-cards); this query scaffolds the join so finance can plug
--   rates without touching numerators.
-- Naive error: cost / raw recovery (phantom dups flatter cost) or ignoring
--   NULL-agent system legs (their vendor cost still counts).
-- Columns expected: finance.vendor_rates(vendor_id, channel, cost_per_min,
--   cost_per_msg, cost_per_visit, valid_from, valid_to).
-- ----------------------------------------------------------------------------
WITH recovery AS (
    SELECT COALESCE(SUM(amount), 0) AS recovered_amt FROM golden.payments
),
-- PLACEHOLDER: replace 0.0 rates with finance.vendor_rates join when available.
call_cost AS (
    SELECT COALESCE(SUM(
        CASE WHEN c.duration_sec > 0 THEN c.duration_sec / 60.0 * 1.0 ELSE 0 END
    ), 0) AS cost_amt
    FROM golden.calls c
)
SELECT 'cost_per_rupee' AS metric,
       (SELECT cost_amt FROM call_cost)
       / NULLIF((SELECT recovered_amt FROM recovery), 0) AS value;

-- ----------------------------------------------------------------------------
-- M9 · CHANNEL CONVERSION = accounts paying ≤7d after touch / accounts touched
-- Why: per-channel (VOICE incl. calls, WHATSAPP, SMS, FIELD) next-7-day payment
--   lift on deduped touches; an account touched on 2 channels credits BOTH
--   (reach), or use first-touch attribution in 03_ for incrementality.
-- Naive error: touches = raw event rows (message retries triple-count reach);
--   window = any-later payment (credits a Diwali blast for a March payment).
-- ----------------------------------------------------------------------------
WITH touches AS (
    SELECT account_id, event_at_utc::DATE AS touch_date, 'VOICE'::TEXT AS channel
    FROM golden.calls WHERE call_status = 'ANSWERED'
    UNION ALL
    SELECT account_id, event_at::DATE, 'WHATSAPP' FROM staging.whatsapp_events
    WHERE event_type IN ('SENT', 'DELIVERED', 'READ')
    UNION ALL
    SELECT account_id, event_at::DATE, 'SMS' FROM staging.sms_events
    WHERE event_type IN ('SENT', 'DELIVERED')
    UNION ALL
    SELECT account_id, event_at::DATE, 'FIELD' FROM staging.field_visits
),
deduped_touches AS (
    SELECT DISTINCT account_id, touch_date, channel FROM touches
),
converted AS (
    SELECT t.*,
           EXISTS (
               SELECT 1 FROM golden.payments g
               WHERE g.account_id = t.account_id
                 AND g.event_at_utc::DATE BETWEEN t.touch_date AND (t.touch_date + INTERVAL '7 days')::DATE
           ) AS paid_7d
    FROM deduped_touches t
)
SELECT channel,
       AVG(paid_7d::INT)::NUMERIC AS conversion_7d,
       COUNT(*) AS touched_accounts_n,
       COUNT(*) FILTER (WHERE paid_7d) AS converted_n
FROM converted
GROUP BY channel
ORDER BY conversion_7d DESC;

-- ----------------------------------------------------------------------------
-- UNIFIED MONTHLY KPI MART (feeds 03_ Q1; IST month grain, golden only)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW golden.monthly_kpi AS
WITH months AS (
    SELECT generate_series(
        DATE_TRUNC('month', (SELECT MIN(event_at_ist) FROM golden.payments)),
        DATE_TRUNC('month', (SELECT MAX(event_at_ist) FROM golden.payments)),
        INTERVAL '1 month') AS mon
),
rec AS (
    SELECT DATE_TRUNC('month', event_at_ist) AS mon,
           SUM(amount) AS recovered_amt,
           COUNT(DISTINCT account_id) AS recovered_accounts
    FROM golden.payments GROUP BY 1
),
con AS (
    SELECT DATE_TRUNC('month', event_at_ist) AS mon,
           COUNT(*) AS calls_n,
           COUNT(*) FILTER (WHERE call_status = 'ANSWERED') AS answered_n
    FROM golden.calls GROUP BY 1
)
SELECT m.mon,
       EXTRACT(DAY FROM (m.mon + INTERVAL '1 month' - INTERVAL '1 day'))::INT AS days_in_month,
       COALESCE(r.recovered_amt, 0)      AS recovered_amt,
       COALESCE(r.recovered_accounts, 0) AS recovered_accounts,
       COALESCE(c.calls_n, 0)            AS calls_n,
       COALESCE(c.answered_n, 0)         AS answered_n,
       COALESCE(r.recovered_amt, 0)
         / NULLIF(EXTRACT(DAY FROM (m.mon + INTERVAL '1 month' - INTERVAL '1 day'))::INT, 0)
         AS recovered_per_day
FROM months m
LEFT JOIN rec r USING (mon)
LEFT JOIN con c USING (mon)
ORDER BY m.mon;
