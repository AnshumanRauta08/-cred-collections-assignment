# CRED Collections — Production Architecture

> Context: Jan–Aug 2026 synthetic, 17 tables. Claim "Recovery +11% MoM" is FALSE — Mar +11.03% raw = Feb 28d→Mar 31d calendar effect (+0.29%/day) + targeting +10%; contact 19–20%, PTP-kept 24–25% flat. This design prevents recurrence.

## 1. Data flow (Raw → Dashboard)

```text
Sources (vendors/tele/app/field) → RAW (immutable, ingest_date)
→ STAGING (typed, IST, event_date) → CLEAN (dedup PK, FK-valid)
→ GOLDEN (dims/facts) → FEATURE (account-day)
→ METRICS (per-day KPI) → DASHBOARD (per-day + adjusted-MoM)
```

Full graph: `architecture.mmd` (flowchart TD). Rationale: linear lineage makes the Feb→Mar calendar bug impossible to hide.

## 2. Service boundaries (solo-builder, no microservices)

- One batch pipeline, not services: ingest → transform → serve as modules in one repo. Rationale: 30k rows, one owner.
- Layer contracts = versioned table schemas between stages (§3). Rationale: replaces APIs; keeps blame local.
- Orchestrator: Dagster/Airflow daily 02:00 IST partition job + dbt-SQL. Rationale: idempotent reruns, one cron to own.

## 3. Deployment topology

- Prod: one warehouse (BigQuery/Snowflake), partitioned by `event_date`, clustered by `account_id`. Rationale: partition-prune, cheap.
- Dev: Postgres/DuckDB same SQL. Rationale: zero-cost repro of prod logic.
- Serve: warehouse view → BI (Metabase/Looker), no app DB. Rationale: single source of truth.

## 4. Data contracts (PK = dedup grain; `event_at → event_at_ist → event_date`)

- `borrowers(borrower_id)` keep earliest `created_at`. Rationale: ID collisions from merges.
- `accounts(account_id)` keep latest `opened_at`; `agents(agent_id)` keep min `joined_at` + map `employee_code`. Rationale: multi-ID agents.
- `payments(payment_id)` + dedup `payment_reference` prefer SUCCESS. Rationale: dup events double-count recovery.
- `calls(call_id)`, `call_attempts(attempt_id)`, `call_dispositions(disposition_id)` latest per `call_id`. Rationale: legacy codes.
- `whatsapp/sms_events(*_event_id)` dedup `(message_id,event_type)`. Rationale: provider retries.
- `field_visits(visit_id)`, `promises_to_pay(ptp_id)` latest per account, `complaints(complaint_id)`.
- `campaigns(campaign_id)` latest `strategy_version`; `daily_targeting(target_id)` unique `(account_id,target_date)`.
- `agent_sessions(session_id)`, `vendor_telephony(vendor_id)`, `account_status_history(history_id)` order by `recorded_at`. Rationale: overwrite history.
- TZ rule: parse source tz (UTC/Dubai/Kolkata) → IST; reject naive. Rationale: cross-tz day misattribution.

## 5. Lineage

- `RAW.* → STAGING.* → CLEAN.* → GOLDEN.{dim_borrower, dim_account, fact_contact, fact_ptp, fact_payment} → FEATURE.account_day → METRICS.daily_kpi → dashboard`. Rationale: every KPI traces to a PK.
- Stale-PTP rule: PTP joins payment within 7d of `promised_date` only. Rationale: stops stale-PTP inflation.

## 6. Metric definitions (ref `metrics.md`; never raw MoM)

- `recovery_per_day = Σ success_amount / days_in_month`; `contact_rate = connected / attempts`; `ptp_kept_rate = kept / due`. Rationale: the +11% lesson.
- Dashboard shows per-day + calendar-adjusted MoM side by side. Rationale: forces honest comparison.

## 7. Incremental, late data, backfills

- Incremental: MERGE on PK scoped to `event_date`; watermark `max(event_at_ist) − 2d`. Rationale: cheap, partition-pruned.
- Late-arriving: 3-day re-state window on `recorded_at vs event_at`; restate affected `METRICS` partitions. Rationale: telephony lags.
- Backfills: idempotent full-partition overwrite (`DELETE event_date → INSERT`), never row-patch. Rationale: safe replay of dup/tz fixes.

## 8. DQ checks, monitoring, anomaly detection

- DQ per run (fail/stale on breach): dup-PK %=0, `borrower/account_id` null %=0, naive-tz %=0, orphan FK %<0.1%, lag `now − watermark` <26h. Rationale: each maps to a known synthetic mess.
- Monitoring: per-day recovery z-score (|z|>3 page); volume-drop alert (targeting/calls −20% WoW); flat-rate guard (contact/PTP ±1pp with volume spike → flag targeting-driven "growth"). Rationale: catches the next false +11%.

## 9. Key decisions

- Single warehouse over polyglot — rationale: no scale need, one thing to monitor.
- Per-day KPIs over raw monthly totals — rationale: proven by Python to kill calendar illusion.
- 3-day re-state over streaming — rationale: daily batch fits lag profile, far simpler.
