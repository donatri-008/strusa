import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:open_settings_plus/open_settings_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/app_notification.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  String? _selectedPrinterAddress;
  String _paperSize = '58mm';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedPrinterAddress = prefs.getString('printerAddress');
      _paperSize = prefs.getString('paperSize') ?? '58mm';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Printer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current Printer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Printer Aktif',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedPrinterAddress != null
                            ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.print,
                        color: _selectedPrinterAddress != null
                            ? const Color(0xFF4CAF50)
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _selectedPrinterAddress ?? 'Tidak ada printer terhubung',
                        style: TextStyle(
                          fontWeight: _selectedPrinterAddress != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: _selectedPrinterAddress != null
                              ? Colors.black
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Paper Size
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ukuran Kertas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                RadioGroup<String>(
                  groupValue: _paperSize,
                  onChanged: (value) {
                    setState(() => _paperSize = value!);
                    _savePaperSize(value!);
                  },
                  child: const Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text('58mm'),
                          value: '58mm',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text('80mm'),
                          value: '80mm',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Scan Button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _scanDevices,
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_isScanning ? 'Mencari Printer...' : 'Cari Printer Bluetooth'),
            ),
          ),

          const SizedBox(height: 24),

          // Available Devices
          if (_devices.isNotEmpty) ...[
            const Text(
              'Printer Tersedia',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ..._devices.map((device) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedPrinterAddress == device.remoteId.toString()
                          ? const Color(0xFF2196F3)
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.print, color: Color(0xFF2196F3)),
                    title: Text(device.platformName.isNotEmpty
                        ? device.platformName
                        : 'Unknown Device'),
                    subtitle: Text(device.remoteId.toString()),
                    trailing: _selectedPrinterAddress == device.remoteId.toString()
                        ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
                        : null,
                    onTap: () => _selectPrinter(device),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _scanDevices() async {
    // Request permissions
    final bluetoothStatus = await Permission.bluetooth.request();
    final bluetoothScanStatus = await Permission.bluetoothScan.request();
    final bluetoothConnectStatus = await Permission.bluetoothConnect.request();
    final locationStatus = await Permission.location.request();

    if (!bluetoothStatus.isGranted ||
        !bluetoothScanStatus.isGranted ||
        !bluetoothConnectStatus.isGranted ||
        !locationStatus.isGranted) {
      AppNotification.permissionDenied('Bluetooth');
      return;
    }

    if (await FlutterBluePlus.isSupported == false) {
      AppNotification.warning('Tidak Didukung', 'Bluetooth tidak didukung di perangkat ini.');
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      if (!mounted) return;

      await Get.dialog(
        Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8F00), Color(0xFFFF6D00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bluetooth_disabled_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Bluetooth Mati',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF8F00).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded,
                            color: Color(0xFFFF8F00), size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Bluetooth perlu dinyalakan untuk mencetak struk via printer thermal.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF7B4F00),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Get.back(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Batal',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Get.back();
                            switch (OpenSettingsPlus.shared) {
                              case OpenSettingsPlusAndroid settings:
                                settings.bluetooth();
                              case OpenSettingsPlusIOS settings:
                                settings.bluetooth();
                              default:
                                if (Platform.isAndroid) FlutterBluePlus.turnOn();
                            }
                          },
                          icon: const Icon(Icons.bluetooth_rounded, size: 18),
                          label: const Text('Nyalakan',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8F00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                  ]),
                ),
              ],
            ),
          ),
        ),
        barrierDismissible: true,
      );
      
      return;
    }

    // Lanjut scan
    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (!_devices.any((d) => d.remoteId == result.device.remoteId)) {
            setState(() {
              _devices.add(result.device);
            });
          }
        }
      });

      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
    } catch (e) {
      AppNotification.unexpectedError('Gagal mencari printer: $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _selectPrinter(BluetoothDevice device) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printerAddress', device.remoteId.toString());
      await prefs.setString('printerName', device.platformName);

      setState(() {
        _selectedPrinterAddress = device.remoteId.toString();
      });

      AppNotification.saved('Printer berhasil dipilih.');
    } catch (e) {
      AppNotification.unexpectedError('Gagal memilih printer: $e');
    }
  }

  Future<void> _savePaperSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paperSize', size);
  }
}