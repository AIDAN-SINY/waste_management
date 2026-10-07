import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/item_card.dart';
import '../widgets/sheets.dart';
import '../widgets/toast.dart';

/// Paramètres: ramassage frequencies (editable) + company info (display).
class BoSettingsPage extends StatelessWidget {
  const BoSettingsPage({
    super.key,
    required this.store,
    this.desktop = false,
    this.agenceId = '',
    this.societeId = '',
  });

  final BackofficeStore store;

  /// Layout desktop (web-first) : padding adapté (pas de tab bar ni FAB).
  final bool desktop;

  /// The manager's agency (applications settings); '' hides that section.
  final String agenceId;
  final String societeId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return ListView(
          padding: EdgeInsets.fromLTRB(
            desktop ? 2 : 16,
            6,
            desktop ? 2 : 16,
            desktop ? 24 : 110,
          ),
          children: [
            if (agenceId.isNotEmpty) ...[
              _title('Client applications'),
              _AutoApprovalCard(agenceId: agenceId, societeId: societeId),
            ],
            _title('Pickup frequencies'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BackofficeTheme.card(),
              child: Column(
                children: [
                  for (var i = 0; i < store.frequences.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: BackofficeTheme.border),
                    _FrequenceRow(
                      frequence: store.frequences[i],
                      onEdit: () => showBoFormSheet(
                        context,
                        store: store,
                        type: BoEntity.frequence,
                        existing: store.frequences[i],
                      ),
                      onDelete: () {
                        store.deleteFrequence(store.frequences[i].id);
                        BoToastService.show('frequency deleted');
                      },
                    ),
                  ],
                ],
              ),
            ),
            _title('Company information'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BackofficeTheme.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoField('Company name', 'WastePro'),
                  const SizedBox(height: 15),
                  _infoField('City of operation', 'Yaoundé'),
                  const SizedBox(height: 15),
                  _infoField('Support number', '+237 696 713 899'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
        child: Text(text, style: BackofficeTheme.sora(14, weight: FontWeight.w700)),
      );

  Widget _infoField(String label, String value) {
    // Read-only display (no controller needed).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: BackofficeTheme.inter(11, weight: FontWeight.w600, color: BackofficeTheme.muted),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: BackofficeTheme.bg,
            border: Border.all(color: BackofficeTheme.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(value, style: BackofficeTheme.inter(14)),
        ),
      ],
    );
  }
}

class _FrequenceRow extends StatelessWidget {
  const _FrequenceRow({
    required this.frequence,
    required this.onEdit,
    required this.onDelete,
  });

  final FrequenceModel frequence;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return BoItemCard(
      avatarText: 'Fq',
      title: frequence.libelle,
      subtitle: 'Every ${frequence.jours} days',
      status: 'Active',
      onKebab: () {
        showBoActionSheet(context, onEdit: onEdit, onDelete: onDelete);
      },
    );
  }
}

/// Agency settings applied by the `autoApproveRegistration` Cloud Function:
/// automatic approval of client applications (ON by default) and the
/// maximum number of clients per collector (empty = no limit).
class _AutoApprovalCard extends StatefulWidget {
  const _AutoApprovalCard({required this.agenceId, required this.societeId});

  final String agenceId;
  final String societeId;

  @override
  State<_AutoApprovalCard> createState() => _AutoApprovalCardState();
}

class _AutoApprovalCardState extends State<_AutoApprovalCard> {
  bool _auto = true;
  final _maxCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore
      .instance
      .collection('agency_settings')
      .doc(widget.agenceId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = (await _doc.get()).data() ?? const {};
      final max = data['maxClientsPerCollector'];
      if (!mounted) return;
      setState(() {
        _auto = data['autoApproval'] != false;
        _maxCtrl.text = max is num && max > 0 ? '${max.toInt()}' : '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({bool? auto}) async {
    final max = int.tryParse(_maxCtrl.text.trim());
    if (_maxCtrl.text.trim().isNotEmpty && (max == null || max <= 0)) {
      BoToastService.show('Enter a positive number, or leave it empty');
      return;
    }
    setState(() {
      if (auto != null) _auto = auto;
      _saving = true;
    });
    try {
      await _doc.set({
        'agenceId': widget.agenceId,
        'societeId': widget.societeId,
        'autoApproval': _auto,
        'maxClientsPerCollector': max,
      }, SetOptions(merge: true));
      BoToastService.show('Settings saved');
    } catch (_) {
      BoToastService.show('Could not save the settings');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BackofficeTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_mode_rounded,
                color: _auto ? BackofficeTheme.green : BackofficeTheme.muted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approve applications automatically',
                      style: BackofficeTheme.inter(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The system approves each new application and assigns '
                      'a collector: the one serving the client\'s zone, else '
                      'the nearest, then the least busy. If none fits, the '
                      'application waits here for your review.',
                      style: BackofficeTheme.inter(
                        11,
                        color: BackofficeTheme.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading || _saving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  key: const Key('auto_approval_switch'),
                  value: _auto,
                  onChanged: (v) => _save(auto: v),
                  activeThumbColor: BackofficeTheme.green,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Maximum clients per collector',
            style: BackofficeTheme.inter(
              11,
              weight: FontWeight.w600,
              color: BackofficeTheme.muted,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('max_clients_field'),
                  controller: _maxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'No limit',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _loading || _saving ? null : () => _save(),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
