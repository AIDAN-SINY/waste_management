import 'package:flutter/material.dart';

import '../../../services/functions_client.dart';
import '../theme.dart';

class ParametresPage extends StatelessWidget {
  const ParametresPage({super.key, this.functions});

  /// Injected in tests (mocked `repairSubscriptions`).
  final FunctionsClient? functions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 880;

        final platformCard = Container(
          padding: const EdgeInsets.all(20),
          decoration: SuperAdminTheme.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Platform',
                style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              _SettingField(label: 'Platform name', value: 'WastePro'),
              const SizedBox(height: 14),
              _SettingField(
                label: 'Support email',
                value: 'support@wastepro.cm',
              ),
              const SizedBox(height: 14),
              _SettingField(
                label: 'Time zone',
                value: 'Africa/Douala (GMT+1)',
              ),
            ],
          ),
        );

        final securityCard = Container(
          padding: const EdgeInsets.all(20),
          decoration: SuperAdminTheme.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Security',
                style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const _SecurityItem(
                color: SuperAdminTheme.gold,
                title: 'Action logging',
                subtitle: 'Enabled — 12-month retention',
              ),
            ],
          ),
        );

        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            ...wide
                ? [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: platformCard),
                        const SizedBox(width: 16),
                        Expanded(child: securityCard),
                      ],
                    ),
                  ]
                : [
                    platformCard,
                    const SizedBox(height: 16),
                    securityCard,
                  ],
            const SizedBox(height: 16),
            _RepairSubscriptionsCard(functions: functions),
          ],
        );
      },
    );
  }
}

/// One-off repair of client subscriptions written by the old app code
/// (`repairSubscriptions` Cloud Function): preview first, then apply.
class _RepairSubscriptionsCard extends StatefulWidget {
  const _RepairSubscriptionsCard({this.functions});

  final FunctionsClient? functions;

  @override
  State<_RepairSubscriptionsCard> createState() =>
      _RepairSubscriptionsCardState();
}

class _RepairSubscriptionsCardState extends State<_RepairSubscriptionsCard> {
  bool _busy = false;
  bool _previewed = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _run({required bool apply}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await (widget.functions ?? FunctionsClient())
          .post('repairSubscriptions', {'apply': apply});
      setState(() {
        _result = data;
        _previewed = !apply;
      });
    } on FunctionsException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final changes = (result?['changes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Maintenance — client subscriptions',
            style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Repairs accounts written by the previous app version: plan '
            'names (Monthly / Weekly / Daily), missing collection days, '
            'subscription end dates. Subscriptions granted without payment '
            'get a 30-day grace period, then must be paid.',
            style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('repair_preview'),
                onPressed: _busy ? null : () => _run(apply: false),
                child: const Text('Preview'),
              ),
              ElevatedButton(
                key: const Key('repair_apply'),
                onPressed: _busy || !_previewed ? null : () => _run(apply: true),
                child: const Text('Apply repair'),
              ),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: SuperAdminTheme.inter(12, color: Colors.red)),
          ],
          if (result != null) ...[
            const SizedBox(height: 12),
            Text(
              result['applied'] == true
                  ? 'Done: ${result['changed']} of ${result['scanned']} '
                      'client accounts repaired.'
                  : '${result['changed']} of ${result['scanned']} client '
                      'accounts would be repaired:',
              style: SuperAdminTheme.inter(12.5, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final c in changes.take(50))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${c['name'] ?? ''} (${c['phone']}): '
                  '${(c['actions'] as List<dynamic>? ?? const []).join(' · ')}',
                  style: SuperAdminTheme.inter(11.5),
                ),
              ),
            if (changes.length > 50)
              Text(
                '… and ${changes.length - 50} more',
                style: SuperAdminTheme.inter(11, color: SuperAdminTheme.muted),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingField extends StatelessWidget {
  const _SettingField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: SuperAdminTheme.inter(
            11.5,
            weight: FontWeight.w600,
            color: SuperAdminTheme.muted,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: SuperAdminTheme.bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: SuperAdminTheme.border),
          ),
          child: Text(
            value,
            style: SuperAdminTheme.inter(13),
          ),
        ),
      ],
    );
  }
}

class _SecurityItem extends StatelessWidget {
  const _SecurityItem({
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SuperAdminTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SuperAdminTheme.inter(12.5, weight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: SuperAdminTheme.inter(11, color: SuperAdminTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
