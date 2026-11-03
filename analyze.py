import glob, json, hashlib
import numpy as np, pandas as pd
rng = np.random.default_rng(42); B = 10000
import os; os.makedirs('out/tables', exist_ok=True)

df = pd.concat([pd.read_csv(f, keep_default_na=False) for f in glob.glob('out/cells_*.csv')])
df['tp'] = (df.outcome == 'tp').astype(int)
df['fp'] = df.outcome.isin(['fp', 'fpfn']).astype(int)
df['fn'] = df.outcome.isin(['fn', 'fpfn']).astype(int)

def prf(t, p, n):
    P = t / (t + p) if t + p else 0.; R = t / (t + n) if t + n else 0.
    return P, R, (2 * t / (2 * t + p + n) if 2 * t + p + n else 0.)

def agg(g):
    t, p, n = g.tp.sum(), g.fp.sum(), g.fn.sum()
    P, R, F = prf(t, p, n)
    return pd.Series(dict(TP=t, FP=p, FN=n, P=P, R=R, F1=F))

def rows_of(g):  # satu baris = unit bootstrap
    return g.groupby(['dataset', 'row'])[['tp', 'fp', 'fn']].sum().sort_index()

def f1v(s): return 2 * s[..., 0] / np.maximum(2 * s[..., 0] + s[..., 1] + s[..., 2], 1)

def ci(g):
    v = rows_of(g).values; idx = rng.integers(0, len(v), (B, len(v)))
    f = f1v(v[idx].sum(1)); return np.percentile(f, [2.5, 97.5])

def paired(a, b):  # selisih F1 gemini - rule, indeks resample sama
    ra, rb = rows_of(a), rows_of(b); k = ra.index.intersection(rb.index)
    va, vb = ra.loc[k].values, rb.loc[k].values
    idx = rng.integers(0, len(k), (B, len(k)))
    d = f1v(va[idx].sum(1)) - f1v(vb[idx].sum(1))
    pt = f1v(va.sum(0)) - f1v(vb.sum(0))
    return pt, *np.percentile(d, [2.5, 97.5])

# Table 9: per variasi GT, suite, mapper, run
t9 = []
for (gv, su, m, r), g in df.groupby(['gt_variant', 'suite', 'mapper', 'run']):
    lo, hi = ci(g); s = agg(g)
    t9.append({**s.to_dict(), 'gt_variant': gv, 'suite': su, 'mapper': m, 'run': r, 'CI_lo': lo, 'CI_hi': hi})
t9 = pd.DataFrame(t9); t9.to_csv('out/tables/table9_per_run.csv', index=False)
rng9 = t9.groupby(['gt_variant', 'suite', 'mapper']).F1.agg(['min', 'max', 'mean']).reset_index()
rng9.to_csv('out/tables/table9_range_3runs.csv', index=False)

# Table 10: per field (real) | Table 11: per skenario (edge) | Appendix C: TP/FP/FN
base = df[df.gt_variant == 'base']
t10 = base[base.suite == 'real'].groupby(['mapper', 'run', 'field']).apply(agg).reset_index()
t10.to_csv('out/tables/table10_per_field_per_run.csv', index=False)
t10.groupby(['mapper', 'field'])[['TP', 'FP', 'FN', 'P', 'R', 'F1']].mean().reset_index() \
   .to_csv('out/tables/table10_per_field_mean.csv', index=False)
t11 = base[base.suite == 'edge'].groupby(['mapper', 'run', 'category']).apply(agg).reset_index()
t11.to_csv('out/tables/table11_per_scenario.csv', index=False)
base.groupby(['suite', 'mapper', 'run', 'dataset']).apply(agg).reset_index() \
    .to_csv('out/tables/appendixC_tp_fp_fn_per_dataset.csv', index=False)
base[base.outcome.isin(['fp', 'fn', 'fpfn'])] \
    .to_csv('out/tables/appendixC_error_cells.csv', index=False)

# Selisih berpasangan gemini - rule + CI
pr = []
for (gv, su, r), g in df.groupby(['gt_variant', 'suite', 'run']):
    pt, lo, hi = paired(g[g.mapper == 'gemini'], g[g.mapper == 'ruleBased'])
    pr.append(dict(gt_variant=gv, suite=su, run=r, diff_F1=pt, CI_lo=lo, CI_hi=hi))
pd.DataFrame(pr).to_csv('out/tables/paired_diff_gemini_minus_rule.csv', index=False)

# Latensi (Table 13)
lat = pd.concat([pd.read_csv(f) for f in glob.glob('out/latency_*.csv')])
lat.groupby(['gt_variant', 'suite', 'mapper']).ms.agg(
    mean='mean', median='median', p95=lambda x: np.percentile(x, 95), n='count'
).reset_index().to_csv('out/tables/table13_latency.csv', index=False)

# Determinisme antar-run: sel yang outcome-nya beda, dan hash mapping Gemini
piv = base[base.mapper == 'gemini'].pivot_table(
    index=['suite', 'dataset', 'row', 'field'], columns='run', values='outcome', aggfunc='first')
print('sel Gemini beda antar-run:', int((piv.nunique(axis=1) > 1).sum()), 'dari', len(piv))
for f in sorted(glob.glob('out/mappings_base_*.json')):
    print(f, hashlib.md5(json.dumps(json.load(open(f)), sort_keys=True,
          default=str).encode()).hexdigest()[:8])
print(rng9.to_string())