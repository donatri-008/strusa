import os, json, time
import google.generativeai as genai
from openpyxl import load_workbook
 
API_KEY = os.environ.get("GEMINI_API_KEY", "")
if not API_KEY:
    raise ValueError("Set GEMINI_API_KEY dulu")
 
genai.configure(api_key=API_KEY)
model = genai.GenerativeModel(
    "gemini-3.5-flash-lite",
    generation_config=genai.types.GenerationConfig(temperature=0.0, max_output_tokens=2048)
)
 
# ── Log global ────────────────────────────────────────────────────────────────
total_calls   = 0
first_pass_ok = 0
retries       = 0
invalid_total = 0
latencies_ms  = []
 
def call_gemini_with_retry(prompt: str) -> dict:
    global total_calls, first_pass_ok, retries, invalid_total
 
    def parse(text):
        import re, json as _json
        text = re.sub(r"```json|```", "", text).strip()
        start, end = text.find("{"), text.rfind("}") + 1
        if start < 0 or end <= start:
            raise ValueError("No JSON object found")
        obj = _json.loads(text[start:end])
        return obj.get("mappings", obj)
 
    total_calls += 1
    t0 = time.perf_counter()
    resp = model.generate_content(prompt)
    elapsed = (time.perf_counter() - t0) * 1000
 
    try:
        mappings = parse(resp.text or "")
        first_pass_ok += 1
        latencies_ms.append(elapsed)
        return mappings
    except Exception as e:
        invalid_total += 1
        retries += 1
        total_calls += 1
        print(f"  ⚠ First pass invalid ({e}), retrying with few-shot...")
 
        few_shot = prompt + """
 
OUTPUT HARUS berupa JSON persis seperti ini:
{"mappings": {"transactionNumber": "...", "amount": "...", ...}}
Hanya JSON. Tanpa penjelasan.
"""
        t0 = time.perf_counter()
        resp2 = model.generate_content(few_shot)
        elapsed2 = (time.perf_counter() - t0) * 1000
        latencies_ms.append(elapsed + elapsed2)
        return parse(resp2.text or "")
 
 
def read_xlsx(path):
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    wb.close()
    return rows
 
 
def build_prompt(headers):
    return f"""Saya memiliki data CSV transaksi PPOB dengan header: {', '.join(str(h) for h in headers)}
 
Petakan ke field: transactionNumber, transactionDate, customerName, customerPhone,
productType, productName, amount, adminFee, totalAmount, paymentStatus, paymentMethod,
meterNumber, customerId, tariff, period, tokenNumber, kwh, packageDescription.
 
Balas HANYA JSON: {{"mappings": {{"field": "header_csv_atau_null", ...}}}}"""
 
 
FILES = [
    ("agenpulsa_agustus_anonim",   "test/fixtures/real_data/agenpulsa_agustus_anonim.xlsx"),
    ("agenpulsa_september_anonim", "test/fixtures/real_data/agenpulsa_september_anonim.xlsx"),
    ("orderkuota_agustus_anonim",  "test/fixtures/real_data/orderkuota_agustus_anonim.xlsx"),
    ("orderkuota_september_anonim","test/fixtures/real_data/orderkuota_september_anonim.xlsx"),
]
 
results = []
for dataset_id, path in FILES:
    if not os.path.exists(path):
        print(f"⚠ File tidak ditemukan: {path}")
        continue
    rows = read_xlsx(path)
    if not rows:
        continue
    headers = [str(h).strip() for h in rows[0] if h is not None]
    prompt = build_prompt(headers)
    print(f"Running {dataset_id}...")
    t_start = time.perf_counter()
    mappings = call_gemini_with_retry(prompt)
    elapsed_total = (time.perf_counter() - t_start) * 1000
    results.append({
        "datasetId": dataset_id,
        "headers": headers,
        "mappings": mappings,
        "elapsedMs": round(elapsed_total),
    })
    time.sleep(5)  # rate limit
 
# ── Ringkasan ──────────────────────────────────────────────────────────────────
import statistics
summary = {
    "total_api_calls":   total_calls,
    "first_pass_valid":  first_pass_ok,
    "first_pass_invalid": invalid_total,
    "retries":           retries,
    "avg_latency_ms":    round(statistics.mean(latencies_ms), 1) if latencies_ms else 0,
    "median_latency_ms": round(statistics.median(latencies_ms), 1) if latencies_ms else 0,
}
 
print("\n=== RETRY LOG ===")
for k, v in summary.items():
    print(f"  {k}: {v}")
 
with open("gemini_retry_log.json", "w") as f:
    json.dump({"summary": summary, "results": results}, f, indent=2)
print("\nSaved: gemini_retry_log.json")