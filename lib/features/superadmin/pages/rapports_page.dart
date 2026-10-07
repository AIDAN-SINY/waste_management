import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/report_service.dart';
import '../theme.dart';

class RapportsPage extends StatefulWidget {
  const RapportsPage({super.key, this.db});

  /// Optional Firestore instance for dependency injection in tests.
  final FirebaseFirestore? db;

  @override
  State<RapportsPage> createState() => _RapportsPageState();
}

class _RapportsPageState extends State<RapportsPage> {
  late final ReportService _reportService;

  ReportType _selectedType = ReportType.monthly;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  ReportData? _reportData;
  bool _loading = false;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reportService = ReportService(db: widget.db);
  }

  Future<void> _generateReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _reportService.generateReport(
        type: _selectedType,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (mounted) {
        setState(() {
          _reportData = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to generate report: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportReport(String format) async {
    if (_reportData == null) return;

    setState(() => _generating = true);

    try {
      final title = _getReportTitle();
      final formatLabel = format.toUpperCase();
      await _reportService.exportAndShare(
        data: _reportData!,
        title: title,
        format: format,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$formatLabel report downloaded successfully'),
            backgroundColor: SuperAdminTheme.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: SuperAdminTheme.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _getReportTitle() {
    switch (_selectedType) {
      case ReportType.daily:
        return 'Daily Report';
      case ReportType.weekly:
        return 'Weekly Report';
      case ReportType.monthly:
        return 'Monthly Report';
      case ReportType.annual:
        return 'Annual Report';
      case ReportType.paymentLog:
        return 'Payment Log';
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
      _generateReport();
    }
  }

  DateTime _getDefaultStart(ReportType type) {
    final now = DateTime.now();
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // Report Type Selector
        Container(
          padding: const EdgeInsets.all(20),
          decoration: SuperAdminTheme.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Type',
                style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReportType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedType = type;
                        _startDate = _getDefaultStart(type);
                        _endDate = DateTime.now();
                      });
                      _generateReport();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SuperAdminTheme.green
                            : SuperAdminTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? SuperAdminTheme.green
                              : SuperAdminTheme.border,
                        ),
                      ),
                      child: Text(
                        _typeName(type),
                        style: SuperAdminTheme.inter(
                          12.5,
                          weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? Colors.white : SuperAdminTheme.text,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Date Range
        Container(
          padding: const EdgeInsets.all(20),
          decoration: SuperAdminTheme.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Date Range',
                style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _dateButton(
                      'Start',
                      DateFormat('yyyy-MM-dd').format(_startDate),
                      () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dateButton(
                      'End',
                      DateFormat('yyyy-MM-dd').format(_endDate),
                      () => _pickDate(false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Export Buttons
        Container(
          padding: const EdgeInsets.all(20),
          decoration: SuperAdminTheme.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export Report',
                style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _generating
                    ? 'Generating...'
                    : 'Download report in your preferred format',
                style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _exportButton(
                      'PDF',
                      Icons.picture_as_pdf,
                      SuperAdminTheme.red,
                      () => _exportReport('pdf'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _exportButton(
                      'Excel',
                      Icons.table_chart,
                      SuperAdminTheme.green,
                      () => _exportReport('excel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _exportButton(
                      'CSV',
                      Icons.description,
                      SuperAdminTheme.blue,
                      () => _exportReport('csv'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Report Summary
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: SuperAdminTheme.green),
            ),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: SuperAdminTheme.card(),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 40, color: SuperAdminTheme.red),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: SuperAdminTheme.inter(13, color: SuperAdminTheme.red),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _generateReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SuperAdminTheme.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (_reportData != null) ...[
          _buildKpiSummary(_reportData!),
          const SizedBox(height: 12),
          _buildPickupsByZone(_reportData!),
          const SizedBox(height: 12),
          _buildRevenueByMonth(_reportData!),
        ]
        else if (!_loading && _reportData == null) ...[
          Container(
            padding: const EdgeInsets.all(40),
            decoration: SuperAdminTheme.card(),
            child: Column(
              children: [
                Icon(Icons.assessment_outlined, size: 48, color: SuperAdminTheme.muted),
                const SizedBox(height: 16),
                Text(
                  'No report generated yet',
                  style: SuperAdminTheme.sora(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a report type and date range, then tap Generate.',
                  style: SuperAdminTheme.inter(12.5, color: SuperAdminTheme.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _generateReport,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Generate Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SuperAdminTheme.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateButton(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SuperAdminTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SuperAdminTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: SuperAdminTheme.inter(11, color: SuperAdminTheme.muted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: SuperAdminTheme.inter(13, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: _generating ? SuperAdminTheme.border : color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _generating ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24,
                color: _generating ? SuperAdminTheme.muted : Colors.white,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: SuperAdminTheme.inter(
                  12,
                  weight: FontWeight.w600,
                  color: _generating ? SuperAdminTheme.muted : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiSummary(ReportData data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report Summary',
            style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${_typeName(_selectedType)} — ${DateFormat('MMM d, yyyy').format(data.startDate)} to ${DateFormat('MMM d, yyyy').format(data.endDate)}',
            style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _kpiCard('Clients', '${data.activeClients}/${data.totalClients}', Icons.people, SuperAdminTheme.green),
              _kpiCard('Collectors', '${data.activeCollectors}/${data.totalCollectors}', Icons.local_shipping, SuperAdminTheme.gold),
              _kpiCard('Pickups', '${data.completedPickups}/${data.totalPickups}', Icons.check_circle, SuperAdminTheme.blue),
              _kpiCard('Completion', '${data.completionRate.toStringAsFixed(0)}%', Icons.trending_up, SuperAdminTheme.green),
              _kpiCard('Revenue', '${NumberFormat('#,##0').format(data.totalRevenue.round())} XAF', Icons.attach_money, SuperAdminTheme.gold),
              _kpiCard('Contracts', '${data.activeContracts} active', Icons.description, SuperAdminTheme.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: SuperAdminTheme.sora(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: SuperAdminTheme.inter(11, color: SuperAdminTheme.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupsByZone(ReportData data) {
    if (data.pickupsByZone.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pickups by Zone',
            style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...data.pickupsByZone.entries.map((entry) {
            final total = data.totalPickups;
            final percentage = total > 0 ? entry.value / total : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: SuperAdminTheme.inter(12.5, weight: FontWeight.w500),
                      ),
                      Text(
                        '${entry.value} pickups',
                        style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: SuperAdminTheme.border,
                    color: SuperAdminTheme.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRevenueByMonth(ReportData data) {
    if (data.revenueByMonth.isEmpty) return const SizedBox.shrink();

    final sorted = data.revenueByMonth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxRevenue = sorted.fold<double>(
      0,
      (max, e) => e.value > max ? e.value : max,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revenue by Month',
            style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: sorted.map((entry) {
                // Max bar height = 120 - label - spacers = ~94px
                final height = maxRevenue > 0
                    ? (entry.value / maxRevenue * 94)
                    : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          NumberFormat('#,##0').format(entry.value.round()),
                          style: SuperAdminTheme.inter(9, color: SuperAdminTheme.muted),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            color: SuperAdminTheme.gold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.key.substring(5), // 'MM'
                          style: SuperAdminTheme.inter(10, color: SuperAdminTheme.muted),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _typeName(ReportType type) => switch (type) {
    ReportType.daily => 'Daily',
    ReportType.weekly => 'Weekly',
    ReportType.monthly => 'Monthly',
    ReportType.annual => 'Annual',
    ReportType.paymentLog => 'Payment Log',
  };
}
