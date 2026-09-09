-- ============================================================================
-- 01_golden_cleaning.sql — staging → clean → golden (Postgres 14+)
-- ============================================================================
-- PURPOSE
--   Single source of truth for all downstream metrics (02_) and analysis (03_).
--   Run order: 01 → 02 → 03. Idempotent: safe to re-run (OR REPLACE + NOT EXISTS).
--
-- CONVENTIONS
--   staging.*  : raw COPY of the 17 CSVs, zero transforms (types only).
--   clean.*    : deduped + type-fixed + timezone-normalised, one row per grain.
--   golden.*   : business-truth marts with exclusion rules applied.
--   quarantine.* : rows excluded from golden, retained for audit (never dropped).
--
-- SOURCE-OF-TRUTH DECISIONS (forensic facts are REQUIREMENTS, not re-derived)
--   1. payments  — DROP full-row dups, KEEP first payment_id, ONLY SUCCESS counts.
--   2. calls     — dedup on call_id, normalise event_at to UTC then Asia/Kolkata.
--   3. borrowers — dedup on borrower_id KEEP earliest created_at.
--   4. agents    — resolve on agent_id KEEP MIN(joined_at); ignore name/employee_code.
--   5. history   — event_at is truth; recorded_at is late-arrival metadata only.
--   6. dispo     — legacy/v1/v2 share the same 9 codes; NO remapping.
--   7. PTP       — KEPT is valid ONLY with a SUCCESS payment within 7 days.
--   8. targeting — never-targeted accounts are selection bias, quarantined not joined.
-- ============================================================================

SET statement_timeout = 0;
SET client_min_messages = WARNING;

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS golden;
CREATE SCHEMA IF NOT EXISTS quarantine;

-- ============================================================================
-- STEP 0 — STAGING CONTRACT (load once via COPY; types only, no business logic)
-- Timestamps arrive as 'YYYY-MM-DD HH24:MI:SS' wall-clock STRINGS already in UTC.
-- Load them as TIMESTAMP (without tz) so the normalisation below is explicit
-- and auditable via AT TIME ZONE, instead of hiding it in the COPY cast.
-- ============================================================================
-- Example (run once per CSV):
--   CREATE TABLE IF NOT EXISTS staging.payments (
--     payment_id TEXT, account_id TEXT, borrower_id TEXT,
--     event_at TIMESTAMP, payment_reference TEXT, amount NUMERIC,
--     payment_status TEXT, payment_method TEXT, provider_id TEXT);
--   COPY staging.payments FROM '/path/payments.csv' WITH (FORMAT csv, HEADER true);
-- (Repeat for borrowers, accounts, agents, agent_sessions, campaigns,
--  daily_targeting, calls, call_attempts, call_dispositions, whatsapp_events,
--  sms_events, field_visits, promises_to_pay, vendor_telephony, complaints,
--  account_status_history.)

-- ============================================================================
-- STEP 1 — BORROWERS
-- Forensic impact: 30,600 rows → 11,015 unique borrower_id (~2.78 rows per ID).
--   Same ID carries DIFFERENT name/phone/email across rows (SCD overwrite, no
--   version key). 50.18% of rows have updated_at < created_at (inverted audit
--   stamps — neither is trustworthy except MIN(created_at) for tenure).
--   1,204 phone collisions + 15,222 email collisions across IDs (phone/email
--   are NOT keys; re-used / family-shared / fat-fingered).
-- DECISION (golden rule): grain = borrower_id, KEEP earliest created_at row.
--   Rationale: borrower_id is the only join key used by every child table;
--   name/phone/email are attributes, never keys. MIN(created_at) is the only
--   monotone tenure signal. Orphans (child rows whose borrower_id never appears
--   here, or vice versa) go to quarantine for the join-bias audit.
-- ============================================================================
CREATE OR REPLACE VIEW clean.borrowers AS
SELECT DISTINCT ON (b.borrower_id)
    b.borrower_id,
    b.name,
    b.phone,
    b.email,
    b.city,
    b.state,
    b.created_at,
    b.updated_at
FROM staging.borrowers b
ORDER BY b.borrower_id, b.created_at ASC NULLS LAST;

-- Borrowers present in children but missing from master (orphan audit).
CREATE OR REPLACE VIEW quarantine.orphan_borrower_refs AS
SELECT DISTINCT p.borrower_id, 'payments'::TEXT AS source_table
FROM staging.payments p
WHERE p.borrower_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM staging.borrowers b WHERE b.borrower_id = p.borrower_id)
UNION ALL
SELECT DISTINCT c.borrower_id, 'calls'::TEXT
FROM staging.calls c
WHERE c.borrower_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM staging.borrowers b WHERE b.borrower_id = c.borrower_id);

-- ============================================================================
-- STEP 2 — AGENTS
-- Forensic impact: 30,000 rows → 1,000 unique agent_id (mean 30 snapshots/agent).
--   Only 10 distinct agent_name values and 1,099 employee_codes for 1,000 IDs:
--   names are shift/team labels, employee_codes are re-issued → BOTH untrusted.
-- DECISION (golden rule): grain = agent_id, tenure truth = MIN(joined_at).
--   Keep latest non-null vendor/team/status as slowly-changing attributes, but
--   NEVER aggregate or join on name/employee_code.
-- ============================================================================
CREATE OR REPLACE VIEW clean.agents AS
WITH ranked AS (
    SELECT
        a.agent_id,
        a.employee_code,
        a.agent_name,
        a.vendor_id,
        a.team,
        a.status,
        a.joined_at,
        a.updated_at,
        MIN(a.joined_at) OVER (PARTITION BY a.agent_id) AS tenure_start,
        ROW_NUMBER() OVER (
            PARTITION BY a.agent_id
            ORDER BY a.updated_at DESC NULLS LAST, a.joined_at DESC NULLS LAST
        ) AS rn
    FROM staging.agents a
)
SELECT
    agent_id,
    tenure_start AS joined_at,   -- tenure truth: first appearance, not snapshot date
    employee_code,               -- informational only — DO NOT JOIN on this
    agent_name,                  -- informational only — 10 labels for 1000 agents
    vendor_id,
    team,
    status
FROM ranked
WHERE rn = 1;

-- ============================================================================
-- STEP 3 — PAYMENTS (money table: strictest rules)
-- Forensic impact (n = 25,500 rows):
--   486 full-row duplicates (re-ingested batches)         → DROP all but one.
--   500 duplicate payment_id (same ID, different payload) → KEEP FIRST occurrence
--     by event_at (earliest = original webhook; later rows are retries/echoes).
--   4,297 duplicate payment_reference reused across DIFFERENT accounts/amounts
--     → reference is a PROVIDER-side batch/UTR echo, NOT a payment key. Never
--     dedup or join on payment_reference.
--   382 NULL payment_reference → excluded from any reference-level check, kept
--     for money totals if SUCCESS (null ref ≠ failed money).
-- DECISION (golden rule): grain = payment_id (first seen); ONLY SUCCESS counts
--   as recovery. PENDING / FAILED / REVERSED are EXCLUDED from every recovery
--   numerator (they are attempts/reversals, not cash). REVERSED is excluded even
--   if a sibling SUCCESS exists — netting happens in finance, not here.
-- Naive error this prevents: SUM(amount) over raw = +~2% phantom recovery from
--   dups, and +large phantom from counting PENDING as collected.
-- ============================================================================
CREATE OR REPLACE VIEW clean.payments_deduped AS
WITH no_full_dups AS (
    -- 486 full-row dups removed: DISTINCT over the full payload.
    SELECT DISTINCT
        payment_id, account_id, borrower_id, event_at,
        payment_reference, amount, payment_status, payment_method, provider_id
    FROM staging.payments
),
ranked AS (
    -- 500 dup payment_id: KEEP FIRST by event_at (original webhook).
    SELECT d.*,
           ROW_NUMBER() OVER (
               PARTITION BY d.payment_id
               ORDER BY d.event_at ASC NULLS LAST
           ) AS rn
    FROM no_full_dups d
)
SELECT
    payment_id, account_id, borrower_id, event_at,
    payment_reference, amount, payment_status, payment_method, provider_id
FROM ranked
WHERE rn = 1;

-- Reference-reuse audit (4,297 refs across different accounts/amounts + 382 nulls).
CREATE OR REPLACE VIEW quarantine.payment_reference_reuse AS
SELECT payment_reference, COUNT(*) AS rows_n,
       COUNT(DISTINCT account_id) AS accounts_n,
       COUNT(DISTINCT amount)     AS amounts_n
FROM clean.payments_deduped
WHERE payment_reference IS NOT NULL
GROUP BY payment_reference
HAVING COUNT(DISTINCT account_id) > 1 OR COUNT(DISTINCT amount) > 1;

-- GOLDEN money mart: SUCCESS only. Everything else is quarantined below.
CREATE OR REPLACE VIEW golden.payments AS
SELECT
    payment_id,
    account_id,
    borrower_id,
    -- Stored strings are UTC wall-clock: stamp as UTC, then derive IST.
    (event_at AT TIME ZONE 'UTC') AS event_at_utc,
    ((event_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata') AS event_at_ist,
    payment_reference,
    amount,
    payment_status,
    payment_method,
    provider_id
FROM clean.payments_deduped
WHERE payment_status = 'SUCCESS';

CREATE OR REPLACE VIEW quarantine.payments_excluded AS
SELECT *, 'non-SUCCESS excluded from recovery'::TEXT AS exclude_reason
FROM clean.payments_deduped
WHERE payment_status IS DISTINCT FROM 'SUCCESS';  -- PENDING/FAILED/REVERSED/NULL

-- ============================================================================
-- STEP 4 — CALLS + TIMEZONE NORMALISATION
-- Forensic impact (n = 91,350 rows):
--   1,271 full-row dups (vendor retries)  → DROP.
--   1,350 duplicate call_id               → KEEP FIRST by event_at.
--   1,827 NULL agent_id (IVR/autodialler legs with no human) → KEEP rows but
--     EXCLUDE from per-agent denominators (they are system traffic, not effort).
--   3 timezones (UTC / Asia_Kolkata / Asia_Dubai) stored as UTC STRINGS:
--     the event_at string is already UTC; the `timezone` column records capture
--     locale. Hour-of-day / day-of-week analytics MUST use Asia/Kolkata civil
--     time or Dubai evening calls misattribute to the wrong IST day-part.
-- DECISION: event_at_utc = event_at AT TIME ZONE 'UTC';
--           event_at_ist = event_at_utc AT TIME ZONE 'Asia/Kolkata'.
-- Naive error this prevents: GROUP BY event_at::date mixes three locales and
--   shifts ~Dubai-share of calls across the IST midnight boundary.
-- ============================================================================
CREATE OR REPLACE VIEW clean.calls AS
WITH no_full_dups AS (
    SELECT DISTINCT
        call_id, account_id, borrower_id, event_at,
        agent_id, campaign_id, direction, vendor_id,
        call_status, duration_sec, timezone
    FROM staging.calls
),
ranked AS (
    SELECT d.*,
           ROW_NUMBER() OVER (
               PARTITION BY d.call_id ORDER BY d.event_at ASC NULLS LAST
           ) AS rn
    FROM no_full_dups d
)
SELECT
    call_id,
    account_id,
    borrower_id,
    agent_id,                       -- NULL kept: 1,827 system/IVR legs
    campaign_id,
    direction,
    vendor_id,
    call_status,
    duration_sec,
    timezone AS capture_timezone,   -- provenance only; never used for bucketing
    (event_at AT TIME ZONE 'UTC') AS event_at_utc,
    ((event_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata') AS event_at_ist,
    DATE_TRUNC('day', ((event_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')) AS event_date_ist,
    EXTRACT(HOUR FROM ((event_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata'))::INT AS event_hour_ist
FROM ranked
WHERE rn = 1;

-- Golden calls: same rows, documented agent-attributed subset for denominators.
CREATE OR REPLACE VIEW golden.calls AS
SELECT *, (agent_id IS NOT NULL) AS is_agent_attributed
FROM clean.calls;

-- ============================================================================
-- STEP 5 — ACCOUNT_STATUS_HISTORY (clock skew)
-- Forensic impact: 60,000 rows, 30,191 with recorded_at < event_at (~50.3%).
--   recorded_at is write-arrival time from backfilled batches; it routinely
--   PREDATES the business event → causality inversion if used for sequencing.
-- DECISION: event_at is truth for state sequencing; recorded_at is retained ONLY
--   as late-arrival metadata (e.g. "as-known-at" reporting), never for ORDER BY
--   of status transitions.
-- ============================================================================
CREATE OR REPLACE VIEW clean.account_status_history AS
SELECT
    history_id,
    account_id,
    borrower_id,
    event_at  AS status_event_at,     -- TRUTH for sequencing
    recorded_at AS status_recorded_at, -- metadata only
    status,
    changed_by,
    source
FROM staging.account_status_history;

-- ============================================================================
-- STEP 6 — DISPOSITIONS (stable codebook, version is metadata)
-- Forensic: legacy/v1/v2 carry the SAME 9 codes
--   (CALLBACK, PROMISE_TO_PAY, PTP, NO_CONTACT, PAID, PTP_BROKEN, WRONG_NUMBER,
--    DISPUTE, REFUSED) with stable monthly shares → no semantic drift.
-- DECISION: NO cross-version remapping. Pass disposition_version through for
--   audit, and expose ONE conformed flag: PROMISE_TO_PAY and PTP both mean a
--   promise was logged (kept-vs-broken is decided in STEP 7 by cash, not here).
-- Naive error this prevents: "harmonising" PTP→PROMISE_TO_PAY per version and
--   double-counting months where both labels co-occur.
-- ============================================================================
CREATE OR REPLACE VIEW clean.dispositions AS
SELECT
    disposition_id,
    account_id,
    borrower_id,
    call_id,
    agent_id,
    disposition_code,
    disposition_version,  -- audit only; no mapping applied (shares stable)
    (event_at AT TIME ZONE 'UTC') AS event_at_utc,
    ((event_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata') AS event_at_ist,
    (disposition_code IN ('PROMISE_TO_PAY', 'PTP')) AS is_ptp_logged,
    (disposition_code IN ('PROMISE_TO_PAY', 'PTP', 'PAID', 'CALLBACK', 'DISPUTE', 'REFUSED')) AS is_rpc
FROM staging.call_dispositions;

-- ============================================================================
-- STEP 7 — PROMISES TO PAY: status flag is UNTRUSTED, cash is truth
-- Forensic impact: 4,415 rows stuck OPEN, of which 4,128 are past promised_date
--   (stale — collectors never closed them). status='KEPT' is self-reported.
-- DECISION (golden rule): a PTP is KEPT iff EXISTS a golden SUCCESS payment for
--   the same account with payment_date in [promised_date - 1d, promised_date + 7d].
--   The -1d grace covers early payers; +7d is the collections-standard honour
--   window. Status flag is carried for disagreement analysis only.
-- Naive error this prevents: kept-rate on status flag overstates honour by
--   counting self-marked KEPT with no cash and ignoring OPEN-but-paid rows.
-- ============================================================================
CREATE OR REPLACE VIEW golden.ptp_validated AS
SELECT
    p.ptp_id,
    p.account_id,
    p.borrower_id,
    p.agent_id,
    p.event_at AS ptp_event_at,
    (p.event_at AT TIME ZONE 'UTC') AS ptp_event_at_utc,
    p.promised_amount,
    p.promised_date::DATE AS promised_date,
    p.status AS reported_status,   -- UNTRUSTED: for disagreement audit only
    p.source,
    CASE
        WHEN pay.payment_id IS NOT NULL THEN 'KEPT_VALIDATED'
        WHEN p.status = 'KEPT'            THEN 'KEPT_UNVALIDATED_NO_CASH'
        WHEN p.status = 'OPEN'
             AND p.promised_date::DATE < CURRENT_DATE THEN 'OPEN_STALE'
        ELSE p.status
    END AS golden_ptp_outcome,
    (pay.payment_id IS NOT NULL) AS is_kept_validated,
    pay.payment_id  AS validating_payment_id,
    pay.amount      AS validating_amount
FROM staging.promises_to_pay p
LEFT JOIN LATERAL (
    SELECT g.payment_id, g.amount
    FROM golden.payments g
    WHERE g.account_id = p.account_id
      AND (g.event_at_utc::DATE BETWEEN (p.promised_date::DATE - INTERVAL '1 day')::DATE
                                    AND (p.promised_date::DATE + INTERVAL '7 days')::DATE)
    ORDER BY g.event_at_utc ASC
    LIMIT 1
) pay ON TRUE;

-- ============================================================================
-- STEP 8 — DAILY_TARGETING + SELECTION-BIAS QUARANTINE
-- Forensic impact: 45,000 targeting rows cover only 23,344 distinct accounts;
--   6,656 accounts were NEVER targeted (systematic exclusion, not random).
-- DECISION: targeting is an exposure flag, not the population frame. Any
--   funnel rate with "targeted" as denominator must show the never-targeted
--   cohort alongside, or efficiency gains are confounded with cherry-picking.
-- ============================================================================
CREATE OR REPLACE VIEW clean.targeting AS
SELECT
    target_id, account_id, campaign_id,
    target_date::DATE AS target_date,
    priority, recommended_channel, status
FROM staging.daily_targeting;

CREATE OR REPLACE VIEW quarantine.never_targeted_accounts AS
SELECT a.account_id
FROM staging.accounts a
WHERE NOT EXISTS (SELECT 1 FROM staging.daily_targeting t WHERE t.account_id = a.account_id);
-- Impact note: 6,656 accounts — keep as explicit control/benchmark cohort in 03_.

-- ============================================================================
-- STEP 9 — GOLDEN EXCLUSION LEDGER (audit: every excluded row is countable)
-- ============================================================================
CREATE OR REPLACE VIEW golden.exclusion_audit AS
SELECT 'payments: full-row dups dropped'         AS rule, 486  AS rows_impact UNION ALL
SELECT 'payments: dup payment_id keep-first',            500 UNION ALL
SELECT 'payments: non-SUCCESS excluded (PENDING/FAILED/REVERSED)',
  (SELECT COUNT(*) FROM quarantine.payments_excluded) UNION ALL
SELECT 'calls: full-row dups dropped',                  1271 UNION ALL
SELECT 'calls: dup call_id keep-first',                 1350 UNION ALL
SELECT 'calls: NULL agent_id kept, excluded from agent denominators', 1827 UNION ALL
SELECT 'borrowers: snapshots collapsed to borrower_id (30600→11015)', 19585 UNION ALL
SELECT 'agents: snapshots collapsed to agent_id (30000→1000)',        29000 UNION ALL
SELECT 'history: recorded_at<event_at rows resequenced on event_at',  30191 UNION ALL
SELECT 'ptp: OPEN stale past promised_date (kept needs cash proof)',   4128 UNION ALL
SELECT 'targeting: accounts never targeted (bias cohort)',             6656;
