import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../backoffice/models.dart';
import '../backoffice/theme.dart';

/// Issues the agency manager assigned to this collector, not resolved yet
/// (live, newest first).
Stream<List<IssueModel>> watchAssignedIssues(
  FirebaseFirestore db,
  String collectorPhone,
) {
  return db
      .collection('issues')
      .where('assignedCollectorPhone',
          isEqualTo: AuthService.canonicalPhone(collectorPhone))
      .snapshots()
      .map((qs) => qs.docs
          .map((d) => IssueModel.fromMap({...d.data(), 'id': d.id}))
          .where((i) => i.status != 'resolved')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
}

/// Banner on the collector's round: « N issues assigned to you » → list.
/// Hidden when he has none.
class CollectorIssuesBanner extends StatelessWidget {
  const CollectorIssuesBanner({
    super.key,
    required this.db,
    required this.collectorPhone,
    this.notifications,
  });

  final FirebaseFirestore db;
  final String collectorPhone;
  final NotificationService? notifications;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<IssueModel>>(
      stream: watchAssignedIssues(db, collectorPhone),
      builder: (context, snap) {
        final issues = snap.data ?? const <IssueModel>[];
        if (issues.isEmpty) return const SizedBox.shrink();
        final toStart = issues.where((i) => i.status == 'assigned').length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: BackofficeTheme.goldSoft,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: const Key('collector_issues_banner'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CollectorIssuesScreen(
                  db: db,
                  collectorPhone: collectorPhone,
                  notifications: notifications,
                ),
              )),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.report_problem_outlined,
                        color: BackofficeTheme.gold, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${issues.length} issue${issues.length == 1 ? '' : 's'} '
                            'assigned to you',
                            style: BackofficeTheme.sora(12.5,
                                weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            toStart > 0
                                ? '$toStart not started yet — tap to see them'
                                : 'All in progress — tap to see them',
                            style: BackofficeTheme.inter(10.5,
                                color: BackofficeTheme.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: BackofficeTheme.muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The collector's assigned issues: he starts them, then resolves them.
/// The client is notified at each step (server `notify`).
class CollectorIssuesScreen extends StatelessWidget {
  const CollectorIssuesScreen({
    super.key,
    required this.db,
    required this.collectorPhone,
    this.notifications,
  });

  final FirebaseFirestore db;
  final String collectorPhone;
  final NotificationService? notifications;

  Future<void> _move(BuildContext context, IssueModel issue, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await db.collection('issues').doc(issue.id).update({
        'status': status,
        if (status == 'in_progress') 'startedAt': FieldValue.serverTimestamp(),
        if (status == 'resolved') 'resolvedAt': FieldValue.serverTimestamp(),
      });
      messenger.showSnackBar(SnackBar(
        content: Text(status == 'resolved'
            ? 'Issue resolved — the client has been notified'
            : 'Issue started — the client has been notified'),
        backgroundColor: BackofficeTheme.green,
      ));
      await (notifications ?? NotificationService(db: db)).notifyIssueEvent(
        status == 'resolved' ? IssueEvent.resolved : IssueEvent.started,
        issueId: issue.id,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not update the issue: $e'),
        backgroundColor: BackofficeTheme.red,
      ));
    }
  }

  Future<void> _confirmResolve(BuildContext context, IssueModel issue) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as resolved?'),
        content: Text('${issue.category}: ${issue.description}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Resolved'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await _move(context, issue, 'resolved');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BackofficeTheme.bg,
      appBar: AppBar(
        title: Text('My assigned issues',
            style: BackofficeTheme.sora(16, weight: FontWeight.w600)),
        backgroundColor: BackofficeTheme.surface,
        foregroundColor: BackofficeTheme.green,
        elevation: 0,
      ),
      body: StreamBuilder<List<IssueModel>>(
        stream: watchAssignedIssues(db, collectorPhone),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text('Could not load your issues.',
                  style: BackofficeTheme.inter(13, color: BackofficeTheme.muted)),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final issues = snap.data!;
          if (issues.isEmpty) {
            return Center(
              child: Text('No issue assigned to you.',
                  style: BackofficeTheme.inter(13, color: BackofficeTheme.muted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: issues.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _card(context, issues[i]),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, IssueModel issue) {
    final started = issue.status == 'in_progress';
    return Container(
      key: Key('collector_issue_${issue.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BackofficeTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(issue.category,
                    style: BackofficeTheme.inter(13.5, weight: FontWeight.w700)),
              ),
              Text(
                started ? 'In progress' : 'To start',
                style: BackofficeTheme.inter(11,
                    weight: FontWeight.w700,
                    color: started ? BackofficeTheme.gold : BackofficeTheme.red),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${issue.clientName} · ${issue.clientId}',
              style: BackofficeTheme.inter(11.5, color: BackofficeTheme.muted)),
          const SizedBox(height: 8),
          Text(issue.description, style: BackofficeTheme.inter(12.5)),
          if (issue.location.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: BackofficeTheme.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(issue.location,
                      style: BackofficeTheme.inter(11.5,
                          color: BackofficeTheme.muted)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: started
                ? FilledButton.icon(
                    key: Key('issue_resolve_${issue.id}'),
                    onPressed: () => _confirmResolve(context, issue),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Mark resolved'),
                    style: FilledButton.styleFrom(
                        backgroundColor: BackofficeTheme.green),
                  )
                : FilledButton.icon(
                    key: Key('issue_start_${issue.id}'),
                    onPressed: () => _move(context, issue, 'in_progress'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start'),
                    style: FilledButton.styleFrom(
                        backgroundColor: BackofficeTheme.gold),
                  ),
          ),
        ],
      ),
    );
  }
}
