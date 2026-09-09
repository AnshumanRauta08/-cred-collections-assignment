# CEO Dashboard — One-Screen Spec (Collections)

**Goal:** kill the calendar illusion. Every MoM number defaults to **per-day + per-row**; raw is shown only with its distortion labelled. Decision-optimised: 6 tiles + 2 charts + 1 alert. No drill-downs on this screen.

## Layout

```
+--------+--------+--------+
| T1     | T2     | T3     |
+--------+--------+--------+
| T4     | T5     | T6     |
+-------------+------------+
| Chart 1     | Chart 2    |
+-------------+------------+
| ALERT (full width)       |
+--------------------------+
```

Refresh: daily, IST-normalised (3 zones → IST). Golden logic only (17,880 → 17,534; 346 dups excluded).

---

## 6 Tiles (exact definitions)

**T1 — Golden Recovery YTD**
- Value: **~₹126.8 Cr (Jan–Jul, golden SUCCESS 17,534)**
- Sub: Raw 17,880 − 346 dups (−1.94%, ~₹2.9 Cr)
- Decision: the only revenue number the CEO quotes. If raw ≠ golden, show “raw overstates by ₹X”.

**T2 — True Growth (per-day) [HIGH]**
- Value: **Mar +0.29% per-day** (₹6.076M/day Feb-28d, n=28, sd ₹0.73M → ₹6.093M/day Mar-31d, n=31, sd ₹0.84M)
- Formal: **Welch t=0.085, p=0.93; permutation p=0.93 (B=20k); bootstrap 95% CI [−6.1%, +6.8%] → not distinguishable from zero** (`golden/feb_mar_test.json`, `daily_recovery.csv`)
- Sub: Raw +10.99% (+11.03% deduped) labelled “calendar effect”; Apr −4.2% per-day; Jul +3.21% per-day
- Decision: green only if per-day > +2% for 2 consecutive months. Else grey “flat”.
- Target: beat +3.21% (Jul) on per-day basis.

**T3 — Efficiency per Row + per Hour**
- Value: **₹30,033 / targeting-row (Mar) vs ₹29,802 (Feb) → +0.8% flat**; **₹16,649 / agent-hour (76,187 hrs)**
- Sub: Rows 5,709 → 6,290 (+10.2% volume)
- Decision: if rows grow but ₹/row flat → flag “volume without leverage — fix targeting, not headcount”.

**T4 — Funnel Health [HIGH]**
- Value: **Contact 19–20% flat | PTP-kept ~25% flat | Priority 1–10 flat 1.56–2.16% (7d), χ² p=0.345 (Forensic H)**
- Decision: flat = no dial-pressure without scoring change. Threshold: alert if contact < 19% or PTP-kept < 22% in any week. Priority flat proves current scoring has no discrimination — rebuild, don't just expand volume.

**T5 — Field Outcome**
- Value: **Field PAID 16.32%**
- Decision: hold as benchmark for targeting experiment; do not expand field until A/B proves lift vs. tele + scoring.

**T6 — Coverage Gap ⚠ HYPOTHESIS [LOW — dashed style, lighter weight than T1 truth]**
- Value: **6,656 accounts never targeted**
- Correction (must display under value): never-targeted ever-paid **43.69% vs targeted 43.05% (diff −0.64pp, p=0.35, CI [−2.00pp,+0.70pp]; MH-adjusted −0.65pp)** — untouched ≠ proven fruit (`golden/stratified_uplift.json`)
- Sub: Fresh DPD 0–30 Mar volume ₹73.6M → ₹89.5M (mix shifted easy)
- Decision: do NOT frame as “size of prize”; frame as “requires holdout — fix zero-signal scoring (H) + stale PTPs”. Tile stays dashed until holdout confirms lift.

---

## 2 Charts

**Chart 1 — “Illusion vs. Reality” (bar + line, Feb / Mar / Apr / Jul)**
- Bars (left axis): raw SUCCESS MoM% → Mar **+10.99%**, Apr/Jul raw as computed.
- Line (right axis): per-day % → Mar **+0.29%**, Apr **−4.2%**, Jul **+3.21%**.
- Annotation on Mar bar: “31d vs 28d + easy-mix (73.6M→89.5M fresh DPD 0–30)”.
- Decision read: fund actions only on the line, never the bars.

**Chart 2 — “Golden Waterfall + Targeting Leverage” (two panels, one chart card)**
- (a) Waterfall: Raw 17,880 → −346 dups → **Golden 17,534** (−1.94%, ~₹2.9 Cr).
- (b) Paired bars Feb vs Mar: rows 5,709 → 6,290 vs. ₹/row 29,802 → 30,033.
- Decision read: if (b) rows diverge from ₹/row two months running → trigger targeting review (#4).

Data notes on card footer: TXN-reuse risk 4,297 refs excluded from lift claims; agent base 1,000 IDs × 30 snapshots; no vendor code change in period.

---

## 1 Alert (full-width, top priority)

**🔴 STALE PTP — 4,128 / 4,415 OPEN PTPs past due**
- Rule: fires when > 20% of OPEN PTPs are past due (current: **~93.5%** — critical).
- Action button: “Open PTP recovery queue” → owner: Collections Ops; SLA: clear or re-date within 7 days.
- Links to T6: prioritise stale PTPs + never-targeted high-propensity accounts in #4 rollout; success = stale share < 20% and PTP-kept holding ~25%+.

---

## What is deliberately NOT on this screen

Raw MoM as a headline, vendor-code logs, agent-level tables, timezone detail — all in appendix/forensics A–G. CEO screen answers one question: **are we recovering more per day, per row, per hour — or just working more days and rows?**
