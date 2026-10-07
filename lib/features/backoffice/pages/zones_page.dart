import 'package:flutter/material.dart';

import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/badge.dart';
import '../widgets/chips.dart';

/// Page « Zones » : agency managers define and manage collection calendars
/// per zone (fixed day(s) of the week + standard pickup time window).
///
/// Clients in a zone inherit these days when they pick a frequency tier.
class BoZonesPage extends StatefulWidget {
  const BoZonesPage({
    super.key,
    required this.store,
    this.desktop = false,
  });

  final BackofficeStore store;
  final bool desktop;

  @override
  State<BoZonesPage> createState() => _BoZonesPageState();
}

class _BoZonesPageState extends State<BoZonesPage> {
  String _filter = 'All';

  static const _allDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const _dayAbbrev = {
    'Monday': 'Mon',
    'Tuesday': 'Tue',
    'Wednesday': 'Wed',
    'Thursday': 'Thu',
    'Friday': 'Fri',
    'Saturday': 'Sat',
    'Sunday': 'Sun',
  };

  List<ZoneModel> get _items {
    final all = widget.store.zones;
    if (_filter == 'All') return all;
    return all.where((z) => z.status == _filter).toList();
  }

  // --- CRUD dialogs ---

  Future<void> _addZone() async {
    final result = await _showZoneDialog();
    if (result != null) {
      try {
        await widget.store.addZone(
          name: result.name,
          collectionDays: result.days,
          standardPickupTime: result.time,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zone created'),
            backgroundColor: BackofficeTheme.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: BackofficeTheme.red),
        );
      }
    }
  }

  Future<void> _editZone(ZoneModel zone) async {
    final result = await _showZoneDialog(zone: zone);
    if (result != null) {
      try {
        await widget.store.updateZone(zone.copyWith(
          name: result.name,
          collectionDays: result.days,
          standardPickupTime: result.time,
        ));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zone updated'),
            backgroundColor: BackofficeTheme.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: BackofficeTheme.red),
        );
      }
    }
  }

  Future<void> _deleteZone(ZoneModel zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete Zone', style: BackofficeTheme.inter(16, weight: FontWeight.w700)),
        content: Text(
          'Delete "${zone.name}"? This cannot be undone.',
          style: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: BackofficeTheme.inter(13)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: BackofficeTheme.inter(13, weight: FontWeight.w600, color: BackofficeTheme.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.store.deleteZone(zone.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zone deleted'), backgroundColor: BackofficeTheme.green),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: BackofficeTheme.red),
        );
      }
    }
  }

  /// Shows the add/edit zone dialog. Returns null if cancelled.
  Future<_ZoneResult?> _showZoneDialog({ZoneModel? zone}) async {
    final nameCtrl = TextEditingController(text: zone?.name ?? '');
    final timeCtrl = TextEditingController(text: zone?.standardPickupTime ?? '07:00 — 08:00');
    final selectedDays = Set<String>.from(zone?.collectionDays ?? []);

    return showDialog<_ZoneResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            zone == null ? 'New Zone' : 'Edit Zone',
            style: BackofficeTheme.inter(16, weight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Zone name
                Text('Zone name', style: BackofficeTheme.inter(12, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: BackofficeTheme.inter(13),
                  decoration: InputDecoration(
                    hintText: 'Ex. Bastos',
                    hintStyle: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: BackofficeTheme.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),

                // Collection days
                Text('Collection day(s)', style: BackofficeTheme.inter(12, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allDays.map((day) {
                    final isSelected = selectedDays.contains(day);
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          if (isSelected) {
                            selectedDays.remove(day);
                          } else {
                            selectedDays.add(day);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected ? BackofficeTheme.green : BackofficeTheme.graySoft,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? BackofficeTheme.green : BackofficeTheme.border,
                          ),
                        ),
                        child: Text(
                          _dayAbbrev[day] ?? day,
                          style: BackofficeTheme.inter(
                            11,
                            weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? Colors.white : BackofficeTheme.text,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Pickup time window
                Text('Pickup time window', style: BackofficeTheme.inter(12, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: timeCtrl,
                  style: BackofficeTheme.inter(13),
                  decoration: InputDecoration(
                    hintText: '07:00 — 08:00',
                    hintStyle: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: BackofficeTheme.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: BackofficeTheme.inter(13)),
            ),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty || selectedDays.isEmpty) return;
                Navigator.of(ctx).pop(_ZoneResult(
                  name: name,
                  days: selectedDays.toList()..sort(),
                  time: timeCtrl.text.trim(),
                ));
              },
              child: Text(
                zone == null ? 'Create' : 'Save',
                style: BackofficeTheme.inter(
                  13,
                  weight: FontWeight.w600,
                  color: BackofficeTheme.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final items = _items;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: BoChipRow(
                    options: const ['All', 'Active', 'Inactive'],
                    selected: _filter,
                    onSelect: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addZone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: BackofficeTheme.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text('Add zone', style: BackofficeTheme.inter(11, weight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 40, color: BackofficeTheme.muted),
                          const SizedBox(height: 10),
                          Text(
                            'No zones found',
                            style: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
                          ),
                          const SizedBox(height: 14),
                          _actionBtn('Add zone', Icons.add, _addZone),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        widget.desktop ? 2 : 16,
                        0,
                        widget.desktop ? 2 : 16,
                        widget.desktop ? 24 : 110,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, i) => _card(context, items[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, ZoneModel zone) {
    final isActive = zone.status == 'Active';
    final dayLabels = zone.collectionDays
        .map((d) => _dayAbbrev[d] ?? d)
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BackofficeTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: name + status badge
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive ? BackofficeTheme.greenSoft : BackofficeTheme.graySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.map_outlined,
                  size: 16,
                  color: isActive ? BackofficeTheme.green : BackofficeTheme.muted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      dayLabels.isNotEmpty ? 'Every $dayLabels' : 'No days set',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                    ),
                  ],
                ),
              ),
              BoBadge(status: isActive ? 'Active' : 'Inactive'),
            ],
          ),
          // Time window
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 13, color: BackofficeTheme.muted),
              const SizedBox(width: 4),
              Text(
                'Pickup window: ${zone.standardPickupTime}',
                style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
              ),
            ],
          ),
          // Action buttons
          const SizedBox(height: 10),
          Row(
            children: [
              _actionBtn(
                'Edit',
                Icons.edit_outlined,
                () => _editZone(zone),
              ),
              const SizedBox(width: 8),
              _actionBtn(
                'Delete',
                Icons.delete_outline,
                () => _deleteZone(zone),
                color: BackofficeTheme.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap, {Color? color}) {
    final c = color ?? BackofficeTheme.green;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(label, style: BackofficeTheme.inter(11, weight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }
}

class _ZoneResult {
  final String name;
  final List<String> days;
  final String time;

  const _ZoneResult({required this.name, required this.days, required this.time});
}
