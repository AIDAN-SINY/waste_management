import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Household QR'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final code = barcode.rawValue?.trim();
            if (code == null || code.isEmpty) continue;
            _handled = true;
            Navigator.pop(context, code);
            break;
          }
        },
      ),
    );
  }
}
