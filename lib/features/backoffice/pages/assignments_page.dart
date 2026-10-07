import 'package:flutter/material.dart';

import '../../../models/assignment_model.dart';
import '../data/backoffice_store.dart';
import '../theme.dart';
import '../widgets/badge.dart';
import '../widgets/chips.dart';

/// Page « Assignments » : agency managers assign collectors to zones with
/// specific time windows and dates.
///
/// From the cahier des charges:
///   - Permet d'affecter un collecteur à une ou plusieurs zones
///   - Informations : collecteur, zone, heure de début, heure de fin, date
class BoAssignmentsPage extends StatefulWidget {
  const BoAssignmentsPage({
    super.key,
    required this.store,
    this.desktop = false,
  });

  final BackofficeStore store;
  final bool desktop;

  @override
  State<BoAssignmentsPage> createState() => _BoAssignmentsPageState();
}

class _BoAssignmentsPageState extends State<BoAssignmentsPage> {
  String _filter = 'All';

  List<AssignmentModel> get _items {
    final all = widget.store.assignments;
    if (_filter == 'All') return all;
    return all.where((a) => a.status == _filter).toList();
  }

  // --- CRUD dialogs ---

  Future<void> _addAssignment() async {
    final result = await _showAssignmentDialog();
    if (result != null) {
      try {
        await widget.store.addAssignment(
          collecteurId: result.collecteurId,
          collecteurName: result.collecteurName,
          zoneId: result.zoneId,
          zoneName: result.zoneName,
          startTime: result.startTime,
          endTime: result.endTime,
          date: result.date,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assignment created'),
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

  Future<void> _editAssignment(AssignmentModel assignment) async {
    final result = await _showAssignmentDialog(assignment: assignment);
    if (result != null) {
      try {
        await widget.store.updateAssignment(assignment.copyWith(
          collecteurId: result.collecteurId,
          collecteurName: result.collecteurName,
          zoneId: result.zoneId,
          zoneName: result.zoneName,
          startTime: result.startTime,
          endTime: result.endTime,
          date: result.date,
        ));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assignment updated'),
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

  Future<void> _deleteAssignment(AssignmentModel assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete Assignment', style: BackofficeTheme.inter(16, weight: FontWeight.w700)),
        content: Text(
          'Remove ${assignment.collecteurName} from ${assignment.zoneName}?',
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
        await widget.store.deleteAssignment(assignment.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment deleted'), backgroundColor: BackofficeTheme.green),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: BackofficeTheme.red),
        );
      }
    }
  }

  /// Vrai si le statut signifie « utilisable » — tolère les variantes de
  /// casse et le français (« Actif »), comme le reste de l'app
  /// (cf. FirestoreBackofficeStore._isActive).
  bool _isUsable(String status) {
    final s = status.trim().toLowerCase();
    return s == 'active' || s == 'actif';
  }

  /// Shows the add/edit assignment dialog. Returns null if cancelled.
  Future<_AssignmentResult?> _showAssignmentDialog({AssignmentModel? assignment}) async {
    final store = widget.store;
    // Tolérant casse + « Actif » : un collecteur avec le statut « Actif »
    // (ou toute casse différente) ne doit pas disparaître de la liste.
    final collecteurs = store.collecteurs.where((c) => _isUsable(c.status)).toList();
    final zones = store.zones.where((z) => _isUsable(z.status)).toList();

    String selectedCollecteurId = assignment?.collecteurId ?? (collecteurs.isNotEmpty ? collecteurs.first.id : '');
    String selectedZoneId = assignment?.zoneId ?? (zones.isNotEmpty ? zones.first.id : '');
    String startTime = assignment?.startTime ?? '07:00';
    String endTime = assignment?.endTime ?? '12:00';
    DateTime date = assignment != null
        ? (DateTime.tryParse(assignment.date) ?? DateTime.now())
        : DateTime.now();

    // Noms résolus sur TOUS les collecteurs (pas seulement les actifs) :
    // une affectation existante pointant vers un collecteur désormais
    // inactif doit quand même afficher son nom dans le dialogue d'édition.
    String collecteurNameForId(String id) {
      for (final c in store.collecteurs) {
        if (c.id == id) return c.name;
      }
      return '';
    }

    String zoneNameForId(String id) {
      for (final z in zones) {
        if (z.id == id) return z.name;
      }
      return '';
    }

    String fmtDate(DateTime d) {
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    return showDialog<_AssignmentResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            assignment == null ? 'New Assignment' : 'Edit Assignment',
            style: BackofficeTheme.inter(16, weight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Collector
                Text('Collector', style: BackofficeTheme.inter(12, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedCollecteurId.isNotEmpty && collecteurs.any((c) => c.id == selectedCollecteurId)
                      ? selectedCollecteurId
                      : null,
                  isExpanded: true,
                  style: BackofficeTheme.inter(13),
                  dropdownColor: BackofficeTheme.surface,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: BackofficeTheme.muted),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: BackofficeTheme.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: collecteurs.map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedCollecteurId = v);
                  },
                ),
                const SizedBox(height: 16),

                // Zone
                Text('Zone', style: BackofficeTheme.inter(12, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedZoneId.isNotEmpty && zones.any((z) => z.id == selectedZoneId)
                      ? selectedZoneId
                      : null,
                  isExpanded: true,
                  style: BackofficeTheme.inter(13),
                  dropdownColor: BackofficeTheme.surface,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: BackofficeTheme.muted),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: BackofficeTheme.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: zones.map((z) => DropdownMenuItem(
                    value: z.id,
                    child: Text(z.name),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedZoneId = v);
                  },
                ),
                const SizedBox(height: 16),

                // Time range
                Text('Time window', style: BackofficeTheme.inter(12, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: startTime),
                        style: BackofficeTheme.inter(13),
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          hintText: '07:00',
                          hintStyle: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: BackofficeTheme.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                          prefixIcon: Icon(Icons.access_time, size: 16, color: BackofficeTheme.muted),
                        ),
                        onChanged: (v) => startTime = v.trim(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('—', style: BackofficeTheme.inter(14, color: BackofficeTheme.muted)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: endTime),
                        style: BackofficeTheme.inter(13),
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          hintText: '12:00',
                          hintStyle: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: BackofficeTheme.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                          prefixIcon: Icon(Icons.access_time, size: 16, color: BackofficeTheme.muted),
                        ),
                        onChanged: (v) => endTime = v.trim(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Date
                Text('Date', style: BackofficeTheme.inter(12, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: BackofficeTheme.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                      prefixIcon: Icon(Icons.calendar_today, size: 16, color: BackofficeTheme.muted),
                    ),
                    child: Text(fmtDate(date), style: BackofficeTheme.inter(13)),
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
                final cName = collecteurNameForId(selectedCollecteurId);
                final zName = zoneNameForId(selectedZoneId);
                if (selectedCollecteurId.isEmpty || selectedZoneId.isEmpty) return;
                Navigator.of(ctx).pop(_AssignmentResult(
                  collecteurId: selectedCollecteurId,
                  collecteurName: cName,
                  zoneId: selectedZoneId,
                  zoneName: zName,
                  startTime: startTime,
                  endTime: endTime,
                  date: fmtDate(date),
                ));
              },
              child: Text(
                assignment == null ? 'Create' : 'Save',
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
                    options: const ['All', 'Active', 'Completed', 'Cancelled'],
                    selected: _filter,
                    onSelect: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addAssignment,
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
                        Text('Add assignment', style: BackofficeTheme.inter(11, weight: FontWeight.w600, color: Colors.white)),
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
                          Icon(Icons.assignment_ind_outlined, size: 40, color: BackofficeTheme.muted),
                          const SizedBox(height: 10),
                          Text(
                            'No assignments found',
                            style: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Assign collectors to zones with time windows',
                            style: BackofficeTheme.inter(11, color: BackofficeTheme.border),
                          ),
                          const SizedBox(height: 14),
                          _actionBtn('Add assignment', Icons.add, _addAssignment),
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

  Widget _card(BuildContext context, AssignmentModel assignment) {
    final isActive = assignment.status == 'Active';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BackofficeTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: collector + status badge
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
                  Icons.assignment_ind_outlined,
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
                      assignment.collecteurName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '→ ${assignment.zoneName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                    ),
                  ],
                ),
              ),
              BoBadge(status: assignment.status),
            ],
          ),
          // Time + date info
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 13, color: BackofficeTheme.muted),
              const SizedBox(width: 4),
              Text(
                '${assignment.startTime} — ${assignment.endTime}',
                style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
              ),
              const SizedBox(width: 12),
              Icon(Icons.calendar_today_outlined, size: 13, color: BackofficeTheme.muted),
              const SizedBox(width: 4),
              Text(
                assignment.date,
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
                () => _editAssignment(assignment),
              ),
              const SizedBox(width: 8),
              _actionBtn(
                'Delete',
                Icons.delete_outline,
                () => _deleteAssignment(assignment),
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

class _AssignmentResult {
  final String collecteurId;
  final String collecteurName;
  final String zoneId;
  final String zoneName;
  final String startTime;
  final String endTime;
  final String date;

  const _AssignmentResult({
    required this.collecteurId,
    required this.collecteurName,
    required this.zoneId,
    required this.zoneName,
    required this.startTime,
    required this.endTime,
    required this.date,
  });
}
