# Data Quality Report — CRED Collections (standalone deliverable)

**Scope:** 17 raw CSVs, Jan 1 – Aug 8 2026 (Aug partial to Aug 8 — excluded from MoM).
**Method:** `python solution/build_golden.py` + `python solution/run_analysis.py` (relative paths; rerun to reproduce).
**Golden rule:** money = SUCCESS-only, `payment_id`-deduped; effort = `call_id`-deduped, IST-day; entities resolved (borrower earliest-`created_at`, agent MIN-`joined_at`).

## 1. Inventory + disposition

| Table | Rows (PK uniq) | Completeness / validity | Treatment | Impact |
|---|---|---|---|---|
| borrowers | 30,600 (11,015) | 895 null email, 614 null phone; 50.18% `updated_at` < `created_at`; same ID → different name/phone/email; 1,204 phone + 15,222 email cross-ID collisions | Keep earliest `created_at` per `borrower_id`; quarantine orphans | 30.6k → 11,015 (no 3× inflation) |
| accounts | 30,000 (30,000) | 455 null `borrower_id`; 2,458 orphan borrower_ids; DPD 0–180 (mean 56.5) | Quarantine null/orphan FK; DPD buckets 0–30/31–60/61–90/90+ | Denominator honest |
| agents | 30,000 (1,000) | ~30 snapshots/agent; 1,099 employee_codes; 10 names only | Resolve on `agent_id`, MIN(`joined_at`) = tenure; never group by name | 30k → 1,000 |
| agent_sessions | 15,000 | login→logout hrs; Jan–Jul 76,187 hrs | Denominator for ₹/agent-hour | ₹16,649/hr |
| campaigns | 120 | Same name ≠ same channel (e.g. DIGITAL_FOLLOWUP=FIELD); 4 versions | Join on `campaign_id` only | No name-based joins |
| daily_targeting | 45,000 (45,000) | 23,344 accts targeted; 6,656 never targeted | Keep never-targeted as explicit control | Selection bias visible |
| calls | 91,350 (90,000) | 1,271 full + 1,350 ID dups; 1,827 null agent; 1 row Dec-2025; 3 tz labels | Keep-first `call_id`; keep null-agent rows but exclude from agent denominators; UTC→IST day | 91,350 → 90,000 |
| call_attempts | 120,000 | 2,400 null vendor; 5 statuses ~20% each | Attempts/targeted ≈ 2.6–2.7 (stable) | No frequency shift |
| call_dispositions | 35,000 | 9 codes × 3 versions, shares flat monthly | No code-change event; map PROMISE_TO_PAY≈PTP explicitly | Rules out D |
| whatsapp_events | 60,600 (60,000) | 600 full dups; 6 types ~16–17% flat | Dedup `(message_id,event_type)` | No channel lift |
| sms_events | 45,000 | 4 types flat | As-is | No SMS lift |
| field_visits | 25,000 | 250 null `scheduled_at`; 6 outcomes; PAID 4,080/25,000 = 16.32% | Benchmark rate | ~6 visits/PAID |
| promises_to_pay | 18,000 | BROKEN 4,553 / CANCELLED 4,543 / KEPT 4,489 / OPEN 4,415; 4,128 OPEN past due (93.5% stale) | KEPT only with SUCCESS cash in [promised−1d,+7d] | Flag untrusted |
| payments | 25,500 (25,000) | 486 full + 500 ID + 4,297 TXN-reuse + 382 null refs | Drop full dups, keep-first ID, ignore TXN as key, SUCCESS-only | 17,880 → 17,534 (−1.94%, ~₹2.9Cr) |
| vendor_telephony | 15 | 5 vendors; 9 INACTIVE; answer spread 19.25–21.14% | Vendor as covariate, not driver | Max +1.9pp |
| complaints | 8,000 | 7 types flat; OPEN 2,096 backlog | AI-voice risk flag | Brand constraint |
| account_status_history | 60,000 | 30,191 `recorded_at` < `event_at` (clock skew) | Order by `event_at`; `recorded_at` only for 3-day late window | No overwrite bias |

## 2. Detection methodology (per issue)

- **Duplicates:** `duplicated()` full-row + PK + business-key (`payment_reference`, phone, email); impact = removed count × amount where money.
- **Missing:** `isna().sum()` per column; FK orphans via `~isin()` against dimension uniques.
- **Timestamps:** parse UTC; assert `updated>=created`, `recorded>=event`; lag `(recorded-event)` distribution; hour histograms by tz label vs IST-converted.
- **IDs:** `nunique()` per candidate key; per-ID variance (e.g. joined dates per `agent_id`); collision tables sorted by key.
- **Staleness:** OPEN PTPs with `promised_date < max(payment_date)`; OPEN complaints age.
- **Attribution:** TXN reuse across accounts/amounts; window-sensitivity 3/7/14/30d on contact→payment matches.

## 3. Business impact of cleaning

- Raw SUCCESS 17,880 → golden 17,534 (−346 rows, −1.94%, ~₹2.9 Cr overstatement removed).
- Mar raw +10.99% (+11.03% deduped) → per-day +0.29% (Welch p=0.93, perm p=0.93, boot CI [−6.1%,+6.8%]) — cleaning does not create the spike; calendar does.
- Borrower/agent collapse prevents 3×/30× denominator inflation in per-account/per-agent rates.
- TXN-reuse exclusion prevents last-touch over-attribution to Mar (more rows → more chance matches).

## 4. Open DQ risks (not fully fixable in-batch)

- No language column → language driver untestable (stated, not invented).
- NPA/WRITEOFF collectability differs unobservably; stratified CIs remain wide.
- Late telephony lag → 3-day re-state window in production (see architecture §7).

*Regenerate: `python solution/build_golden.py && python solution/run_analysis.py` → `solution/golden/*.json`.*
