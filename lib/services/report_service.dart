import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' as xl;

import '../helpers/download_helper.dart';

/// Report types available for generation.
enum ReportType {
  daily,
  weekly,
  monthly,
  annual,
  paymentLog,
}

/// Report data structure containing all metrics for a report period.
class ReportData {
  final DateTime startDate;
  final DateTime endDate;
  final int totalClients;
  final int activeClients;
  final int totalCollectors;
  final int activeCollectors;
  final int totalPickups;
  final int completedPickups;
  final int missedPickups;
  final double completionRate;
  final double totalRevenue;
  final int totalContracts;
  final int activeContracts;
  final int expiredContracts;
  final List<Map<String, dynamic>> recentPayments;
  final List<Map<String, dynamic>> recentPickups;
  final Map<String, int> pickupsByZone;
  final Map<String, double> revenueByMonth;

  const ReportData({
    required this.startDate,
    required this.endDate,
    required this.totalClients,
    required this.activeClients,
    required this.totalCollectors,
    required this.activeCollectors,
    required this.totalPickups,
    required this.completedPickups,
    required this.missedPickups,
    required this.completionRate,
    required this.totalRevenue,
    required this.totalContracts,
    required this.activeContracts,
    required this.expiredContracts,
    required this.recentPayments,
    required this.recentPickups,
    required this.pickupsByZone,
    required this.revenueByMonth,
  });
}

/// Generates reports from Firestore data and exports to PDF, Excel, or CSV.
class ReportService {
  ReportService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Generates report data for the given [type] and [date] range.
  Future<ReportData> generateReport({
    required ReportType type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final now = DateTime.now();
    final start = startDate ?? _getDefaultStart(type, now);
    final end = endDate ?? now;

    try {
      // Fetch all data in parallel.
      final results = await Future.wait([
        _db.collection('clients').get(),
        _db.collection('collecteurs').get(),
        _db.collection('pickups').get(),
        _db.collection('transactions').get(),
        _db.collection('contracts').get(),
      ]);

      final clientsSnap = results[0];
      final collecteursSnap = results[1];
      final pickupsSnap = results[2];
      final transactionsSnap = results[3];
      final contractsSnap = results[4];

      // Process clients.
      final totalClients = clientsSnap.docs.length;
      final activeClients = clientsSnap.docs
          .where((d) => (d.data()['status'] as String?) == 'Active')
          .length;

      // Process collectors.
      final totalCollectors = collecteursSnap.docs.length;
      final activeCollectors = collecteursSnap.docs
          .where((d) => (d.data()['status'] as String?) == 'Active')
          .length;

      // Process pickups in date range.
      final pickupsInRange = pickupsSnap.docs.where((d) {
        final date = d.data()['date'] as String? ?? '';
        return date.compareTo(start.toIso8601String().substring(0, 10)) >= 0 &&
            date.compareTo(end.toIso8601String().substring(0, 10)) <= 0;
      }).toList();

      final completedPickups = pickupsInRange
          .where((d) => (d.data()['status'] as String?) == 'completed')
          .length;
      final missedPickups = pickupsInRange
          .where((d) => (d.data()['status'] as String?) == 'missed')
          .length;
      final totalPickups = pickupsInRange.length;
      final completionRate =
          totalPickups > 0 ? (completedPickups / totalPickups * 100) : 0.0;

      // Process transactions in date range.
      final paymentsInRange = transactionsSnap.docs.where((d) {
        final ts = d.data()['createdAt'] as Timestamp?;
        if (ts == null) return false;
        final date = ts.toDate();
        return date.isAfter(start) && date.isBefore(end);
      }).toList();

      final totalRevenue = paymentsInRange.fold<double>(
        0,
        (sum, d) => sum + ((d.data()['amount'] as num?)?.toDouble() ?? 0),
      );

      // Recent payments (last 20).
      final recentPayments = paymentsInRange
          .take(20)
          .map((d) => d.data())
          .toList();

      // Recent pickups (last 20).
      final recentPickups = pickupsInRange
          .take(20)
          .map((d) => d.data())
          .toList();

      // Pickups by zone.
      final pickupsByZone = <String, int>{};
      for (final d in pickupsInRange) {
        final zone = d.data()['zone'] as String? ?? 'Unknown';
        pickupsByZone[zone] = (pickupsByZone[zone] ?? 0) + 1;
      }

      // Revenue by month.
      final revenueByMonth = <String, double>{};
      for (final d in transactionsSnap.docs) {
        final ts = d.data()['createdAt'] as Timestamp?;
        if (ts == null) continue;
        final date = ts.toDate();
        final key = DateFormat('yyyy-MM').format(date);
        revenueByMonth[key] =
            (revenueByMonth[key] ?? 0) +
                ((d.data()['amount'] as num?)?.toDouble() ?? 0);
      }

      // Process contracts.
      final totalContracts = contractsSnap.docs.length;
      final activeContracts = contractsSnap.docs
          .where((d) => (d.data()['status'] as String?) == 'Active')
          .length;
      final expiredContracts = contractsSnap.docs
          .where((d) => (d.data()['status'] as String?) == 'Expired')
          .length;

      return ReportData(
        startDate: start,
        endDate: end,
        totalClients: totalClients,
        activeClients: activeClients,
        totalCollectors: totalCollectors,
        activeCollectors: activeCollectors,
        totalPickups: totalPickups,
        completedPickups: completedPickups,
        missedPickups: missedPickups,
        completionRate: completionRate,
        totalRevenue: totalRevenue,
        totalContracts: totalContracts,
        activeContracts: activeContracts,
        expiredContracts: expiredContracts,
        recentPayments: recentPayments,
        recentPickups: recentPickups,
        pickupsByZone: pickupsByZone,
        revenueByMonth: revenueByMonth,
      );
    } catch (e) {
      debugPrint('[ReportService] Error generating report: $e');
      // Return empty report on error.
      return ReportData(
        startDate: start,
        endDate: end,
        totalClients: 0,
        activeClients: 0,
        totalCollectors: 0,
        activeCollectors: 0,
        totalPickups: 0,
        completedPickups: 0,
        missedPickups: 0,
        completionRate: 0,
        totalRevenue: 0,
        totalContracts: 0,
        activeContracts: 0,
        expiredContracts: 0,
        recentPayments: [],
        recentPickups: [],
        pickupsByZone: {},
        revenueByMonth: {},
      );
    }
  }

  /// Generates a PDF report and returns the bytes.
  Future<Uint8List> generatePdf(ReportData data, String title) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final currencyFormat = NumberFormat('#,##0');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'WastePro - $title',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Period: ${dateFormat.format(data.startDate)} to ${dateFormat.format(data.endDate)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          // KPIs
          pw.Header(text: 'Key Performance Indicators'),
          pw.SizedBox(height: 8),
          _pdfKpiRow('Total Clients', '${data.totalClients}'),
          _pdfKpiRow('Active Clients', '${data.activeClients}'),
          _pdfKpiRow('Total Collectors', '${data.totalCollectors}'),
          _pdfKpiRow('Active Collectors', '${data.activeCollectors}'),
          _pdfKpiRow('Total Pickups', '${data.totalPickups}'),
          _pdfKpiRow('Completed Pickups', '${data.completedPickups}'),
          _pdfKpiRow('Missed Pickups', '${data.missedPickups}'),
          _pdfKpiRow('Completion Rate', '${data.completionRate.toStringAsFixed(1)}%'),
          _pdfKpiRow('Total Revenue', '${currencyFormat.format(data.totalRevenue.round())} XAF'),
          _pdfKpiRow('Active Contracts', '${data.activeContracts}'),
          _pdfKpiRow('Expired Contracts', '${data.expiredContracts}'),
          pw.SizedBox(height: 20),

          // Pickups by Zone
          if (data.pickupsByZone.isNotEmpty) ...[
            pw.Header(text: 'Pickups by Zone'),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Zone', 'Pickups'],
              data: data.pickupsByZone.entries
                  .map((e) => [e.key, '${e.value}'])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
          ],

          // Revenue by Month
          if (data.revenueByMonth.isNotEmpty) ...[
            pw.Header(text: 'Revenue by Month'),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Month', 'Revenue (XAF)'],
              data: data.revenueByMonth.entries
                  .map((e) => [
                        e.key,
                        (currencyFormat.format(e.value.round())),
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfKpiRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  /// Generates an Excel report and returns the bytes.
  Uint8List generateExcel(ReportData data, String title) {
    final excel = xl.Excel.createExcel();
    final currencyFormat = NumberFormat('#,##0');

    // KPIs sheet
    final kpiSheet = excel['KPIs'];
    kpiSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        xl.TextCellValue('Metric');
    kpiSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
        xl.TextCellValue('Value');

    final kpis = [
      ('Total Clients', '${data.totalClients}'),
      ('Active Clients', '${data.activeClients}'),
      ('Total Collectors', '${data.totalCollectors}'),
      ('Active Collectors', '${data.activeCollectors}'),
      ('Total Pickups', '${data.totalPickups}'),
      ('Completed Pickups', '${data.completedPickups}'),
      ('Missed Pickups', '${data.missedPickups}'),
      ('Completion Rate', '${data.completionRate.toStringAsFixed(1)}%'),
      ('Total Revenue', '${currencyFormat.format(data.totalRevenue.round())} XAF'),
      ('Active Contracts', '${data.activeContracts}'),
      ('Expired Contracts', '${data.expiredContracts}'),
    ];

    for (var i = 0; i < kpis.length; i++) {
      kpiSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value =
          xl.TextCellValue(kpis[i].$1);
      kpiSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value =
          xl.TextCellValue(kpis[i].$2);
    }

    // Pickups by Zone sheet
    if (data.pickupsByZone.isNotEmpty) {
      final zoneSheet = excel['Pickups by Zone'];
      zoneSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
          xl.TextCellValue('Zone');
      zoneSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
          xl.TextCellValue('Pickups');

      var row = 1;
      for (final entry in data.pickupsByZone.entries) {
        zoneSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            xl.TextCellValue(entry.key);
        zoneSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
            xl.TextCellValue('${entry.value}');
        row++;
      }
    }

    // Revenue by Month sheet
    if (data.revenueByMonth.isNotEmpty) {
      final revSheet = excel['Revenue by Month'];
      revSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
          xl.TextCellValue('Month');
      revSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
          xl.TextCellValue('Revenue (XAF)');

      var row = 1;
      for (final entry in data.revenueByMonth.entries) {
        revSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            xl.TextCellValue(entry.key);
        revSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
            xl.TextCellValue(currencyFormat.format(entry.value.round()));
        row++;
      }
    }

    final fileBytes = excel.save();
    if (fileBytes == null) return Uint8List(0);
    return Uint8List.fromList(fileBytes);
  }

  /// Generates a CSV report string.
  String generateCsv(ReportData data, String title) {
    final buffer = StringBuffer();
    final currencyFormat = NumberFormat('#,##0');

    buffer.writeln('WastePro - $title');
    buffer.writeln('Period,${data.startDate.toIso8601String().substring(0, 10)} to ${data.endDate.toIso8601String().substring(0, 10)}');
    buffer.writeln();

    // KPIs
    buffer.writeln('Key Performance Indicators');
    buffer.writeln('Metric,Value');
    buffer.writeln('Total Clients,${data.totalClients}');
    buffer.writeln('Active Clients,${data.activeClients}');
    buffer.writeln('Total Collectors,${data.totalCollectors}');
    buffer.writeln('Active Collectors,${data.activeCollectors}');
    buffer.writeln('Total Pickups,${data.totalPickups}');
    buffer.writeln('Completed Pickups,${data.completedPickups}');
    buffer.writeln('Missed Pickups,${data.missedPickups}');
    buffer.writeln('Completion Rate,${data.completionRate.toStringAsFixed(1)}%');
    buffer.writeln('Total Revenue,"${currencyFormat.format(data.totalRevenue.round())} XAF"');
    buffer.writeln('Active Contracts,${data.activeContracts}');
    buffer.writeln('Expired Contracts,${data.expiredContracts}');
    buffer.writeln();

    // Pickups by Zone
    if (data.pickupsByZone.isNotEmpty) {
      buffer.writeln('Pickups by Zone');
      buffer.writeln('Zone,Pickups');
      for (final entry in data.pickupsByZone.entries) {
        buffer.writeln('${entry.key},${entry.value}');
      }
      buffer.writeln();
    }

    // Revenue by Month
    if (data.revenueByMonth.isNotEmpty) {
      buffer.writeln('Revenue by Month');
      buffer.writeln('Month,Revenue (XAF)');
      for (final entry in data.revenueByMonth.entries) {
        buffer.writeln('${entry.key},${currencyFormat.format(entry.value.round())}');
      }
    }

    return buffer.toString();
  }

  /// Exports report to a file and shares it.
  Future<void> exportAndShare({
    required ReportData data,
    required String title,
    required String format, // 'pdf', 'excel', 'csv'
  }) async {
    final dateRange = '${DateFormat('MMM d').format(data.startDate)}-${DateFormat('MMM d').format(data.endDate)}';

    late String filename;
    late List<int> bytes;
    String mimeType;

    switch (format) {
      case 'pdf':
        filename = 'WastePro $title ($dateRange).pdf';
        bytes = await generatePdf(data, title);
        mimeType = 'application/pdf';
        break;
      case 'excel':
        filename = 'WastePro $title ($dateRange).xlsx';
        bytes = generateExcel(data, title);
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        break;
      case 'csv':
        filename = 'WastePro $title ($dateRange).csv';
        bytes = generateCsv(data, title).codeUnits;
        mimeType = 'text/csv';
        break;
      default:
        return;
    }

    // On web, trigger a browser download.
    if (kIsWeb) {
      downloadFile(bytes, filename, mimeType);
      return;
    }

    // On native (mobile/desktop), use share_plus.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'WastePro Report - $title',
    );
  }

  /// Returns the default start date for a report type.
  DateTime _getDefaultStart(ReportType type, DateTime now) {
    switch (type) {
      case ReportType.daily:
        return DateTime(now.year, now.month, now.day);
      case ReportType.weekly:
        return now.subtract(const Duration(days: 7));
      case ReportType.monthly:
        return DateTime(now.year, now.month, 1);
      case ReportType.annual:
        return DateTime(now.year, 1, 1);
      case ReportType.paymentLog:
        return DateTime(now.year, now.month, 1);
    }
  }
}
