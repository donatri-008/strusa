/// Ground truth definitions for REAL (non-synthetic) CSV export data from
/// OrderKuota and AgenPulsa, provided by UMKM 3D Store, already anonymized
/// (phone numbers are the reseller's masked test numbers, not end-customer
/// PII in production use).
///
/// Unlike `ground_truth_mapping.dart` (9 synthetic edge-case fixtures used
/// for controlled robustness stress-testing), the three datasets here are
/// unmodified real exports and therefore serve as the PRIMARY accuracy
/// evaluation data for RM2/RM3, addressing the "single provider, real data"
/// requirement.
///
/// IMPORTANT SCHEMA FINDING (documented in outline v3, confirmed here):
/// Both platforms export an IDENTICALLY NAMED header row:
///   ID, Produk, Provider, Nominal, ID Plgn, NO. HP, Harga, Pembayaran,
///   Tanggal, Status
/// but the semantics differ from what the names suggest:
///   - `Produk`   = coarse category / provider brand (NOT product name)
///   - `Provider` = the actual specific plan/product variant name
///   - `Nominal`  = free-text package description (NOT a numeric amount)
///   - `Harga`    = the actual numeric transaction amount
///   - `ID Plgn`  = always empty in both platforms' exports (unused field)
///   - `Status`   = vocabulary differs: AgenPulsa uses "SUKSES",
///                  OrderKuota uses "OK" -- both mean the same canonical
///                  state and must normalize to the same target value.
///   - `Pembayaran` is always "Saldo Akun" (reseller platform balance,
///     not a customer-facing payment channel) -- this does not map
///     cleanly onto the target schema's cash/transfer/qris/eWallet enum.
///     Ground truth here treats it as the nearest existing bucket
///     ('eWallet' = stored balance), and this mismatch itself is reported
///     as a technical constraint finding (RM5), not silently ignored.
library;

import 'ground_truth_mapping.dart' show GroundTruthDataset;

// ---------------------------------------------------------------------
// RD01 — AgenPulsa, Agustus 2026 (5 baris)
// ---------------------------------------------------------------------
const GroundTruthDataset agenpulsaAgustusAnonim = GroundTruthDataset(
  id: 'agenpulsa_agustus_anonim',
  csvFilePath: 'test/fixtures/real_data/agenpulsa_agustus_anonim.csv',
  platform: 'agenpulsa',
  edgeCaseCategory: 'real_data',
  description:
      'Data riil ekspor AgenPulsa bulan Agustus 2026 dari UMKM 3D Store '
      '(dianonimkan). Menguji kasus header identik lintas platform namun '
      'bermakna berbeda (Nominal=deskripsi teks, Harga=nilai uang riil).',
  expectedRows: [
    {
      'transactionNumber': '726571719',
      'transactionDate': '2026-08-29',
      'customerName': null,
      'customerPhone': '083137671122',
      'productType': 'paketData',
      'productName': 'Axis (Khusus Lokal Salatiga, Jatim dan Sulawesi)',
      'amount': '30648',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': '7GB Lokal / 28 Hari',
    },
    {
      'transactionNumber': '726885288',
      'transactionDate': '2026-08-29',
      'customerName': null,
      'customerPhone': '087728142112',
      'productType': 'paketData',
      'productName': 'XL (Kuota Mini)',
      'amount': '10469',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Kuota 3.6GB - 6GB, 2 Hari',
    },
    {
      'transactionNumber': '726949215',
      'transactionDate': '2026-08-30',
      'customerName': null,
      'customerPhone': '081934781100',
      'productType': 'paketData',
      'productName': 'XL (Flex Max Mini)',
      'amount': '22974',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'XL Flex Mini 10GB - 14GB + Bonus Nelpon, 7 Hari',
    },
    {
      'transactionNumber': '727299418',
      'transactionDate': '2026-08-31',
      'customerName': null,
      'customerPhone': '083185221121',
      'productType': 'paketData',
      'productName': 'Axis (Paket Harian)',
      'amount': '11349',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Paket Harian 5GB + Lokal, 3 Hari',
    },
    {
      'transactionNumber': '727447701',
      'transactionDate': '2026-08-31',
      'customerName': null,
      'customerPhone': '085784591311',
      'productType': 'paketData',
      'productName': 'Indosat (Old Freedom)',
      'amount': '32947',
      'adminFee': null,
      'totalAmount': null,
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Freedom Internet 9GB, 28 Hari',
    },
  ],
);

// ---------------------------------------------------------------------
// RD02 — AgenPulsa, September 2026 (14 baris)
// ---------------------------------------------------------------------
const GroundTruthDataset agenpulsaSeptemberAnonim = GroundTruthDataset(
  id: 'agenpulsa_september_anonim',
  csvFilePath: 'test/fixtures/real_data/agenpulsa_september_anonim.csv',
  platform: 'agenpulsa',
  edgeCaseCategory: 'real_data',
  description:
      'Data riil ekspor AgenPulsa bulan September 2026 dari UMKM 3D Store '
      '(dianonimkan). Volume lebih besar (14 baris) dengan variasi provider '
      'dan repeated-purchase pattern (mis. "Digipos Sakti" berulang).',
  expectedRows: [
    {
      'transactionNumber': '727860357',
      'transactionDate': '2026-09-01',
      'customerPhone': '082330057322',
      'productType': 'paketData',
      'productName': 'Digipos Sakti',
      'amount': '25550',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'BAYAR PAKET DIGIPOS SAKTI',
    },
    {
      'transactionNumber': '728114059',
      'transactionDate': '2026-09-02',
      'customerPhone': '089533064232',
      'productType': 'paketData',
      'productName': 'Three (Kuota Always On)',
      'amount': '28690',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Kuota 5GB AlwaysOn (AON)',
    },
    {
      'transactionNumber': '728150189',
      'transactionDate': '2026-09-02',
      'customerPhone': '085850283321',
      'productType': 'paketData',
      'productName': 'Indosat (Freedom Internet Mini)',
      'amount': '13299',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Freedom Internet 2.5GB, 5Hr',
    },
    {
      'transactionNumber': '728169893',
      'transactionDate': '2026-09-02',
      'customerPhone': '081232727761',
      'productType': 'paketData',
      'productName': 'Digipos Sakti',
      'amount': '25550',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'BAYAR PAKET DIGIPOS SAKTI',
    },
    {
      'transactionNumber': '728503576',
      'transactionDate': '2026-09-03',
      'customerPhone': '0895324131123',
      'productType': 'paketData',
      'productName': 'Three (Kuota Mini)',
      'amount': '9055',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Kuota 1.5GB, 7 Hari',
    },
    {
      'transactionNumber': '728769784',
      'transactionDate': '2026-09-03',
      'customerPhone': '085634915321',
      'productType': 'paketData',
      'productName': 'Indosat (Old Freedom)',
      'amount': '44485',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Freedom Internet 16GB, 28 Hari',
    },
    {
      'transactionNumber': '728838870',
      'transactionDate': '2026-09-04',
      'customerPhone': '085619125561',
      'productType': 'paketData',
      'productName': 'Indosat (Old Freedom)',
      'amount': '30437',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Freedom Internet 8GB, 28 Hari',
    },
    {
      'transactionNumber': '728982862',
      'transactionDate': '2026-09-04',
      'customerPhone': '081331383244',
      'productType': 'paketData',
      'productName': 'Digipos Sakti',
      'amount': '60550',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'BAYAR PAKET DIGIPOS SAKTI',
    },
    {
      'transactionNumber': '729072999',
      'transactionDate': '2026-09-04',
      'customerPhone': '087728141123',
      'productType': 'paketData',
      'productName': 'XL (Flex Max Mini)',
      'amount': '22998',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'XL Flex Mini 6GB, 14 Hari',
    },
    {
      'transactionNumber': '729110384',
      'transactionDate': '2026-09-04',
      'customerPhone': '0895324131122',
      'productType': 'paketData',
      'productName': 'Three (Kuota Mini)',
      'amount': '9055',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Kuota 1.5GB, 7 Hari',
    },
    {
      'transactionNumber': '729289750',
      'transactionDate': '2026-09-05',
      'customerPhone': '083845255511',
      'productType': 'paketData',
      'productName': 'Axis (Kuota Harian Nasional)',
      'amount': '13299',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo':
          'Kuota 4GB s/d 6GB + Bonus Lokal Jawa, Bali dan Nusra, 5 Hari',
    },
    {
      'transactionNumber': '729334170',
      'transactionDate': '2026-09-05',
      'customerPhone': '081335741123',
      'productType': 'paketData',
      'productName': 'Telkomsel (Kuota Lokal - Jawa Timur)',
      'amount': '13499',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Telkomsel Data 2.5GB, 5 Hari',
    },
    {
      'transactionNumber': '729427975',
      'transactionDate': '2026-09-05',
      'customerPhone': '085704513311',
      'productType': 'paketData',
      'productName': 'Indosat (Old Freedom)',
      'amount': '23031',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Freedom Internet 3GB, 14 Hari',
    },
    {
      'transactionNumber': '729487303',
      'transactionDate': '2026-09-05',
      'customerPhone': '083174923111',
      'productType': 'paketData',
      'productName': 'Axis (Owsem)',
      'amount': '19860',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Axis OWSEM 4GB, 28 Hari',
    },
  ],
);

// ---------------------------------------------------------------------
// RD03 — OrderKuota, September 2026 (3 baris)
// ---------------------------------------------------------------------
//
// Catatan khusus baris ke-2: kolom Produk="GIFT TELKOMSEL", Harga=0, dan
// Nominal="Cek List Paket Combo Sakti" -- pola ini bukan transaksi
// penjualan riil melainkan aksi cek/gift dengan nilai nol. Ini dicatat
// sebagai kasus ambigu untuk pembahasan kendala teknis (RM5): parser
// harus memutuskan apakah entri Harga=0 tetap dihitung sebagai transaksi
// valid atau perlu penanganan khusus (mis. dikecualikan dari rekap
// pendapatan meski tetap dicatat sebagai log aktivitas).
const GroundTruthDataset orderkuotaSeptemberAnonim = GroundTruthDataset(
  id: 'orderkuota_september_anonim',
  csvFilePath: 'test/fixtures/real_data/orderkuota_september_anonim.csv',
  platform: 'orderkuota',
  edgeCaseCategory: 'real_data',
  description:
      'Data riil ekspor OrderKuota bulan September 2026 dari UMKM 3D Store '
      '(dianonimkan). Memuat status vocabulary "OK" (berbeda dari AgenPulsa '
      '"SUKSES") dan satu baris anomali Harga=0 (transaksi cek/gift).',
  expectedRows: [
    {
      'transactionNumber': '1358252698',
      'transactionDate': '2026-09-02',
      'customerPhone': '083845256643',
      'productType': 'paketData',
      'productName': 'Mini Isi Ulang Axis 5 Hari',
      'amount': '12200',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Mini 4GB + Channel Jawa 5 Hari',
    },
    {
      'transactionNumber': '1360405559',
      'transactionDate': '2026-09-03',
      'customerPhone': '081370604637',
      'productType': 'lainnya',
      'productName': 'Data Terbaik Telkomsel',
      'amount': '0',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Cek List Paket Combo Sakti',
    },
    {
      'transactionNumber': '1362462083',
      'transactionDate': '2026-09-05',
      'customerPhone': '083149662211',
      'productType': 'paketData',
      'productName': 'Mini Isi Ulang Axis 1-3 Hari',
      'amount': '10000',
      'paymentStatus': 'lunas',
      'paymentMethod': 'eWallet',
      'packageInfo': 'Mini Axis 3GB + Bonus Aigo 3 Hari',
    },
  ],
);

/// Seluruh dataset data riil, siap dipakai oleh
/// `real_data_batch_test.dart` sebagai data uji utama RM2/RM3
/// (melengkapi dataset sintetis EC01-EC09 yang berfungsi sebagai
/// robustness/stress-test tambahan).
const List<GroundTruthDataset> allRealDataDatasets = [
  agenpulsaAgustusAnonim,
  agenpulsaSeptemberAnonim,
  orderkuotaSeptemberAnonim,
];