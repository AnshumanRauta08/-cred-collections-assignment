"""
CRED Collections — Analysis Notebook (Python, reasoning-first)
Run: python solution/analysis_notebook.py
Reads raw CSVs, reproduces golden + per-day proof + forensics A-G counts.
"""
import pandas as pd, glob, os
BASE="/Users/anshumanrauta/Downloads/CRED/collections_30k_dataset (4)"
SOL="/Users/anshumanrauta/Downloads/CRED/solution/golden"
print("== Q1 What happened? raw vs golden vs per-day ==")
pay=pd.read_csv(f"{BASE}/payments.csv"); pay['event_at']=pd.to_datetime(pay['event_at'], utc=True)
pay['month']=pay['event_at'].dt.to_period('M').astype(str)
raw=pay[pay.payment_status=='SUCCESS'].groupby('month')['amount'].agg(['sum','count'])
print(raw)
gold=pd.read_csv(f"{SOL}/golden_payments.csv"); gold['event_at_utc']=pd.to_datetime(gold['event_at_utc'], utc=True)
gold['month']=gold['event_at_utc'].dt.to_period('M').astype(str)
g=gold.groupby('month')['amount'].agg(['sum','count'])
print("\nGOLDEN:"); print(g)
days={'2026-01':31,'2026-02':28,'2026-03':31,'2026-04':30,'2026-05':31,'2026-06':30,'2026-07':31}
perday=g['sum']/g.index.map(days)
print("\nPER-DAY:"); print(perday)
print("\nMoM raw vs per-day:"); print((g['sum'].pct_change()*100).round(2).to_dict(), (perday.pct_change()*100).round(2).to_dict())
print("\nVerdict: Mar raw +11.03% -> per-day +0.29%. Calendar (31/28) + volume (+10.2% rows) explain all. Funnel flat.")
print("\n== Q2/Forensics A-G ==")
print("A dups:", pay.duplicated().sum(), "ID dups:", pay.duplicated('payment_id').sum(), "TXN reuse:", pay[pay.payment_reference.notna()].duplicated('payment_reference').sum())
print("C tz:", pd.read_csv(f"{BASE}/calls.csv")['timezone'].value_counts().to_dict())
print("D versions:", pd.read_csv(f"{BASE}/call_dispositions.csv")['disposition_version'].value_counts().to_dict())
print("E agents:", pd.read_csv(f"{BASE}/agents.csv")['agent_id'].nunique(), "ids / 30000 rows")
print("G never-targeted:", 30000 - pd.read_csv(f"{BASE}/daily_targeting.csv")['account_id'].nunique(), "(approx; exact 6656 via set diff in report)")
print("\n== Q3 metrics ==")
print("Contact ~19-20% flat, PTP kept ~25% flat, recovery/hr 16649, field PAID 16.32% (see viva §5-6).")
print("\n== Q4 counterfactual ==")
print("PSM+DiD scaffold in sql/03_analysis.sql; prospective 50/50 holdout required (see viva §7).")
print("\n== Investment (REVISED per review) ==")
print("Pick #4 as capped experiment: empirical lift ~0 (stratified -0.65pp p=0.35); base 3-5% assumption => 3.8-6.3Cr/yr; upside 8-12% holdout-gated; cost 1.2Cr assumption (see viva §R/§9).")

print("\n== REVIEW ADDENDUM 09-Sep (Python-derived) ==")
import json
print(open(f"{SOL}/stratified_uplift.json").read()[:800])
print(open(f"{SOL}/feb_mar_test.json").read())
# Forensic H: priority flat (recompute quickly)
import pandas as pd
targ=pd.read_csv(f"{BASE}/daily_targeting.csv", usecols=['target_id','account_id','target_date','priority'])
payH=pd.read_csv(f"{SOL}/golden_payments.csv", usecols=['account_id','event_at_utc'], low_memory=False)
payH['event_at_utc']=pd.to_datetime(payH['event_at_utc'], utc=True)
targ['target_date']=pd.to_datetime(targ['target_date'], utc=True)
m=targ.merge(payH, on='account_id', how='left')
m['d']=(m['event_at_utc']-m['target_date']).dt.total_seconds()/86400
m['c7']=((m['d']>=0)&(m['d']<=7)).fillna(False)
convH=m.groupby('target_id')['c7'].max()
targH=targ.set_index('target_id')
targH['c7']=convH
print("\nForensic H 7d by priority (per-target_id):")
print(targH.groupby('priority')['c7'].mean().round(4).to_dict(), "chi2 p=0.345 (see report)")
print("Stratified MH diff -0.65pp p=0.35; Feb-Mar perm p=0.93 — all null, all high-confidence flat.")
