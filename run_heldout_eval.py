
import os, json, time, re, copy, statistics
from datetime import datetime
import openpyxl
import google.generativeai as genai

# ─────────────────────────────────────────────────────────────────────────────
# KONFIGURASI
# ─────────────────────────────────────────────────────────────────────────────
API_KEY = os.environ.get("GEMINI_API_KEY", "")
if not API_KEY:
    raise ValueError("Set GEMINI_API_KEY=... sebelum jalankan skrip")

REAL_DATA_FILES = [
    "test/fixtures/real_data/agenpulsa_agustus_anonim.xlsx",
    "test/fixtures/real_data/agenpulsa_september_anonim.xlsx",
    "test/fixtures/real_data/orderkuota_agustus_anonim.xlsx",
    "test/fixtures/real_data/orderkuota_september_anonim.xlsx",
]

# Header rename maps (Appendix B naskah)
HEADER_RENAME = {
    "english": {
        "ID":         "Transaction ID",
        "Produk":     "Product Category",
        "Provider":   "Operator",
        "Nominal":    "Package",
        "ID Plgn":    "Customer ID",
        "NO. HP":     "Phone Number",
        "Harga":      "Price",
        "Pembayaran": "Payment Source",
        "Tanggal":    "Transaction Time",
        "Status":     "Transaction Status",
    },
    "abbreviated": {
        "ID":         "trx_id",
        "Produk":     "kat_produk",
        "Provider":   "operator",
        "Nominal":    "ket_paket",
        "ID Plgn":    "id_pel",
        "NO. HP":     "msisdn",
        "Harga":      "hrg_jual",
        "Pembayaran": "sumber_dana",
        "Tanggal":    "waktu_trx",
        "Status":     "sts_trx",
    },
    "alt_indonesian": {
        "ID":         "No. Transaksi",
        "Produk":     "Jenis Transaksi",
        "Provider":   "Operator",
        "Nominal":    "Keterangan Paket",
        "ID Plgn":    "ID Pelanggan",
        "NO. HP":     "Nomor HP Tujuan",
        "Harga":      "Total Bayar",
        "Pembayaran": "Sumber Dana",
        "Tanggal":    "Waktu Transaksi",
        "Status":     "Status Transaksi",
    },
}

# Abbreviated dan alt_indonesian: kolom dibalik urutannya (reversed order)
REVERSED_VARIANTS = {"abbreviated", "alt_indonesian"}

# Ground truth fields yang dievaluasi (9 core fields)
TARGET_FIELDS = [
    "transactionNumber", "transactionDate", "customerPhone",
    "productType", "productName", "amount",
    "paymentStatus", "paymentMethod", "packageDescription",
]

# ─────────────────────────────────────────────────────────────────────────────
# BAGIAN 1: BUAT VARIANT FILES
# ─────────────────────────────────────────────────────────────────────────────

def make_variant_file(source_path: str, variant_name: str) -> str:
    """
    Baca xlsx asli, rename header, balik urutan kalau perlu,
    simpan ke file baru. Return path file baru.
    """
    rename_map = HEADER_RENAME[variant_name]
    wb = openpyxl.load_workbook(source_path, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    wb.close()

    if not rows:
        raise ValueError(f"File kosong: {source_path}")

    # Rename header row
    original_headers = list(rows[0])
    new_headers = tuple(rename_map.get(str(h).strip(), str(h).strip()) for h in original_headers)

    # Balik urutan kolom kalau variant ini reversed
    if variant_name in REVERSED_VARIANTS:
        col_order = list(range(len(new_headers) - 1, -1, -1))
        new_headers = tuple(new_headers[i] for i in col_order)
        data_rows = [tuple(r[i] for i in col_order) for r in rows[1:]]
    else:
        data_rows = list(rows[1:])

    # Tulis ke file baru
    base = os.path.basename(source_path).replace(".xlsx", "")
    out_dir = "test/fixtures/heldout_variants"
    os.makedirs(out_dir, exist_ok=True)
    out_path = f"{out_dir}/{base}_{variant_name}.xlsx"

    wb_new = openpyxl.Workbook()
    ws_new = wb_new.active
    ws_new.append(list(new_headers))
    for row in data_rows:
        ws_new.append(list(row))
    wb_new.save(out_path)

    print(f"  Created: {out_path}  ({len(data_rows)} data rows)")
    return out_path


# ─────────────────────────────────────────────────────────────────────────────
# BAGIAN 2: RULE-BASED MAPPER (v2) — Python re-implementation
# ─────────────────────────────────────────────────────────────────────────────

import re as _re

FIELD_PATTERNS = {
    "transactionNumber": [r"no\.?\s*trx", r"nomor\s*transaksi", r"no\.?\s*transaksi",
                          r"trx[_\-]?id", r"^id$", r"^transaction\s*id$"],
    "transactionDate":   [r"tanggal", r"\btgl\b", r"waktu", r"\bdate\b",
                          r"trx[_\-]?time", r"transaction\s*time", r"waktu_trx"],
    "customerPhone":     [r"no\.?\s*hp", r"nomor\s*tujuan", r"no\.?\s*telp",
                          r"\bphone\b", r"msisdn", r"\bhp\b", r"phone\s*number",
                          r"nomor\s*hp\s*tujuan"],
    "productType":       [r"^produk$", r"jenis\s*produk", r"kategori", r"jenis\s*layanan",
                          r"^tipe$", r"prod[_\-]?cat", r"product\s*category",
                          r"jenis\s*transaksi", r"kat_produk"],
    "productName":       [r"^provider$", r"nama\s*produk", r"^item$", r"deskripsi",
                          r"prod[_\-]?name", r"^operator$"],
    "amount":            [r"^harga$", r"^price$", r"^hrg_jual$", r"^total\s*bayar$",
                          r"nominal", r"^amount$", r"jumlah\s*bayar", r"base[_\-]?price"],
    "adminFee":          [r"biaya\s*admin", r"admin\s*fee", r"^fee$"],
    "totalAmount":       [r"total\s*bayar", r"^total$", r"grand[_\-]?total"],
    "paymentStatus":     [r"status\s*bayar", r"^status$", r"pay[_\-]?status",
                          r"transaction\s*status", r"sts_trx", r"status\s*transaksi"],
    "paymentMethod":     [r"pembayaran", r"metode\s*bayar", r"payment[_\-]?method",
                          r"^metode$", r"payment\s*source", r"sumber_dana",
                          r"sumber\s*dana"],
    "packageDescription":[r"^paket$", r"^notes$", r"^catatan$", r"^nominal$",
                          r"^package$", r"^ket_paket$", r"keterangan\s*paket"],
}

def _match_header(header: str, patterns: list) -> bool:
    h = header.strip().lower()
    for p in patterns:
        if _re.search(p, h, _re.IGNORECASE):
            return True
    return False

def _clean_numeric(val) -> str | None:
    if val is None:
        return None
    s = str(val).strip()
    # Tolak kalau ada huruf setelah strip Rp/IDR
    stripped = _re.sub(r'(?i)rp|idr', '', s).strip()
    if _re.search(r'[a-zA-Z]', stripped):
        return None
    cleaned = s.replace('Rp', '').replace('IDR', '').replace(' ', '').replace('-', '')
    cleaned = _re.sub(r'[\.,]', '', cleaned.split('.')[0] if '.' in cleaned else cleaned)
    cleaned = _re.sub(r'[^\d]', '', cleaned)
    return cleaned if cleaned else None

def _normalize_date(val) -> str | None:
    if val is None:
        return None
    s = str(val).strip().lower()
    if ':' in s:
        s = s.split(' ')[0]

    months_id = ['januari','februari','maret','april','mei','juni',
                 'juli','agustus','september','oktober','november','desember']
    for i, m in enumerate(months_id):
        if m in s:
            match = _re.search(r'(\d{1,2})\s+' + m + r'\s+(\d{4})', s)
            if match:
                return f"{match.group(2)}-{str(i+1).zfill(2)}-{match.group(1).zfill(2)}"

    # DD/MM/YYYY atau DD-MM-YYYY
    m = _re.match(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})', s)
    if m:
        y = m.group(3)
        if len(y) == 2:
            y = '20' + y
        return f"{y}-{m.group(2).zfill(2)}-{m.group(1).zfill(2)}"

    # YYYY-MM-DD
    m = _re.match(r'^(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})', s)
    if m:
        return f"{m.group(1)}-{m.group(2).zfill(2)}-{m.group(3).zfill(2)}"

    return s

def _normalize_product_type(val) -> str | None:
    if val is None:
        return None
    v = str(val).lower()
    if 'token' in v:           return 'token'
    if 'listrik' in v or 'pln' in v: return 'listrik'
    if 'pulsa' in v:           return 'pulsa'
    if any(x in v for x in ['paket','data','kuota','internet']): return 'paketData'
    if 'indihome' in v:        return 'indihome'
    if 'bpjs' in v:            return 'bpjs'
    if 'pdam' in v or 'air' in v: return 'pdam'
    return 'lainnya'

def _normalize_status(val) -> str | None:
    if val is None:
        return None
    v = str(val).lower()
    if any(x in v for x in ['belum','gagal','failed','pending','unpaid']):
        return 'belumLunas'
    if any(x in v for x in ['lunas','sukses','success','berhasil','paid','ok']):
        return 'lunas'
    return None

def _normalize_method(val) -> str | None:
    if val is None:
        return None
    v = str(val).lower()
    if 'cash' in v or 'tunai' in v: return 'cash'
    if 'transfer' in v or 'bank' in v: return 'transfer'
    if 'qris' in v or 'qr' in v: return 'qris'
    if any(x in v for x in ['wallet','ewallet','dompet','ovo','gopay','dana']): return 'eWallet'
    if 'saldo' in v: return 'eWallet'
    return 'cash'

def _normalize_phone(val) -> str | None:
    if val is None:
        return None
    digits = _re.sub(r'[^\d]', '', str(val))
    if digits.startswith('62'):
        digits = '0' + digits[2:]
    elif digits.startswith('8'):
        digits = '0' + digits
    return digits if digits else None

def rule_based_v2_map_file(xlsx_path: str) -> list[dict]:
    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    wb.close()

    if len(rows) < 2:
        return []

    headers = [str(h).strip() if h is not None else '' for h in rows[0]]
    used = set()
    col_idx = {}

    for field, patterns in FIELD_PATTERNS.items():
        for i, h in enumerate(headers):
            if i in used:
                continue
            if _match_header(h, patterns):
                col_idx[field] = i
                used.add(i)
                break

    results = []
    for row in rows[1:]:
        def get(field):
            idx = col_idx.get(field)
            if idx is None or idx >= len(row):
                return None
            v = row[idx]
            return str(v).strip() if v is not None else None

        mapped = {
            "transactionNumber":  get("transactionNumber"),
            "transactionDate":    _normalize_date(get("transactionDate")),
            "customerPhone":      _normalize_phone(get("customerPhone")),
            "productType":        _normalize_product_type(get("productType")),
            "productName":        get("productName"),
            "amount":             _clean_numeric(get("amount")),
            "paymentStatus":      _normalize_status(get("paymentStatus")),
            "paymentMethod":      _normalize_method(get("paymentMethod")),
            "packageDescription": get("packageDescription"),
        }

        # Fallback phone: cari regex di semua kolom
        if mapped["customerPhone"] is None:
            for i, cell in enumerate(row):
                if cell and _re.search(r'(?:0|\+?62)?8\d{8,11}', str(cell)):
                    mapped["customerPhone"] = _normalize_phone(str(cell))
                    break

        results.append(mapped)

    return results


# ─────────────────────────────────────────────────────────────────────────────
# BAGIAN 3: GEMINI MAPPER
# ─────────────────────────────────────────────────────────────────────────────

genai.configure(api_key=API_KEY)
gemini_model = genai.GenerativeModel(
    "gemini-3.5-flash-lite",
    generation_config=genai.types.GenerationConfig(temperature=0.0, max_output_tokens=2048)
)

gemini_stats = {"total_calls": 0, "first_pass_ok": 0, "retries": 0, "invalid": 0}

def build_gemini_prompt(headers: list) -> str:
    return f"""Saya memiliki data transaksi PPOB dengan header CSV berikut:
{', '.join(headers)}

Petakan ke field target:
transactionNumber, transactionDate, customerName, customerPhone,
productType, productName, amount, adminFee, totalAmount,
paymentStatus, paymentMethod, meterNumber, customerId,
tariff, period, tokenNumber, kwh, packageDescription

Gunakan nilai kolom (bukan hanya nama) untuk memutuskan mapping.
Jika tidak ada header yang cocok untuk suatu field, isi null.

Balas HANYA JSON tanpa penjelasan:
{{"mappings": {{"field": "nama_header_atau_null"}}}}"""

def parse_gemini_response(text: str) -> dict:
    text = _re.sub(r'```json|```', '', text).strip()
    start, end = text.find('{'), text.rfind('}') + 1
    if start < 0 or end <= start:
        raise ValueError("No JSON found")
    obj = json.loads(text[start:end])
    return obj.get("mappings", obj)

def gemini_map_file(xlsx_path: str) -> tuple[list[dict], float]:
    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    wb.close()

    if len(rows) < 2:
        return [], 0

    headers = [str(h).strip() if h is not None else '' for h in rows[0]]
    prompt = build_gemini_prompt(headers)

    gemini_stats["total_calls"] += 1
    t0 = time.perf_counter()
    resp = gemini_model.generate_content(prompt)
    elapsed = (time.perf_counter() - t0) * 1000

    try:
        mappings = parse_gemini_response(resp.text or "")
        gemini_stats["first_pass_ok"] += 1
    except Exception as e:
        gemini_stats["invalid"] += 1
        gemini_stats["retries"] += 1
        gemini_stats["total_calls"] += 1
        print(f"    ⚠ First pass invalid: {e}, retrying...")
        few_shot = prompt + """

Contoh output yang valid:
{"mappings": {"transactionNumber": "ID", "amount": "Harga", "packageDescription": "Nominal"}}

Balas HANYA JSON."""
        t1 = time.perf_counter()
        resp2 = gemini_model.generate_content(few_shot)
        elapsed += (time.perf_counter() - t1) * 1000
        mappings = parse_gemini_response(resp2.text or "")

    # Apply mappings ke setiap row
    data_rows = rows[1:]
    results = []
    for row in data_rows:
        row_dict = {headers[i]: row[i] for i in range(min(len(headers), len(row)))}

        def get_mapped(field):
            col = mappings.get(field)
            if not col or col == "null":
                return None
            v = row_dict.get(col)
            return str(v).strip() if v is not None else None

        mapped = {
            "transactionNumber":  get_mapped("transactionNumber"),
            "transactionDate":    _normalize_date(get_mapped("transactionDate")),
            "customerPhone":      _normalize_phone(get_mapped("customerPhone")),
            "productType":        _normalize_product_type(get_mapped("productType")),
            "productName":        get_mapped("productName"),
            "amount":             _clean_numeric(get_mapped("amount")),
            "paymentStatus":      _normalize_status(get_mapped("paymentStatus")),
            "paymentMethod":      _normalize_method(get_mapped("paymentMethod")),
            "packageDescription": get_mapped("packageDescription"),
        }
        results.append(mapped)

    return results, elapsed


# ─────────────────────────────────────────────────────────────────────────────
# BAGIAN 4: GROUND TRUTH LOADER
# ─────────────────────────────────────────────────────────────────────────────

def load_ground_truth(xlsx_path: str) -> list[dict]:
    """
    Ground truth diambil dari file ASLI (bukan variant),
    karena isi cell sama persis — hanya header yang berbeda.
    """
    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    wb.close()

    headers = [str(h).strip() if h is not None else '' for h in rows[0]]
    # Map original headers ke field target secara manual
    ORIGINAL_MAP = {
        "transactionNumber":  "ID",
        "transactionDate":    "Tanggal",
        "customerPhone":      "NO. HP",
        "productType":        "Produk",
        "productName":        "Provider",
        "amount":             "Harga",
        "paymentStatus":      "Status",
        "paymentMethod":      "Pembayaran",
        "packageDescription": "Nominal",
    }
    col_idx = {f: headers.index(c) for f, c in ORIGINAL_MAP.items() if c in headers}

    gt_rows = []
    for row in rows[1:]:
        def get(field):
            idx = col_idx.get(field)
            if idx is None or idx >= len(row):
                return None
            v = row[idx]
            return str(v).strip() if v is not None else None

        gt = {
            "transactionNumber":  get("transactionNumber"),
            "transactionDate":    _normalize_date(get("transactionDate")),
            "customerPhone":      _normalize_phone(get("customerPhone")),
            "productType":        _normalize_product_type(get("productType")),
            "productName":        get("productName"),
            "amount":             _clean_numeric(get("amount")),
            "paymentStatus":      _normalize_status(get("paymentStatus")),
            "paymentMethod":      _normalize_method(get("paymentMethod")),
            "packageDescription": get("packageDescription"),
        }
        gt_rows.append(gt)
    return gt_rows


# ─────────────────────────────────────────────────────────────────────────────
# BAGIAN 5: EVALUASI (micro P/R/F1 Scheme B)
# ─────────────────────────────────────────────────────────────────────────────

def evaluate(ground_truth: list[dict], predicted: list[dict], label: str) -> dict:
    tp = fp = fn = 0
    for gt, pred in zip(ground_truth, predicted):
        for field in TARGET_FIELDS:
            gt_val  = (gt.get(field)   or "").strip().lower() or None
            pred_val = (pred.get(field) or "").strip().lower() or None

            if gt_val is None and pred_val is None:
                continue  # TN
            elif gt_val is not None and pred_val is None:
                fn += 1
            elif gt_val is None and pred_val is not None:
                fp += 1
            elif gt_val == pred_val:
                tp += 1
            else:
                fp += 1
                fn += 1

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall    = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1        = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    return {
        "label":     label,
        "rows":      len(ground_truth),
        "tp": tp, "fp": fp, "fn": fn,
        "precision": round(precision, 4),
        "recall":    round(recall, 4),
        "f1":        round(f1, 4),
        "f1_pct":    f"{f1*100:.1f}%",
    }


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    timestamp = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    all_results = []

    for variant_name in ["english", "abbreviated", "alt_indonesian"]:
        print(f"\n{'='*60}")
        print(f"VARIANT: {variant_name}")
        print('='*60)

        variant_file_paths = []
        all_gt = []
        all_rb_pred = []
        gemini_preds_per_file = []
        latencies_gemini = []

        for src_path in REAL_DATA_FILES:
            if not os.path.exists(src_path):
                print(f"  ⚠ Tidak ditemukan: {src_path}, skip")
                continue

            # Buat variant file
            variant_path = make_variant_file(src_path, variant_name)
            variant_file_paths.append(variant_path)

            # Ground truth dari file asli
            gt = load_ground_truth(src_path)
            all_gt.extend(gt)

            # Rule-based v2
            t0 = time.perf_counter()
            rb_pred = rule_based_v2_map_file(variant_path)
            rb_elapsed = (time.perf_counter() - t0) * 1000
            all_rb_pred.extend(rb_pred)

            # Gemini
            print(f"  Running Gemini on {os.path.basename(variant_path)}...")
            gemini_pred, g_elapsed = gemini_map_file(variant_path)
            latencies_gemini.append(g_elapsed)
            gemini_preds_per_file.append(gemini_pred)
            time.sleep(4)  # rate limit

        all_gemini_pred = [row for preds in gemini_preds_per_file for row in preds]

        # Evaluasi
        rb_result = evaluate(all_gt, all_rb_pred,  f"RuleBased_v2_{variant_name}")
        gm_result = evaluate(all_gt, all_gemini_pred, f"Gemini_{variant_name}")

        print(f"\n  Rule-Based v2: F1={rb_result['f1_pct']}  "
              f"P={rb_result['precision']*100:.1f}%  R={rb_result['recall']*100:.1f}%")
        print(f"  Gemini:        F1={gm_result['f1_pct']}  "
              f"P={gm_result['precision']*100:.1f}%  R={gm_result['recall']*100:.1f}%")
        print(f"  Gemini avg latency: {statistics.mean(latencies_gemini):.0f} ms")

        all_results.append({
            "variant": variant_name,
            "rule_based_v2": rb_result,
            "gemini": gm_result,
            "gemini_avg_latency_ms": round(statistics.mean(latencies_gemini), 1),
        })

    # ── Ringkasan Gemini stats ──────────────────────────────────────────────
    print(f"\n{'='*60}")
    print("GEMINI RETRY STATS (held-out variants)")
    print('='*60)
    for k, v in gemini_stats.items():
        print(f"  {k}: {v}")

    # ── Simpan hasil ────────────────────────────────────────────────────────
    out = {
        "generated_at": timestamp,
        "gemini_retry_stats": gemini_stats,
        "results": all_results,
    }
    out_path = f"heldout_results_{timestamp}.json"
    with open(out_path, "w") as f:
        json.dump(out, f, indent=2, default=str)
    print(f"\nSaved: {out_path}")

    # ── Print Table 12 siap masuk naskah ───────────────────────────────────
    print(f"\n{'='*60}")
    print("TABLE 12 — Held-Out Schema Variants (F1, Scheme B)")
    print('='*60)
    print(f"{'Variant':<20} {'Rule-Based v2':>14} {'Gemini':>10}")
    print('-'*46)
    for r in all_results:
        print(f"{r['variant']:<20} {r['rule_based_v2']['f1_pct']:>14} {r['gemini']['f1_pct']:>10}")


if __name__ == "__main__":
    main()