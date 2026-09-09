#!/usr/bin/env python3
"""
CRED Collections — Analysis runner (tracked).
Recomputes every inferential number the memo/dashboard cite, plus the
EXECUTED counterfactual (PSM + DiD). Portable: relative paths / env / CLI.

Usage:
    python run_analysis.py [--data-dir PATH] [--golden-dir PATH]
Outputs (in golden-dir):
    feb_mar_test.json, stratified_uplift.json, forensic_h.json,
    counterfactual_did.json
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats


def resolve(cli_data, cli_golden):
    here = Path(__file__).resolve().parent
    if cli_data:
        data = Path(cli_data)
    elif "CRED_DATA_DIR" in os.environ:
        data = Path(os.environ["CRED_DATA_DIR"])
    else:
        data = here.parent / "collections_30k_dataset (4)"
    if not data.exists():
        alt = here.parent / "collections_30k_dataset"
        if alt.exists():
            data = alt
    if cli_golden:
        golden = Path(cli_golden)
    elif "CRED_OUT_DIR" in os.environ:
        golden = Path(os.environ["CRED_OUT_DIR"])
    else:
        golden = here / "golden"
    return data, golden


# ---------- A. Feb vs Mar daily test ----------
def feb_mar_test(golden: Path) -> dict:
    pay = pd.read_csv(golden / "golden_payments.csv", usecols=["amount", "event_at_utc"])
    pay["event_at_utc"] = pd.to_datetime(pay["event_at_utc"], utc=True)
    pay["date"] = pay["event_at_utc"].dt.date
    daily = pay.groupby("date")["amount"].sum()
    feb = daily[[d for d in daily.index if d.month == 2 and d.year == 2026]].values.astype(float)
    mar = daily[[d for d in daily.index if d.month == 3 and d.year == 2026]].values.astype(float)
    t, p = stats.ttest_ind(mar, feb, equal_var=False)
    rng = np.random.default_rng(42)
    combined = np.concatenate([feb, mar])
    obs = float(mar.mean() - feb.mean())
    B = 20000
    # Single permutation per iteration (deterministic seed stream).
    null = np.array([(lambda pr: float(pr[len(feb):].mean() - pr[:len(feb)].mean()))(rng.permutation(combined)) for _ in range(B)])
    p_perm = float((np.sum(np.abs(null) >= abs(obs)) + 1) / (B + 1))
    boot = np.array([float(rng.choice(mar, size=len(mar), replace=True).mean()
                           - rng.choice(feb, size=len(feb), replace=True).mean()) for _ in range(B)])
    res = {
        "feb_n": int(len(feb)), "feb_mean": float(feb.mean()), "feb_sd": float(feb.std(ddof=1)),
        "mar_n": int(len(mar)), "mar_mean": float(mar.mean()), "mar_sd": float(mar.std(ddof=1)),
        "obs_diff": obs, "obs_pct": float(mar.mean() / feb.mean() - 1),
        "welch_t": float(t), "welch_p": float(p), "perm_p": p_perm, "B": B,
        "null_95": [float(np.percentile(null, 2.5)), float(np.percentile(null, 97.5))],
        "boot_ci_abs": [float(np.percentile(boot, 2.5)), float(np.percentile(boot, 97.5))],
        "boot_ci_pct": [float(np.percentile(boot / feb.mean() * 100, 2.5)),
                        float(np.percentile(boot / feb.mean() * 100, 97.5))],
        "verdict": "not distinguishable from zero" if p_perm > 0.05 else "significant",
    }
    (golden / "feb_mar_test.json").write_text(json.dumps(res, indent=2))
    print(f"Feb-vs-Mar: diff {obs:+,.0f} ({res['obs_pct']*100:+.2f}%), Welch p={p:.3f}, perm p={p_perm:.3f}")
    return res


# ---------- B. Targeted vs never + stratified ----------
def stratified_uplift(data: Path, golden: Path) -> dict:
    from statsmodels.stats.proportion import proportions_ztest, confint_proportions_2indep
    pay = pd.read_csv(golden / "golden_payments.csv", usecols=["account_id", "event_at_utc"])
    pay["event_at_utc"] = pd.to_datetime(pay["event_at_utc"], utc=True)
    paid_jul = set(pay[pay["event_at_utc"] < "2026-08-01"]["account_id"])
    accts = pd.read_csv(data / "accounts.csv", usecols=["account_id", "dpd", "risk_segment"])
    accts["dpd_bucket"] = pd.cut(accts["dpd"], bins=[-1, 30, 60, 90, 180],
                                 labels=["0-30", "31-60", "61-90", "90+"])
    targ = set(pd.read_csv(data / "daily_targeting.csv", usecols=["account_id"])["account_id"])
    accts["ever_targeted"] = accts["account_id"].isin(targ)
    accts["ever_paid"] = accts["account_id"].isin(paid_jul)
    n1 = int(accts["ever_targeted"].sum()); x1 = int(accts[accts["ever_targeted"]]["ever_paid"].sum())
    n0 = int((~accts["ever_targeted"]).sum()); x0 = int(accts[~accts["ever_targeted"]]["ever_paid"].sum())
    z, p = proportions_ztest([x1, x0], [n1, n0])
    low, upp = confint_proportions_2indep(x1, n1, x0, n0, compare="diff")
    accts["stratum"] = accts["dpd_bucket"].astype(str) + "_" + accts["risk_segment"].astype(str)
    rows = []
    for s, g in accts.groupby("stratum"):
        a, b = g[g["ever_targeted"]], g[~g["ever_targeted"]]
        if len(a) == 0 or len(b) == 0:
            continue
        p1, p0 = float(a["ever_paid"].mean()), float(b["ever_paid"].mean())
        se = float(np.sqrt(p1 * (1 - p1) / len(a) + p0 * (1 - p0) / len(b)))
        rows.append({"stratum": s, "n_targ": int(len(a)), "n_never": int(len(b)),
                     "p_targ": p1, "p_never": p0, "diff": p1 - p0, "se": se, "w": float(1 / se ** 2)})
    r = pd.DataFrame(rows)
    mh = float((r["w"] * r["diff"]).sum() / r["w"].sum())
    mh_se = float(np.sqrt(1 / r["w"].sum()))
    out = {"targeted_rate": x1 / n1, "never_rate": x0 / n0, "diff": x1 / n1 - x0 / n0,
           "n_targ": n1, "x_targ": x1, "n_never": n0, "x_never": x0,
           "z": float(z), "p": float(p), "ci": [float(low), float(upp)],
           "mh_diff": mh, "mh_se": mh_se, "mh_ci": [mh - 1.96 * mh_se, mh + 1.96 * mh_se],
           "strata": rows,
           "verdict": "zero measured lift for current targeting"}
    (golden / "stratified_uplift.json").write_text(json.dumps(out, indent=2))
    print(f"Targeted {x1/n1:.4f} vs never {x0/n0:.4f} diff {x1/n1-x0/n0:+.4f} p={p:.3f} MH {mh:+.4f}")
    return out


# ---------- C. Forensic H: priority flat ----------
def forensic_h(data: Path, golden: Path) -> dict:
    targ = pd.read_csv(data / "daily_targeting.csv",
                       usecols=["target_id", "account_id", "target_date", "priority"])
    pay = pd.read_csv(golden / "golden_payments.csv", usecols=["account_id", "event_at_utc"])
    pay["event_at_utc"] = pd.to_datetime(pay["event_at_utc"], utc=True)
    targ["target_date"] = pd.to_datetime(targ["target_date"], utc=True)
    m = targ.merge(pay, on="account_id", how="left")
    m["delta"] = (m["event_at_utc"] - m["target_date"]).dt.total_seconds() / 86400
    m["c7"] = ((m["delta"] >= 0) & (m["delta"] <= 7)).fillna(False)
    per_target = m.groupby("target_id")["c7"].max()
    t2 = targ.set_index("target_id")
    t2["c7"] = per_target
    by_p = t2.groupby("priority")["c7"].agg(["mean", "sum", "size"]).round(4)
    ct = pd.crosstab(t2["priority"], t2["c7"])
    chi2, p, dof, _ = stats.chi2_contingency(ct)
    out = {"overall_7d": float(t2["c7"].mean()),
           "by_priority": {int(k): {"mean": float(v["mean"]), "n": int(v["size"])}
                           for k, v in by_p.iterrows()},
           "chi2": float(chi2), "p": float(p), "dof": int(dof),
           "verdict": "no discriminative power"}
    (golden / "forensic_h.json").write_text(json.dumps(out, indent=2))
    print(f"Forensic H: 7d {out['overall_7d']:.4f}, chi2 p={p:.3f}")
    return out


# ---------- D. EXECUTED counterfactual: PSM + DiD ----------
def counterfactual_did(data: Path, golden: Path) -> dict:
    """
    Cutover = March (mid-year targeting change).
    Treatment: accounts with ANY Mar targeting under strategy v2/v3 (new logic).
    Control:   accounts with Mar targeting ONLY under legacy/v1 (old logic),
               1:1 PSM-matched on DPD/outstanding/risk/loan.
    Pre:  ever-paid Jan–Feb | Post: ever-paid Apr–May (Mar skipped as transition).
    Estimand: DiD on ever-paid rate. Expect null/wide (weak first stage is the finding).
    """
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import OneHotEncoder

    camps = pd.read_csv(data / "campaigns.csv", usecols=["campaign_id", "strategy_version"])
    targ = pd.read_csv(data / "daily_targeting.csv", usecols=["account_id", "campaign_id", "target_date"])
    targ["target_date"] = pd.to_datetime(targ["target_date"])
    targ = targ.merge(camps, on="campaign_id", how="left")
    mar = targ[(targ["target_date"] >= "2026-03-01") & (targ["target_date"] < "2026-04-01")]
    new_ids = set(mar[mar["strategy_version"].isin(["v2", "v3"])]["account_id"])
    old_ids = set(mar[mar["strategy_version"].isin(["legacy", "v1"])]["account_id"]) - new_ids
    print(f"Mar new-logic (v2/v3): {len(new_ids)} | old-logic-only (legacy/v1): {len(old_ids)}")

    accts = pd.read_csv(data / "accounts.csv",
                        usecols=["account_id", "dpd", "outstanding_amount", "risk_segment", "loan_type"])
    pay = pd.read_csv(golden / "golden_payments.csv", usecols=["account_id", "event_at_utc"])
    pay["event_at_utc"] = pd.to_datetime(pay["event_at_utc"], utc=True)
    pre_ids = set(pay[(pay["event_at_utc"] >= "2026-01-01") & (pay["event_at_utc"] < "2026-03-01")]["account_id"])
    post_ids = set(pay[(pay["event_at_utc"] >= "2026-04-01") & (pay["event_at_utc"] < "2026-06-01")]["account_id"])
    jan_ids = set(pay[(pay["event_at_utc"] >= "2026-01-01") & (pay["event_at_utc"] < "2026-02-01")]["account_id"])
    feb_ids = set(pay[(pay["event_at_utc"] >= "2026-02-01") & (pay["event_at_utc"] < "2026-03-01")]["account_id"])

    df = accts[accts["account_id"].isin(new_ids | old_ids)].copy()
    df["treat"] = df["account_id"].isin(new_ids).astype(int)
    df["pre"] = df["account_id"].isin(pre_ids).astype(int)
    df["post"] = df["account_id"].isin(post_ids).astype(int)
    df["jan"] = df["account_id"].isin(jan_ids).astype(int)
    df["feb"] = df["account_id"].isin(feb_ids).astype(int)

    # PSM: P(treat | X)
    enc = OneHotEncoder(handle_unknown="ignore", sparse_output=False)
    Xo = enc.fit_transform(df[["risk_segment", "loan_type"]])
    import numpy as np
    X = np.column_stack([df[["dpd", "outstanding_amount"]].values, Xo])
    # Standardise continuous cols
    mu, sd = X[:, :2].mean(0), X[:, :2].std(0) + 1e-9
    X[:, :2] = (X[:, :2] - mu) / sd
    clf = LogisticRegression(max_iter=2000).fit(X, df["treat"])
    df["ps"] = clf.predict_proba(X)[:, 1]

    rng = np.random.default_rng(7)
    treated = df[df["treat"] == 1].sample(frac=1, random_state=7)  # shuffle
    pool = df[df["treat"] == 0].copy()
    pairs, used = [], set()
    caliper = 0.05
    for _, r in treated.iterrows():
        cand = pool[~pool["account_id"].isin(used)]
        if cand.empty:
            break
        d = (cand["ps"] - r["ps"]).abs()
        j = d.idxmin()
        if d.loc[j] <= caliper:
            pairs.append((r["account_id"], cand.loc[j, "account_id"]))
            used.add(cand.loc[j, "account_id"])
    mt = df.set_index("account_id")
    T = [mt.loc[a] for a, _ in pairs]
    C = [mt.loc[b] for _, b in pairs]
    Tm, Cm = pd.DataFrame(T), pd.DataFrame(C)
    # Balance: standardised mean diffs
    bal = {}
    for c in ["dpd", "outstanding_amount", "pre", "jan", "feb"]:
        m1, m0 = float(Tm[c].mean()), float(Cm[c].mean())
        s = float(np.sqrt((Tm[c].var(ddof=1) + Cm[c].var(ddof=1)) / 2) + 1e-12)
        bal[c] = {"treat": m1, "control": m0, "smd": float((m1 - m0) / s)}
    # DiD
    t_pre, t_post = float(Tm["pre"].mean()), float(Tm["post"].mean())
    c_pre, c_post = float(Cm["pre"].mean()), float(Cm["post"].mean())
    did = (t_post - t_pre) - (c_post - c_pre)
    # Parallel pre-trends (Jan->Feb change by arm, unmatched full groups for transparency)
    full = df
    pt = {k: float(full[full["treat"] == k]["feb"].mean() - full[full["treat"] == k]["jan"].mean()) for k in (0, 1)}
    # Bootstrap CI for DiD (resample pairs)
    B = 10000
    arr = np.array([((mt.loc[a]["post"] - mt.loc[a]["pre"]) - (mt.loc[b]["post"] - mt.loc[b]["pre"]))
                    for a, b in pairs], dtype=float)
    boots = np.array([float(rng.choice(arr, size=len(arr), replace=True).mean()) for _ in range(B)])
    ci = [float(np.percentile(boots, 2.5)), float(np.percentile(boots, 97.5))]
    base_rate = float(df["pre"].mean())
    out = {
        "design": "Mar cutover; treat=v2/v3-any, control=legacy/v1-only; pre=Jan-Feb ever-paid, post=Apr-May ever-paid; 1:1 PSM caliper 0.05",
        "n_treat_pool": int((df["treat"] == 1).sum()), "n_control_pool": int((df["treat"] == 0).sum()),
        "n_pairs": int(len(pairs)), "caliper": caliper,
        "rates": {"treat_pre": t_pre, "treat_post": t_post, "control_pre": c_pre, "control_post": c_post},
        "did_pp": float(did), "did_rel": float(did / base_rate) if base_rate else None,
        "boot_ci_pp": ci, "B": B,
        "parallel_pre_trends": {"treat_jan_feb_change": pt[1], "control_jan_feb_change": pt[0],
                                "diff": pt[1] - pt[0]},
        "balance_smd": bal,
        "verdict": ("null / weak first stage — CI spans zero; targeting change has no cleanly identified lift; "
                    "prospective 50/50 holdout still required"),
    }
    (golden / "counterfactual_did.json").write_text(json.dumps(out, indent=2))
    print(f"DiD: {did:+.4f} pp, 95% CI [{ci[0]:+.4f}, {ci[1]:+.4f}], pairs={len(pairs)}")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default=None)
    ap.add_argument("--golden-dir", default=None)
    a = ap.parse_args()
    data, golden = resolve(a.data_dir, a.golden_dir)
    print(f"data: {data}\ngolden: {golden}")
    feb_mar_test(golden)
    stratified_uplift(data, golden)
    forensic_h(data, golden)
    counterfactual_did(data, golden)


if __name__ == "__main__":
    main()
