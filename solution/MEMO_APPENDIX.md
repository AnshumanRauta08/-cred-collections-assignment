# Memo Appendix — Statistical Detail (for audit, not the CEO read)

## A. Feb vs Mar per-day (`golden/feb_mar_test.json`, `daily_recovery.csv`)

- Feb: n=28 days, mean ₹6,076,516/d, sd ₹734,383. Mar: n=31, mean ₹6,093,948/d, sd ₹835,937.
- Observed diff +₹17,431 (+0.29%). Welch t=0.085, **p=0.932**; permutation (B=20,000) **p=0.931**; bootstrap 95% CI [−₹370k, +₹411k] = **[−6.09%, +6.77%]**; null 95% interval [−₹393k, +₹401k] contains observed.
- Reading: not distinguishable from zero. 31/28−1 alone predicts +10.7% raw.

## B. Targeted vs never-targeted (`golden/stratified_uplift.json`)

- Golden Jan–Jul ever-paid: targeted 10,049/23,344 = 43.05%; never 2,908/6,656 = 43.69%; diff −0.64pp; z=−0.93, **p=0.351**; Newcombe 95% CI [−2.00pp, +0.70pp].
- DPD×risk inverse-variance (MH-style, 16 strata): −0.65pp, SE 0.69pp, CI [−2.00pp, +0.70pp]. Targeted wins only in 31–60 DPD / HIGH / LOW; never wins elsewhere (NPA 90+: +8.8pp never).
- Reading: zero measured lift for current targeting; mix does not rescue the story.

## C. Priority discrimination / Forensic H (`golden/forensic_h.json`)

- Per-target 7-day SUCCESS conversion by priority 1–10: 1.56–2.16% (overall 1.83%), no monotonic trend; χ²=10.07, **p=0.345**; 30-day 6.65–7.56% also flat.
- Reading: current scoring has no discriminative power.

## D. Executed counterfactual PSM+DiD (`golden/counterfactual_did.json`)

- Design: Mar cutover; treat = Mar targeting under v2/v3 (n=2,949), control = Mar legacy/v1-only (n=2,717); 1:1 PSM caliper 0.05 on DPD/outstanding/risk/loan → **2,717 pairs**; pre = Jan–Feb ever-paid, post = Apr–May ever-paid.
- Rates: treat 14.39%→14.06% (−0.33pp); control 14.76%→15.72% (+0.96pp). **DiD −1.29pp, bootstrap 95% CI [−4.01pp, +1.40pp]** (B=10k), relative −8.8%.
- Parallel pre-trends Jan→Feb: treat −1.22pp vs control −0.52pp (diff −0.71pp — reasonably parallel, both declining).
- Balance SMDs: dpd 0.011, outstanding 0.036, pre −0.010, jan 0.000, feb −0.021 (all |SMD|<0.05 — well matched).
- Reading: null / weak first stage — CI spans zero with negative point. No cleanly identified lift; prospective 50/50 holdout still required. An executed-but-weak estimate, not a template.

## E. Cost/volume flags

- ₹1.2 Cr ≈ ₹0.8Cr scoring + ₹0.4Cr rollout — commercial estimate, not measured.
- 50% volume = holdout design split (8–12 wks, kill-switch <3% at 4 wks), not data-derived.

*Reproduce: `python solution/run_analysis.py` (seeds 42/7; sklearn LogisticRegression max_iter=2000).*
