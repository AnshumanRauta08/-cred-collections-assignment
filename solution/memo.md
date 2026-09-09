# CRED Collections — Executive Memo

**To:** CEO, CRED Collections | **From:** Collections Analytics | **Date:** 9 Sep 2026
**Re:** March “+11% MoM” — what really happened, and where to invest ₹10 Cr

## TL;DR

**March did not grow 11%. On a per-day basis, growth was +0.29% — flat.**

Raw SUCCESS rose +10.99% in March (+11.03% deduped) only because March has 31 days vs. February’s 28. April fell −4.2% per-day; July recovered +3.21% per-day. Contact (19–20%) and PTP-kept (~25%) were flat throughout.

**Recommendation if we have ₹10 Cr to invest in ONE area: #4 Better borrower targeting — BUT on corrected evidence (see §4).**
Current targeting shows **zero measured lift**: targeted 43.05% vs never-targeted 43.69% ever-paid (diff −0.64pp, p=0.35, 95% CI [−2.00pp, +0.70pp]; DPD×risk stratified MH diff −0.65pp, same CI), and priority 1–10 gives flat 7-day conversion 1.56–2.16% (χ² p=0.345). The case for #4 is therefore **“current scoring has no discrimination — rebuild + holdout”**, not “6,656 untouched = low-hanging fruit”. Incremental is **scenario-based**: empirical 0 (if holdout fails) / base 3–5% relative lift (assumption) ≈ ₹3.8–6.3 Cr/yr / upside 8–12% ≈ ₹10–15 Cr/yr only if holdout confirms. Cost **~₹1.2 Cr is a commercial assumption** (scoring build ~₹0.8 Cr + rollout ~₹0.4 Cr), not measured; 50% volume is the holdout design split, not data-derived. Downside capped at ₹1.2 Cr with kill-switch. Confidence: **high on “flat”, low on any pre-holdout lift number**.

---

## 1. What happened?

**Headline MoM is a calendar illusion — now with a formal test.**

| Metric | Feb | Mar | Change |
|---|---|---|---|
| SUCCESS (raw) | — | — | **+10.99% (+11.03% deduped)** |
| SUCCESS per-day | ₹6.076M/day (28d) | ₹6.093M/day (31d) | **+0.29%** |
| Formal test (daily means) | n=28, sd ₹0.73M | n=31, sd ₹0.84M | **Welch t=0.085, p=0.93; permutation p=0.93; bootstrap 95% CI [−6.1%, +6.8%] → not distinguishable from zero** |
| SUCCESS per-day, Apr | — | — | **−4.2%** |
| SUCCESS per-day, Jul | — | — | **+3.21%** |
| Targeting rows | 5,709 rows | 6,290 rows | **+10.2% volume** |
| Recovery / targeting-row | ₹29,802 | ₹30,033 | **+0.8% (flat)** |
| Contact rate | — | — | **19–20% flat** |
| PTP-kept rate | — | — | **~25% flat** |

We worked **+10.2% more rows** in March to earn **+0.8% more per row**. Efficiency did not improve — volume did.

**Clean (golden) numbers — what the business should report:**

- Raw SUCCESS 17,880 → **golden SUCCESS 17,534** after removing **346 duplicates (−1.94%, ~₹2.9 Cr impact)**.
- **Jan–Jul golden total: ~₹126.8 Cr.**
- **Recovery / agent-hour: ₹16,649 (76,187 hrs).**
- **Field PAID: 16.32%.**
- **6,656 accounts never targeted** (denominator gap).
- **4,128 / 4,415 OPEN PTPs past due (stale)** — follow-up is broken.

## 2. Why? (Forensics A–H, all quantified)

No single bug explains March. Seven checks rule out false causes; one explains the volume — plus a new finding that reframes the targeting case:

- **A — Duplicates:** 346 removed (−1.94%). Material (~₹2.9 Cr) but does not create the MoM spike; deduped growth is still +11.03%.
- **B — Attribution risk:** 4,297 TXN refs reused. Flagged as attribution risk, not counted as growth.
- **C — Timezone:** 3 zones normalised to IST. No MoM distortion after normalisation.
- **D — Vendor codes:** No vendor code change. Rules out definition shift.
- **E — Agent snapshots:** 1,000 agent IDs × 30 snapshots checked. No staffing-surge artefact.
- **F — Mix shift:** Fresh DPD 0–30 volume spiked **₹73.6M → ₹89.5M in March**. More easy-bucket accounts were worked — flatters raw recovery without improving rates.
- **G — Denominator:** 6,656 accounts never targeted. BUT correction: never-targeted ever-paid **43.69% vs targeted 43.05% (diff −0.64pp, z=−0.93, p=0.35; 95% CI [−2.00pp, +0.70pp]; DPD×risk MH-adjusted −0.65pp, same CI)**. Stratified gaps are inconsistent in sign (targeted wins only in 31–60 DPD and HIGH/LOW risk; NPA 90+ never-targeted wins by +8.8pp). **The untouched pool is not proven low-hanging fruit** — likely mix/selection, not opportunity. Reported rates overstate coverage, but expanding volume alone has no empirical lift.
- **H — Priority has no discrimination (NEW):** daily_targeting priority 1–10 (n≈4.4–4.6k each) → 7-day SUCCESS conversion **1.56–2.16%, no monotonic trend; χ²=10.07, p=0.345**; 30-day 6.65–7.56% also flat. Method: per-target_id any-payment-in-window (0–7d same account, golden SUCCESS). **Current scoring does not differentiate outcomes.** This is a stronger, more honest argument for rebuilding scoring than “under-resourced targeting” — and it means no in-hand basis for assuming a new score yields 8–12% lift specifically.

**Conclusion:** March = more calendar days + more rows + easier mix. Per-day (+0.29%, p=0.93), per-row (+0.8%), contact, PTP-kept, priority conversion, and targeted-vs-never lift (−0.65pp, p=0.35) are all flat / null.

## 3. Confidence? (sharply separated)

**HIGH — arithmetic, reproducible, no holdout needed:**
- Calendar math (28d vs 31d), per-day +0.29% with **p=0.93 / 95% CI [−6.1%, +6.8%]**, per-row +0.8%, flat funnel (19–20% / ~25%), golden cut (−1.94%, ₹2.9 Cr), forensics A–G counts — **high confidence**.
- **NEW nulls (also high):** targeted-vs-never diff −0.64pp, **p=0.35, CI [−2.00pp, +0.70pp]** (MH-adjusted −0.65pp, same CI); priority χ² **p=0.345**. High confidence that *current* targeting has no measured lift.

**LOW / ASSUMPTION — requires prospective holdout before quoting as fact:**
- Any *future-model* lift (3–5% base, 8–12% upside), the **₹1.2 Cr build cost** (commercial estimate: scoring ~₹0.8 Cr + rollout ~₹0.4 Cr, not measured in dataset), and the **50% volume** (holdout design split, not data-derived) — **low confidence, assumption-only**. Present these with scenario ranges, never with the same visual weight as per-day truth.

What we could not verify: field-visit causality behind the 16.32% PAID rate (no randomised field experiment in this dataset); language driver (no language column exists).

## 4. What to do? Invest the ₹10 Cr in #4 Better borrower targeting — as a capped experiment, not a proven lift

Why #4 over more agents, more dials, or more field visits: contact and PTP-kept are flat, recovery/row is flat (+0.8%), priority scoring is flat (H, p=0.345), and current targeting has **zero stratified lift (−0.65pp, p=0.35)**. The constraint is **scoring quality + PTP follow-up**, not headcount or untouched-pool size. Correction to prior draft: do NOT pitch 6,656 never-targeted as proven fruit (they already convert *higher* raw) — pitch #4 as **fixing zero-discrimination scoring**, validated only by holdout.

**Plan (cost ~₹1.2 Cr ASSUMPTION of the ₹10 Cr; return/reserve the rest):**

1. Scoring rebuild + PTP queue fix (~₹1.2 Cr **assumption**: ~₹0.8 Cr data-science/scoring + ~₹0.4 Cr rollout; flag as estimate in viva).
2. **A/B holdout — mandatory, go/no-go gate:** 50% volume (**design choice**, not data-derived) gets new scoring, 50% holdout on current logic for 8–12 weeks. Primary: per-day recovery + validated kept; falsification: placebo cutover + window sensitivity (3/7/14d).
3. Kill-switch: if lift < 3% relative at 4-week interim, stop. Loss limited to ₹1.2 Cr.

| Item | Value | Status |
|---|---|---|
| Empirical lift (current targeting, stratified) | **−0.65pp (≈ −1.5% relative), 95% CI [−2.00pp, +0.70pp], p=0.35** | **HIGH — measured, ≈ zero** |
| Priority discrimination | **Flat 1.56–2.16% (7d), p=0.345** | **HIGH — measured, no signal** |
| Scenario: pessimistic (holdout fails) | **₹0 incremental; ROI −1× (lose ₹1.2 Cr)** | Assumption-gated |
| Scenario: base (new-score 3–5% relative) | **≈ ₹3.8–6.3 Cr/yr on ₹126.8 Cr base; ROI ≈ 2–4× net; BE 3–5 mo** | **ASSUMPTION — requires holdout** |
| Scenario: upside (8–12% relative, old draft) | **≈ ₹10–15 Cr/yr; ROI 7–12×; BE 1–2 mo** | **UPSIDE ONLY — do not present as base** |
| Cost | **~₹1.2 Cr** | **ASSUMPTION, not measurement** |
| 50% volume | Holdout split | **DESIGN CHOICE** |
| Downside | **No lift → loss capped at ₹1.2 Cr** | By design |
| Confidence | **High on flat; low on any pre-holdout lift** | See §3 |

Retired: prior “₹6–9 Cr / 5–7× / 65% / ₹4–12 Cr” single-point ROI (asserted 8–12% lift) — replaced by scenario table above per review.

## 5. Financial impact

- Restate March externally/internally as **+0.29% per-day, p=0.93, 95% CI [−6.1%, +6.8%] (flat, not distinguishable from zero)**, not +11%. Golden Jan–Jul base is **₹126.8 Cr** (raw overstates by ~₹2.9 Cr from dups alone).
- New-score upside is **scenario-gated**: base 3–5% ≈ ₹3.8–6.3 Cr/yr (2–4× net on assumed ₹1.2 Cr; BE 3–5 mo) and 8–12% ≈ ₹10–15 Cr/yr (7–12×) **only if the 50/50 holdout confirms**. Pessimistic = ₹0 (lose capped ₹1.2 Cr).
- Secondary, non-ROI work (no lift claimed): clear 4,128 stale PTPs and define eligibility for the 6,656 never-targeted without assuming they convert better — success = stale < 20% and validated kept ≥ 25%, measured in holdout.

---
*Sources: golden dataset (17,534 SUCCESS, Jan–Jul ~₹126.8 Cr); forensics A–H; `golden/stratified_uplift.json` (diff −0.64pp, p=0.35, MH −0.65pp), `golden/feb_mar_test.json` (p=0.93), `golden/daily_recovery.csv`, priority 7d 1.56–2.16% (p=0.345). Cost/volume are flagged assumptions, not measurements.*
