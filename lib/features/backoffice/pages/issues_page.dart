import 'package:flutter/material.dart';

import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/badge.dart';
import '../widgets/chips.dart';

/// Page « Issues » : client-reported issues (overflowing bins, missed
/// collections, illegal dumping, etc.) that the agency manager can review
/// and resolve.
class BoIssuesPage extends StatefulWidget {
  const BoIssuesPage({
    super.key,
    required this.store,
    this.desktop = false,
  });

  final BackofficeStore store;
  final bool desktop;

  @override
  State<BoIssuesPage> createState() => _BoIssuesPageState();
}

class _BoIssuesPageState extends State<BoIssuesPage> {
  String _filter = 'All';

  static const _labels = <String, String>{
    'open': 'Open',
    'assigned': 'Assigned',
    'in_progress': 'In Progress',
    'resolved': 'Resolved',
  };

  static const _statusColors = <String, Color>{
    'open': BackofficeTheme.red,
    'assigned': BackofficeTheme.gold,
    'in_progress': BackofficeTheme.gold,
    'resolved': BackofficeTheme.green,
  };

  List<IssueModel> get _items {
    final all = widget.store.issues;
    if (_filter == 'All') return all;
    return all.where((i) => i.status == _filter.toLowerCase().replaceAll(' ', '_')).toList();
  }

  /// Opens the collector picker and assigns [issue] to the chosen one.
  Future<void> _assign(IssueModel issue) async {
    final chosen = await showModalBottomSheet<CollecteurModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BackofficeTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => AssignIssueSheet(store: widget.store, issue: issue),
    );
    if (chosen == null || !mounted) return;
    try {
      await widget.store.assignIssue(issue, chosen);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Issue assigned to ${chosen.name} — he has been notified'),
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

  Future<void> _resolve(IssueModel issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Resolve Issue',
          style: BackofficeTheme.inter(16, weight: FontWeight.w700),
        ),
        content: Text(
          'Mark this issue as resolved?\n\n${issue.category}: ${issue.description}',
          style: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: BackofficeTheme.inter(13)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Resolve',
              style: BackofficeTheme.inter(13, weight: FontWeight.w600, color: BackofficeTheme.green),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.store.resolveIssue(issue);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Issue marked as resolved'),
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
            BoChipRow(
              options: const ['All', 'Open', 'Assigned', 'In Progress', 'Resolved'],
              selected: _filter,
              onSelect: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? _EmptyState(text: 'No issues found')
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

  Widget _card(BuildContext context, IssueModel issue) {
    final isOpen = issue.status == 'open';
    final isResolved = issue.status == 'resolved';
    final statusColor = _statusColors[issue.status] ?? BackofficeTheme.muted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BackofficeTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: category + status badge
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isOpen ? BackofficeTheme.redSoft : BackofficeTheme.greenSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isOpen ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  size: 16,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${issue.clientName} · ${issue.createdAt}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                    ),
                  ],
                ),
              ),
              BoBadge(status: _labels[issue.status] ?? issue.status),
            ],
          ),
          // Description
          const SizedBox(height: 10),
          Text(
            issue.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BackofficeTheme.inter(12, color: BackofficeTheme.muted),
          ),
          // Location (if present)
          if (issue.location.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 13, color: BackofficeTheme.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    issue.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                  ),
                ),
              ],
            ),
          ],
          // Collector handling it
          if (issue.assignedCollecteurId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.engineering_outlined, size: 13, color: BackofficeTheme.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Assigned to ${issue.assignedCollectorName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BackofficeTheme.inter(11, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          // Action buttons
          if (!isResolved) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: Key('issue_assign_${issue.id}'),
                  onPressed: () => _assign(issue),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BackofficeTheme.green,
                    side: const BorderSide(color: BackofficeTheme.green),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                  child: Text(
                    issue.assignedCollecteurId.isEmpty ? 'Assign' : 'Reassign',
                    style: BackofficeTheme.inter(11.5, weight: FontWeight.w600,
                        color: BackofficeTheme.green),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: BackofficeTheme.green,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    onTap: () => _resolve(issue),
                    borderRadius: BorderRadius.circular(9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Text(
                        'Resolve',
                        style: BackofficeTheme.inter(
                          11.5,
                          weight: FontWeight.w600,
                          color: BackofficeTheme.cream,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One collector proposed for an issue, with his availability right now.
class IssueCandidate {
  const IssueCandidate({
    required this.collecteur,
    required this.availability,
    required this.openIssues,
    required this.isClientsCollector,
    required this.servesZone,
    this.coversClient = false,
  });

  final CollecteurModel collecteur;
  final CollectorAvailability availability;
  final int openIssues;

  /// The client's regular collector.
  final bool isClientsCollector;

  /// Works in the client's zone (by zone name).
  final bool servesZone;

  /// The client's GPS position lies inside the zone circled on the map
  /// for this collector.
  final bool coversClient;

  bool get canAssign => availability != CollectorAvailability.inactive;
}

/// Collectors ranked for [issue]: available first (the client's own
/// collector, then those in his zone, then the least loaded), then busy,
/// then off duty; inactive ones last (they cannot be picked).
List<IssueCandidate> rankCollectorsForIssue(
  BackofficeStore store,
  IssueModel issue, {
  DateTime? now,
}) {
  String digits(String p) => p.replaceAll(RegExp(r'\D'), '');
  final clientDigits = digits(issue.clientId);
  final client = store.clients
      .where((c) => clientDigits.isNotEmpty && digits(c.phone).endsWith(
          clientDigits.length > 9 ? clientDigits.substring(clientDigits.length - 9) : clientDigits))
      .firstOrNull;
  final zone = (client?.zone ?? '').toLowerCase().trim();

  final list = [
    for (final c in store.collecteurs)
      IssueCandidate(
        collecteur: c,
        availability: collectorAvailability(c,
            openIssues: store.openIssuesOf(c.id), now: now),
        openIssues: store.openIssuesOf(c.id),
        isClientsCollector: client != null && client.collecteurId == c.id,
        servesZone: zone.isNotEmpty &&
            c.zone.toLowerCase().trim().isNotEmpty &&
            (zone.contains(c.zone.toLowerCase().trim()) ||
                c.zone.toLowerCase().contains(zone)),
        coversClient: client?.latitude != null &&
            client?.longitude != null &&
            (c.zoneArea?.contains(client!.latitude!, client.longitude!) ??
                false),
      ),
  ];
  list.sort((a, b) {
    final byAvailability = a.availability.index - b.availability.index;
    if (byAvailability != 0) return byAvailability;
    if (a.isClientsCollector != b.isClientsCollector) {
      return a.isClientsCollector ? -1 : 1;
    }
    if (a.coversClient != b.coversClient) return a.coversClient ? -1 : 1;
    if (a.servesZone != b.servesZone) return a.servesZone ? -1 : 1;
    final byLoad = a.openIssues - b.openIssues;
    if (byLoad != 0) return byLoad;
    return b.collecteur.rating.compareTo(a.collecteur.rating);
  });
  return list;
}

/// Bottom sheet: the manager picks the collector who will handle an issue.
/// Returns the chosen [CollecteurModel] (null when cancelled).
class AssignIssueSheet extends StatefulWidget {
  const AssignIssueSheet({
    super.key,
    required this.store,
    required this.issue,
    this.now,
  });

  final BackofficeStore store;
  final IssueModel issue;

  /// Clock override (tests).
  final DateTime? now;

  @override
  State<AssignIssueSheet> createState() => _AssignIssueSheetState();
}

class _AssignIssueSheetState extends State<AssignIssueSheet> {
  late final List<IssueCandidate> _candidates =
      rankCollectorsForIssue(widget.store, widget.issue, now: widget.now);

  /// Pre-selected: the best assignable candidate (other than the current
  /// collector when reassigning).
  late String? _selectedId = _candidates
      .where((c) => c.canAssign &&
          c.collecteur.id != widget.issue.assignedCollecteurId)
      .map((c) => c.collecteur.id)
      .firstOrNull;

  static const _colors = <CollectorAvailability, Color>{
    CollectorAvailability.available: BackofficeTheme.green,
    CollectorAvailability.busy: BackofficeTheme.gold,
    CollectorAvailability.offDuty: BackofficeTheme.muted,
    CollectorAvailability.inactive: BackofficeTheme.red,
  };

  @override
  Widget build(BuildContext context) {
    final availableCount = _candidates
        .where((c) => c.availability == CollectorAvailability.available)
        .length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.issue.assignedCollecteurId.isEmpty
                  ? 'Assign this issue'
                  : 'Reassign this issue',
              style: BackofficeTheme.sora(15.5, weight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              '${widget.issue.category} · ${widget.issue.clientName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BackofficeTheme.inter(12, color: BackofficeTheme.muted),
            ),
            const SizedBox(height: 10),
            Text(
              availableCount == 0
                  ? 'No collector is available right now — you can still pick '
                      'a busy or off-duty one.'
                  : '$availableCount collector${availableCount == 1 ? '' : 's'} '
                      'available now (on duty, fewer than $kBusyIssueCount '
                      'issues in progress).',
              key: const Key('assign_summary'),
              style: BackofficeTheme.inter(11.5, color: BackofficeTheme.muted),
            ),
            const SizedBox(height: 10),
            if (_candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No collector in this agency yet.',
                  textAlign: TextAlign.center,
                  style: BackofficeTheme.inter(12.5, color: BackofficeTheme.muted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final c in _candidates) _tile(c)],
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('issue_assign_confirm'),
              onPressed: _selectedId == null
                  ? null
                  : () => Navigator.of(context).pop(_candidates
                      .firstWhere((c) => c.collecteur.id == _selectedId)
                      .collecteur),
              style: FilledButton.styleFrom(
                backgroundColor: BackofficeTheme.green,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IssueCandidate c) {
    final color = _colors[c.availability]!;
    final selected = _selectedId == c.collecteur.id;
    final isCurrent = c.collecteur.id == widget.issue.assignedCollecteurId;
    final details = [
      if (c.isClientsCollector) "Client's collector",
      if (!c.isClientsCollector && c.coversClient) 'Client inside his zone',
      if (!c.isClientsCollector && !c.coversClient && c.servesZone)
        'Works in this zone',
      if (c.collecteur.zone.isNotEmpty) c.collecteur.zone,
      '${c.openIssues} issue${c.openIssues == 1 ? '' : 's'} in progress',
      if (isCurrent) 'currently assigned',
    ].join(' · ');
    return Opacity(
      opacity: c.canAssign ? 1 : 0.45,
      child: InkWell(
        key: Key('assign_option_${c.collecteur.id}'),
        onTap: c.canAssign
            ? () => setState(() => _selectedId = c.collecteur.id)
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? BackofficeTheme.greenSoft : null,
            border: Border.all(
              color: selected ? BackofficeTheme.green : BackofficeTheme.border,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected ? BackofficeTheme.green : BackofficeTheme.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.collecteur.name,
                      style: BackofficeTheme.inter(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  c.availability.label,
                  style: BackofficeTheme.inter(10.5,
                      weight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.report_off_outlined, size: 34, color: BackofficeTheme.border),
            const SizedBox(height: 10),
            Text(text, style: BackofficeTheme.inter(12.5, color: BackofficeTheme.muted)),
          ],
        ),
      ),
    );
  }
}
