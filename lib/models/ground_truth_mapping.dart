/// Ground truth definitions for CSV-to-schema mapping accuracy evaluation.
///
/// Each [GroundTruthDataset] pairs a source CSV fixture with the
/// "kunci jawaban" (expected values) for the 18-field target schema used
/// throughout the research (see `ground_truth_template.csv`):
///
///   transactionNumber, transactionDate, customerName, customerPhone,
///   productType, productName, amount, adminFee, totalAmount,
///   paymentStatus, paymentMethod, meterNumber, customerId, tariff,
///   period, tokenNumber, kwh, packageInfo
///
/// `expectedRows[i]` corresponds to the i-th data row (0-indexed, header
/// excluded) of the CSV at [csvFilePath]. A `null` value means the
/// correct/expected extraction for that field on that row is "not
/// present / not derivable" — i.e. a correct mapper should also produce
/// null there, not hallucinate a value.
///
/// These 9 datasets specifically target common real-world CSV robustness
/// problems seen in OrderKuota / AgenPulsa exports, for use in the
/// edge-case batch runner (`edge_case_batch_runner.dart`).
library ground_truth_mapping;

/// The 18 canonical target schema fields, in the reporting order used
/// throughout the evaluation pipeline.
const List<String> kTargetSchemaFields = [
  'transactionNumber',
  'transactionDate',
  'customerName',
  'customerPhone',
  'productType',
  'productName',
  'amount',
  'adminFee',
  'totalAmount',
  'paymentStatus',
  'paymentMethod',
  'meterNumber',
  'customerId',
  'tariff',
  'period',
  'tokenNumber',
  'kwh',
  'packageInfo',
];

class GroundTruthDataset {
  final String id;
  final String csvFilePath;
  final String platform;
  final String edgeCaseCategory;
  final String description;
  final List<Map<String, String?>> expectedRows;

  const GroundTruthDataset({
    required this.id,
    required this.csvFilePath,
    required this.platform,
    required this.edgeCaseCategory,
    required this.description,
    required this.expectedRows,
  });

  int get rowCount => expectedRows.length;

  /// Alias supaya konsumen (evaluator, ablation runner) tidak perlu tahu
  /// nama field internal — cukup panggil ini untuk dapat list field-map
  /// per baris, siap dibandingkan dengan hasil mapping Gemini/rule-based.
  List<Map<String, String?>> toFieldMaps() => expectedRows;
}

// ---------------------------------------------------------------------
// EC01 — Missing target columns entirely (no adminFee / paymentMethod /
// totalAmount / customerPhone columns in the source CSV at all).
// ---------------------------------------------------------------------
const GroundTruthDataset ec01MissingColumns = GroundTruthDataset(
  id: 'ec01_missing_columns',
  csvFilePath: 'test/fixtures/edge_cases/ec01_missing_columns.csv',
  platform: 'orderkuota',
  edgeCaseCategory: 'missing_columns',
  description:
      'Source CSV has no admin fee, payment method, or total-amount '
      'columns at all — a correct mapper must leave those fields null '
      'rather than guessing or hallucinating values.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-OK-1001',
      'transactionDate': '2025-01-05',
      'customerName': 'Budi Santoso',
      'customerPhone': null,
      'productType': 'pulsa',
      'productName': 'Telkomsel 25000',
      'amount': '25000',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': null,
    },
    {
      'transactionNumber': 'TRX-OK-1002',
      'transactionDate': '2025-01-05',
      'customerName': 'Siti Aminah',
      'customerPhone': null,
      'productType': 'token',
      'productName': 'Token PLN 100000',
      'amount': '100000',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': null,
    },
    {
      'transactionNumber': 'TRX-OK-1003',
      'transactionDate': '2025-01-06',
      'customerName': 'Andi Wijaya',
      'customerPhone': null,
      'productType': 'paketData',
      'productName': 'XL 10GB',
      'amount': '45000',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'belumLunas',
      'paymentMethod': null,
    },
  ],
);

// ---------------------------------------------------------------------
// EC02 — Empty/blank values scattered across otherwise-present columns.
// ---------------------------------------------------------------------
const GroundTruthDataset ec02EmptyValues = GroundTruthDataset(
  id: 'ec02_empty_values',
  csvFilePath: 'test/fixtures/edge_cases/ec02_empty_values.csv',
  platform: 'agenpulsa',
  edgeCaseCategory: 'empty_values',
  description:
      'Individual cells are blank across required fields (customer name, '
      'phone, date, amount, total, status, payment method) — tests '
      'graceful null handling per-cell rather than dropping the whole row.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-AP-2001',
      'transactionDate': '2025-02-01',
      'customerName': null,
      'customerPhone': '081234567890',
      'productType': 'pulsa',
      'productName': 'Indosat 20000',
      'amount': '20000',
      'adminFee': '1000',
      'totalAmount': '21000',
      'paymentStatus': 'lunas',
      'paymentMethod': 'cash',
    },
    {
      'transactionNumber': 'TRX-AP-2002',
      'transactionDate': '2025-02-01',
      'customerName': 'Dewi Lestari',
      'customerPhone': null,
      'productType': 'bpjs',
      'productName': 'BPJS Kesehatan',
      'amount': '150000',
      'adminFee': '2500',
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': 'transfer',
    },
    {
      'transactionNumber': 'TRX-AP-2003',
      'transactionDate': null,
      'customerName': 'Rudi Hartono',
      'customerPhone': '081298765432',
      'productType': 'pdam',
      'productName': 'PDAM Bulanan',
      'amount': null,
      'adminFee': '2500',
      'totalAmount': '102500',
      'paymentStatus': null,
      'paymentMethod': 'qris',
    },
    {
      'transactionNumber': 'TRX-AP-2004',
      'transactionDate': '2025-02-02',
      'customerName': 'Maya Putri',
      'customerPhone': '081211112222',
      'productType': 'indihome',
      'productName': 'Indihome 20Mbps',
      'amount': '300000',
      'adminFee': '2500',
      'totalAmount': '302500',
      'paymentStatus': 'belumLunas',
      'paymentMethod': null,
    },
  ],
);

// ---------------------------------------------------------------------
// EC03 — Inconsistent date formats mixed within the same file
// (DD/MM/YYYY, YYYY-MM-DD, "D Month YYYY" Indonesian, DD-MM-YYYY, YYYY/MM/DD).
// ---------------------------------------------------------------------
const GroundTruthDataset ec03InconsistentDates = GroundTruthDataset(
  id: 'ec03_inconsistent_dates',
  csvFilePath: 'test/fixtures/edge_cases/ec03_inconsistent_dates.csv',
  platform: 'orderkuota',
  edgeCaseCategory: 'inconsistent_date_formats',
  description:
      'Every row uses a different date format/locale (numeric, ISO, '
      'Indonesian month name) — all must normalize to the same ISO '
      '(YYYY-MM-DD) value.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-OK-3001',
      'transactionDate': '2025-01-05',
      'customerName': 'Fajar Nugroho',
      'productType': 'listrik',
      'productName': 'Listrik PLN R1/900VA',
      'amount': '250000',
      'adminFee': '2500',
      'totalAmount': '252500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'cash',
    },
    {
      'transactionNumber': 'TRX-OK-3002',
      'transactionDate': '2025-01-06',
      'customerName': 'Lina Marlina',
      'productType': 'token',
      'productName': 'Token PLN 50000',
      'amount': '50000',
      'adminFee': '1500',
      'totalAmount': '51500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'transfer',
    },
    {
      'transactionNumber': 'TRX-OK-3003',
      'transactionDate': '2025-01-07',
      'customerName': 'Hendra Gunawan',
      'productType': 'pulsa',
      'productName': 'Tri 15000',
      'amount': '15000',
      'adminFee': '500',
      'totalAmount': '15500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
    },
    {
      'transactionNumber': 'TRX-OK-3004',
      'transactionDate': '2025-01-08',
      'customerName': 'Putri Ayu',
      'productType': 'paketData',
      'productName': 'Smartfren 5GB',
      'amount': '35000',
      'adminFee': '1000',
      'totalAmount': '36000',
      'paymentStatus': 'belumLunas',
      'paymentMethod': 'qris',
    },
    {
      'transactionNumber': 'TRX-OK-3005',
      'transactionDate': '2025-01-09',
      'customerName': 'Bambang Sutrisno',
      'productType': 'bpjs',
      'productName': 'BPJS Kesehatan',
      'amount': '180000',
      'adminFee': '2500',
      'totalAmount': '182500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'cash',
    },
  ],
);

// ---------------------------------------------------------------------
// EC04 — Currency formatting variants: "Rp" prefix, thousand separators
// (dot), decimal comma, trailing "-", plain decimals.
// ---------------------------------------------------------------------
const GroundTruthDataset ec04CurrencyFormatting = GroundTruthDataset(
  id: 'ec04_currency_formatting',
  csvFilePath: 'test/fixtures/edge_cases/ec04_currency_formatting.csv',
  platform: 'agenpulsa',
  edgeCaseCategory: 'currency_formatting',
  description:
      'Numeric amount fields are formatted as Indonesian currency strings '
      '("Rp100.000", "150,000", "Rp 350.000,-") instead of plain numbers — '
      'all must be normalized to plain numeric values.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-AP-4001',
      'transactionDate': '2025-03-01',
      'customerName': 'Yusuf Ramadhan',
      'productType': 'token',
      'productName': 'Token PLN',
      'amount': '100000',
      'adminFee': '1500',
      'totalAmount': '101500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'cash',
    },
    {
      'transactionNumber': 'TRX-AP-4002',
      'transactionDate': '2025-03-01',
      'customerName': 'Nur Halimah',
      'productType': 'pulsa',
      'productName': 'Axis 25000',
      'amount': '25000',
      'adminFee': '1000',
      'totalAmount': '26000',
      'paymentStatus': 'lunas',
      'paymentMethod': 'transfer',
    },
    {
      'transactionNumber': 'TRX-AP-4003',
      'transactionDate': '2025-03-02',
      'customerName': 'Agus Setiawan',
      'productType': 'pdam',
      'productName': 'PDAM Bulanan',
      'amount': '150000',
      'adminFee': '2500',
      'totalAmount': '152500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'qris',
    },
    {
      'transactionNumber': 'TRX-AP-4004',
      'transactionDate': '2025-03-02',
      'customerName': 'Ratna Sari',
      'productType': 'indihome',
      'productName': 'Indihome 30Mbps',
      'amount': '350000',
      'adminFee': '2500',
      'totalAmount': '352500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
    },
  ],
);

// ---------------------------------------------------------------------
// EC05 — Non-standard / inconsistent payment status & method vocabulary
// (mixed English/Indonesian, mixed casing, synonyms).
// ---------------------------------------------------------------------
const GroundTruthDataset ec05NonStandardStatus = GroundTruthDataset(
  id: 'ec05_non_standard_status',
  csvFilePath: 'test/fixtures/edge_cases/ec05_non_standard_status.csv',
  platform: 'orderkuota',
  edgeCaseCategory: 'non_standard_status_vocabulary',
  description:
      'Payment status/method columns use inconsistent vocabulary '
      '(SUCCESS/berhasil/PENDING/FAILED/OK, tunai/dompet digital/va bank/'
      'scan qr) that must all be normalized to the canonical enum values.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-OK-5001',
      'transactionDate': '2025-04-01',
      'customerName': 'Wahyu Hidayat',
      'productType': 'pulsa',
      'productName': 'Telkomsel 50000',
      'amount': '50000',
      'adminFee': '1000',
      'totalAmount': '51000',
      'paymentStatus': 'lunas',
      'paymentMethod': 'cash',
    },
    {
      'transactionNumber': 'TRX-OK-5002',
      'transactionDate': '2025-04-01',
      'customerName': 'Indah Permata',
      'productType': 'token',
      'productName': 'Token PLN 200000',
      'amount': '200000',
      'adminFee': '2500',
      'totalAmount': '202500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
    },
    {
      'transactionNumber': 'TRX-OK-5003',
      'transactionDate': '2025-04-02',
      'customerName': 'Joko Susilo',
      'productType': 'bpjs',
      'productName': 'BPJS Ketenagakerjaan',
      'amount': '120000',
      'adminFee': '2500',
      'totalAmount': '122500',
      'paymentStatus': 'belumLunas',
      'paymentMethod': 'transfer',
    },
    {
      'transactionNumber': 'TRX-OK-5004',
      'transactionDate': '2025-04-02',
      'customerName': 'Sri Wahyuni',
      'productType': 'paketData',
      'productName': 'Indosat 12GB',
      'amount': '55000',
      'adminFee': '1000',
      'totalAmount': '56000',
      'paymentStatus': 'belumLunas',
      'paymentMethod': 'qris',
    },
    {
      'transactionNumber': 'TRX-OK-5005',
      'transactionDate': '2025-04-03',
      'customerName': 'Eko Prasetyo',
      'productType': 'pdam',
      'productName': 'PDAM Bulanan',
      'amount': '175000',
      'adminFee': '2500',
      'totalAmount': '177500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'cash',
    },
  ],
);

// ---------------------------------------------------------------------
// EC06 — Duplicate/ambiguous column header names (two "Nominal" columns
// meaning amount+adminFee, two "Keterangan" columns meaning
// productName+paymentMethod).
// ---------------------------------------------------------------------
const GroundTruthDataset ec06DuplicateHeaders = GroundTruthDataset(
  id: 'ec06_duplicate_headers',
  csvFilePath: 'test/fixtures/edge_cases/ec06_duplicate_headers.csv',
  platform: 'agenpulsa',
  edgeCaseCategory: 'duplicate_ambiguous_headers',
  description:
      'CSV header has duplicate column names ("Nominal" twice for '
      'amount/adminFee, "Keterangan" twice for productName/paymentMethod) '
      '— tests whether the mapper can disambiguate by column position/'
      'content rather than failing on the name collision.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-AP-6001',
      'transactionDate': '2025-05-01',
      'customerName': 'Anton Wijaya',
      'amount': '50000',
      'adminFee': '1500',
      'productName': 'Pulsa Telkomsel',
      'paymentMethod': 'cash',
      'paymentStatus': 'lunas',
    },
    {
      'transactionNumber': 'TRX-AP-6002',
      'transactionDate': '2025-05-01',
      'customerName': 'Melati Sari',
      'amount': '100000',
      'adminFee': '2500',
      'productName': 'Token PLN',
      'paymentMethod': 'transfer',
      'paymentStatus': 'lunas',
    },
    {
      'transactionNumber': 'TRX-AP-6003',
      'transactionDate': '2025-05-02',
      'customerName': 'Fitriani',
      'amount': '25000',
      'adminFee': '500',
      'productName': 'Paket Data XL',
      'paymentMethod': 'qris',
      'paymentStatus': 'belumLunas',
    },
  ],
);

// ---------------------------------------------------------------------
// EC07 — Extra whitespace and inconsistent casing in both headers and
// values (leading/trailing spaces, ALL CAPS, lower case).
// ---------------------------------------------------------------------
const GroundTruthDataset ec07WhitespaceCasing = GroundTruthDataset(
  id: 'ec07_whitespace_casing',
  csvFilePath: 'test/fixtures/edge_cases/ec07_whitespace_casing.csv',
  platform: 'orderkuota',
  edgeCaseCategory: 'whitespace_and_casing',
  description:
      'Headers and values contain stray leading/trailing whitespace and '
      'inconsistent casing (e.g. " Nominal ", "TOKEN LISTRIK", " sukses ") '
      '— tests trimming/normalization robustness before matching.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-OK-7001',
      'transactionDate': '2025-06-01',
      'customerName': 'Rangga Saputra',
      'productType': 'pulsa',
      'productName': 'Smartfren 20000',
      'amount': '20000',
      'adminFee': '1000',
      'totalAmount': '21000',
      'paymentStatus': 'lunas',
      'paymentMethod': 'cash',
    },
    {
      'transactionNumber': 'TRX-OK-7002',
      'transactionDate': '2025-06-01',
      'customerName': 'Yuni Astuti',
      'productType': 'token',
      'productName': 'Token PLN 75000',
      'amount': '75000',
      'adminFee': '1500',
      'totalAmount': '76500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'transfer',
    },
    {
      'transactionNumber': 'TRX-OK-7003',
      'transactionDate': '2025-06-02',
      'customerName': 'Dedi Kurniawan',
      'productType': 'bpjs',
      'productName': 'BPJS Kesehatan',
      'amount': '140000',
      'adminFee': '2500',
      'totalAmount': '142500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'qris',
    },
  ],
);

// ---------------------------------------------------------------------
// EC08 — Merged fields: a single column packs multiple pieces of
// information (name+phone, product+kWh, product+period, product+meter+period).
// ---------------------------------------------------------------------
const GroundTruthDataset ec08MergedFields = GroundTruthDataset(
  id: 'ec08_merged_fields',
  csvFilePath: 'test/fixtures/edge_cases/ec08_merged_fields.csv',
  platform: 'agenpulsa',
  edgeCaseCategory: 'merged_composite_fields',
  description:
      'Single source columns bundle multiple target fields together '
      '("Budi Santoso - 081234567890", "Token PLN 100000 / 68.5 kWh", '
      '"PDAM Bulanan - Periode 06/2025") — tests whether the mapper can '
      'split composite values into the correct separate target fields.',
  expectedRows: [
    {
      'transactionNumber': 'TRX-AP-8001',
      'transactionDate': '2025-07-01',
      'customerName': 'Budi Santoso',
      'customerPhone': '081234567890',
      'productType': 'pulsa',
      'productName': 'Telkomsel 25000',
      'amount': '25000',
      'adminFee': '1000',
      'totalAmount': '26000',
      'paymentStatus': 'lunas',
    },
    {
      'transactionNumber': 'TRX-AP-8002',
      'transactionDate': '2025-07-01',
      'customerName': 'Siti Aminah',
      'customerPhone': '08129876543',
      'productType': 'token',
      'productName': 'Token PLN 100000',
      'kwh': '68.5',
      'amount': '100000',
      'adminFee': '2500',
      'totalAmount': '102500',
      'paymentStatus': 'lunas',
    },
    {
      'transactionNumber': 'TRX-AP-8003',
      'transactionDate': '2025-07-02',
      'customerName': 'Andi Wijaya',
      'customerPhone': '081211112222',
      'productType': 'pdam',
      'productName': 'PDAM Bulanan',
      'period': '06/2025',
      'amount': '150000',
      'adminFee': '2500',
      'totalAmount': '152500',
      'paymentStatus': 'lunas',
    },
    {
      'transactionNumber': 'TRX-AP-8004',
      'transactionDate': '2025-07-02',
      'customerName': 'Rina Marlina',
      'customerPhone': '081399998888',
      'productType': 'listrik',
      'productName': 'PLN R1/900VA',
      'tariff': 'R1/900VA',
      'meterNumber': '12345678',
      'period': 'Juli 2025',
      'amount': '220000',
      'adminFee': '2500',
      'totalAmount': '222500',
      'paymentStatus': 'lunas',
    },
  ],
);

// ---------------------------------------------------------------------
// EC09 — Completely different platform schema: English/abbreviated
// column names, reordered columns, different status/method vocabulary,
// datetime with time component, and free-text notes carrying meter/
// customer-id info.
// ---------------------------------------------------------------------
const GroundTruthDataset ec09PlatformSchemaVariation = GroundTruthDataset(
  id: 'ec09_platform_schema_variation',
  csvFilePath: 'test/fixtures/edge_cases/ec09_platform_schema_variation.csv',
  platform: 'agenpulsa',
  edgeCaseCategory: 'platform_schema_variation',
  description:
      'Column names, order, and vocabulary are entirely different from '
      'the other fixtures (trx_id, prod_cat, pay_status=PAID/UNPAID, '
      'trx_time with embedded time-of-day, notes field carrying meter '
      'number / customer ID) — tests generalization beyond a single '
      'known column-naming convention.',
  expectedRows: [
    {
      'transactionNumber': 'AP-9001',
      'transactionDate': '2025-08-01',
      'customerName': 'Hasan Basri',
      'customerPhone': '081277778888',
      'productType': 'token',
      'productName': 'Token PLN 50rb',
      'amount': '50000',
      'adminFee': '1500',
      'totalAmount': '51500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'transfer',
      'meterNumber': '998877665',
    },
    {
      'transactionNumber': 'AP-9002',
      'transactionDate': '2025-08-01',
      'customerName': 'Wulan Dari',
      'customerPhone': '081266665555',
      'productType': 'pulsa',
      'productName': 'Telkomsel 10rb',
      'amount': '10000',
      'adminFee': '500',
      'totalAmount': '10500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
    },
    {
      'transactionNumber': 'AP-9003',
      'transactionDate': '2025-08-02',
      'customerName': 'Fitra Ramadhan',
      'customerPhone': '081255554444',
      'productType': 'bpjs',
      'productName': 'BPJS Kesehatan Kelas 2',
      'amount': '175000',
      'adminFee': '2500',
      'totalAmount': '177500',
      'paymentStatus': 'belumLunas',
      'paymentMethod': 'transfer',
      'customerId': '0002123456789',
    },
    {
      'transactionNumber': 'AP-9004',
      'transactionDate': '2025-08-02',
      'customerName': 'Citra Kirana',
      'customerPhone': '081244443333',
      'productType': 'indihome',
      'productName': 'Indihome 50Mbps',
      'amount': '400000',
      'adminFee': '2500',
      'totalAmount': '402500',
      'paymentStatus': 'lunas',
      'paymentMethod': 'qris',
      'packageInfo': 'Paket Internet + TV',
    },
  ],
);

/// All 9 edge-case ground truth datasets, ready to feed into
/// `edge_case_batch_runner.dart`.
const List<GroundTruthDataset> allEdgeCaseDatasets = [
  ec01MissingColumns,
  ec02EmptyValues,
  ec03InconsistentDates,
  ec04CurrencyFormatting,
  ec05NonStandardStatus,
  ec06DuplicateHeaders,
  ec07WhitespaceCasing,
  ec08MergedFields,
  ec09PlatformSchemaVariation,
];