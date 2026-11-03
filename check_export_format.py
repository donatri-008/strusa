import glob, re, collections
import pandas as pd
from openpyxl import load_workbook

for f in sorted(glob.glob('test/fixtures/real_data/*.xlsx')):
    print(f'\n## {f}')
    wb = load_workbook(f, read_only=True)
    print('sheet:', wb.sheetnames)
    xl = pd.ExcelFile(f)
    df = xl.parse(xl.sheet_names[0], dtype=str, keep_default_na=False)
    hdr = list(df.columns)
    print('header:', hdr)
    print('header spasi di tepi:', [h for h in hdr if h != h.strip()])
    print('header duplikat:', [h for h, c in collections.Counter(hdr).items() if c > 1])
    print('baris:', len(df), '| ID unik:', df['ID'].nunique() if 'ID' in df else 'n/a')
    for c in hdr:
        e = (df[c].str.strip() == '').mean()
        if e > 0: print(f'kolom kosong {c}: {e:.0%}')
    for c in ['Status', 'Pembayaran', 'Produk']:
        if c in df: print(c, dict(df[c].value_counts().head(8)))
    if 'Harga' in df:
        num = pd.to_numeric(df['Harga'], errors='coerce')
        print('Harga non-numerik:', int(num.isna().sum()), '| Harga=0:', int((num == 0).sum()))
    if 'Nominal' in df:
        print('Nominal berisi huruf:', int(df['Nominal'].str.contains(r'[A-Za-z]').sum()), 'dari', len(df))
    if 'NO. HP' in df:
        print('HP bukan awalan 0:', int((~df['NO. HP'].str.startswith('0')).sum()))
    ws = wb[wb.sheetnames[0]]
    r = next(ws.iter_rows(min_row=2, max_row=2))
    for i, c in enumerate(hdr):
        if c == 'Tanggal': print('tipe sel Tanggal:', r[i].data_type, '| contoh:', r[i].value)
    if 'Tanggal' in df:
        print('pola tanggal:', dict(df['Tanggal'].str.replace(r'\d', '9', regex=True).value_counts()))