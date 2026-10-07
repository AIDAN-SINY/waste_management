import 'package:flutter/material.dart';

import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';

/// Page showing maintenance history and reminders for a specific vehicle.
///
/// Displays:
///   - Vehicle info card with next service reminder
///   - Maintenance log history sorted by date
///   - Add new maintenance entry button + form
class VehicleMaintenancePage extends StatefulWidget {
  const VehicleMaintenancePage({
    super.key,
    required this.store,
    required this.vehicle,
  });

  final BackofficeStore store;
  final VehicleModel vehicle;

  @override
  State<VehicleMaintenancePage> createState() => _VehicleMaintenancePageState();
}

class _VehicleMaintenancePageState extends State<VehicleMaintenancePage> {
  late List<VehicleMaintenanceModel> _logs;

  @override
  void initState() {
    super.initState();
    _logs = widget.store.maintenanceForVehicle(widget.vehicle.id);
  }

  void _refreshLogs() {
    setState(() {
      _logs = widget.store.maintenanceForVehicle(widget.vehicle.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;

    return Scaffold(
      backgroundColor: BackofficeTheme.bg,
      appBar: AppBar(
        backgroundColor: BackofficeTheme.surface,
        foregroundColor: BackofficeTheme.green,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${v.type} — ${v.plateNumber}',
              style: BackofficeTheme.sora(15, weight: FontWeight.w600),
            ),
            Text(
              '${v.brand} ${v.model}',
              style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final logs = widget.store.maintenanceForVehicle(widget.vehicle.id);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Vehicle Info + Next Service Reminder ---
                _buildVehicleCard(v, logs),
                const SizedBox(height: 16),

                // --- Maintenance History ---
                Text(
                  'Maintenance History',
                  style: BackofficeTheme.sora(14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (logs.isEmpty)
                  _buildEmptyState()
                else
                  for (final log in logs) ...[
                    _buildLogCard(log),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddLogSheet(context),
        backgroundColor: BackofficeTheme.gold,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 24, color: Color(0xFF073A1B)),
      ),
    );
  }

  // ---- Vehicle info card with reminder ----

  Widget _buildVehicleCard(VehicleModel v, List<VehicleMaintenanceModel> logs) {
    // Calculate next service info.
    final lastDate = DateTime.tryParse(v.lastMaintenanceDate);
    final now = DateTime.now();
    final nextServiceDate = lastDate?.add(Duration(days: v.maintenanceIntervalDays));
    final nextServiceMileage = v.mileage + v.maintenanceIntervalKm;

    // Check if overdue.
    bool isOverdue = false;
    String reminderText = '';
    if (nextServiceDate != null && nextServiceDate.isBefore(now)) {
      isOverdue = true;
      final daysOver = now.difference(nextServiceDate).inDays;
      reminderText = 'Overdue by $daysOver day(s)';
    } else if (nextServiceDate != null) {
      final daysUntil = nextServiceDate.difference(now).inDays;
      reminderText = 'Due in $daysUntil day(s)';
    }

    // Overdue by mileage?
    if (v.mileage >= nextServiceMileage && !isOverdue) {
      isOverdue = true;
      reminderText = 'Mileage limit reached';
    } else if (v.mileage >= nextServiceMileage - 500 && !isOverdue) {
      reminderText = 'Mileage service approaching';
    }

    if (reminderText.isEmpty) {
      reminderText = 'Next service: ${nextServiceDate != null ? _fmtDate(nextServiceDate) : 'N/A'}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOverdue ? BackofficeTheme.redSoft : BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue ? BackofficeTheme.red : BackofficeTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOverdue
                      ? BackofficeTheme.red.withValues(alpha: 0.12)
                      : BackofficeTheme.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isOverdue ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: isOverdue ? BackofficeTheme.red : BackofficeTheme.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOverdue ? 'Maintenance Overdue' : 'Service Status',
                      style: BackofficeTheme.sora(13, weight: FontWeight.w600),
                    ),
                    Text(
                      reminderText,
                      style: BackofficeTheme.inter(
                        11,
                        color: isOverdue ? BackofficeTheme.red : BackofficeTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _infoChip(Icons.speed, '${v.mileage} km'),
              const SizedBox(width: 8),
              _infoChip(Icons.calendar_today, 'Every ${v.maintenanceIntervalDays}d'),
              const SizedBox(width: 8),
              _infoChip(Icons.straighten, 'Every ${v.maintenanceIntervalKm} km'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoChip(Icons.build_outlined, '${logs.length} services'),
              const SizedBox(width: 8),
              _infoChip(
                Icons.attach_money,
                '${_totalCost(logs)} XAF',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BackofficeTheme.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: BackofficeTheme.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: BackofficeTheme.inter(10, weight: FontWeight.w600, color: BackofficeTheme.muted),
          ),
        ],
      ),
    );
  }

  int _totalCost(List<VehicleMaintenanceModel> logs) {
    return logs.fold(0, (sum, log) => sum + log.cost);
  }

  // ---- Empty state ----

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BackofficeTheme.border),
      ),
      child: Column(
        children: [
          Icon(Icons.build_outlined, size: 32, color: BackofficeTheme.muted),
          const SizedBox(height: 10),
          Text(
            'No maintenance records',
            style: BackofficeTheme.sora(13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to add the first service entry',
            style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
          ),
        ],
      ),
    );
  }

  // ---- Log card ----

  Widget _buildLogCard(VehicleMaintenanceModel log) {
    final isOverdue = log.status == 'Overdue';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? BackofficeTheme.red : BackofficeTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: BackofficeTheme.greenSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _iconForType(log.type),
                  size: 16,
                  color: BackofficeTheme.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.type,
                      style: BackofficeTheme.sora(12, weight: FontWeight.w600),
                    ),
                    Text(
                      _fmtDate(DateTime.tryParse(log.serviceDate) ?? DateTime.now()),
                      style: BackofficeTheme.inter(10, color: BackofficeTheme.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? BackofficeTheme.redSoft
                      : BackofficeTheme.greenSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  log.status,
                  style: BackofficeTheme.inter(
                    9,
                    weight: FontWeight.w700,
                    color: isOverdue ? BackofficeTheme.red : BackofficeTheme.green,
                  ),
                ),
              ),
            ],
          ),
          if (log.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              log.description,
              style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (log.mileageAtService > 0) ...[
                _infoChip(Icons.speed, '${log.mileageAtService} km'),
                const SizedBox(width: 6),
              ],
              if (log.cost > 0) ...[
                _infoChip(Icons.attach_money, '${log.cost} XAF'),
                const SizedBox(width: 6),
              ],
              if (log.mechanicName.isNotEmpty)
                _infoChip(Icons.person_outline, log.mechanicName),
            ],
          ),
          if (log.nextServiceDate.isNotEmpty || log.nextServiceMileage > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BackofficeTheme.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 12, color: BackofficeTheme.gold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Next: ${log.nextServiceDate.isNotEmpty ? _fmtDate(DateTime.tryParse(log.nextServiceDate) ?? DateTime.now()) : 'N/A'}'
                      '${log.nextServiceMileage > 0 ? ' · ${log.nextServiceMileage} km' : ''}',
                      style: BackofficeTheme.inter(10, weight: FontWeight.w600, color: BackofficeTheme.gold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'Oil Change' => Icons.water_drop_outlined,
      'Tire Rotation' => Icons.circle_outlined,
      'Brake Service' => Icons.stop_circle_outlined,
      'Engine Repair' => Icons.build_outlined,
      'General Inspection' => Icons.plumbing_outlined,
      _ => Icons.build_outlined,
    };
  }

  // ---- Add log bottom sheet ----

  void _showAddLogSheet(BuildContext context) {
    final typeCtrl = TextEditingController(text: 'General Inspection');
    final descCtrl = TextEditingController();
    final mileageCtrl = TextEditingController(text: '${widget.vehicle.mileage}');
    final costCtrl = TextEditingController();
    final mechanicCtrl = TextEditingController();
    String selectedType = 'General Inspection';
    String selectedStatus = 'Completed';

    final types = [
      'Oil Change',
      'Tire Rotation',
      'Brake Service',
      'Engine Repair',
      'General Inspection',
      'Other',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BackofficeTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: BackofficeTheme.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Add Maintenance Record',
                    style: BackofficeTheme.sora(15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),

                  // Type dropdown
                  _sheetLabel('Service Type'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: BackofficeTheme.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BackofficeTheme.border),
                    ),
                    child: DropdownButton<String>(
                      value: selectedType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      style: BackofficeTheme.inter(13),
                      items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (v) => setModalState(() => selectedType = v ?? selectedType),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Description
                  _sheetLabel('Description'),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    style: BackofficeTheme.inter(13),
                    decoration: _sheetFieldDec('Work performed...'),
                  ),
                  const SizedBox(height: 12),

                  // Mileage
                  _sheetLabel('Mileage at Service (km)'),
                  TextField(
                    controller: mileageCtrl,
                    keyboardType: TextInputType.number,
                    style: BackofficeTheme.inter(13),
                    decoration: _sheetFieldDec('e.g. 4320'),
                  ),
                  const SizedBox(height: 12),

                  // Cost
                  _sheetLabel('Cost (XAF)'),
                  TextField(
                    controller: costCtrl,
                    keyboardType: TextInputType.number,
                    style: BackofficeTheme.inter(13),
                    decoration: _sheetFieldDec('e.g. 15000'),
                  ),
                  const SizedBox(height: 12),

                  // Mechanic
                  _sheetLabel('Mechanic / Workshop'),
                  TextField(
                    controller: mechanicCtrl,
                    style: BackofficeTheme.inter(13),
                    decoration: _sheetFieldDec('e.g. Garage Bonamoussadi'),
                  ),
                  const SizedBox(height: 12),

                  // Status
                  _sheetLabel('Status'),
                  Row(
                    children: [
                      for (final s in ['Completed', 'Scheduled', 'Overdue'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(s, style: BackofficeTheme.inter(11, weight: FontWeight.w600)),
                            selected: selectedStatus == s,
                            onSelected: (_) => setModalState(() => selectedStatus = s),
                            selectedColor: BackofficeTheme.greenSoft,
                            side: BorderSide(
                              color: selectedStatus == s ? BackofficeTheme.green : BackofficeTheme.border,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final v = widget.vehicle;
                        final now = DateTime.now();
                        final nextDate = now.add(Duration(days: v.maintenanceIntervalDays));
                        final mileage = int.tryParse(mileageCtrl.text.trim()) ?? 0;

                        await widget.store.addMaintenanceLog(
                          vehicleId: v.id,
                          vehiclePlate: v.plateNumber,
                          type: selectedType,
                          description: descCtrl.text.trim(),
                          mileageAtService: mileage,
                          serviceDate: _fmtDate(now),
                          cost: int.tryParse(costCtrl.text.trim()) ?? 0,
                          mechanicName: mechanicCtrl.text.trim(),
                          nextServiceDate: _fmtDate(nextDate),
                          nextServiceMileage: mileage + v.maintenanceIntervalKm,
                          status: selectedStatus,
                        );

                        if (mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Maintenance record added for ${v.plateNumber}'),
                              backgroundColor: BackofficeTheme.green,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BackofficeTheme.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Save Record',
                        style: BackofficeTheme.inter(13, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: BackofficeTheme.inter(11, weight: FontWeight.w600, color: BackofficeTheme.muted),
      ),
    );
  }

  InputDecoration _sheetFieldDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
      filled: true,
      fillColor: BackofficeTheme.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.green),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
