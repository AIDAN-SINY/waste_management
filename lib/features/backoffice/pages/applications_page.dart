import 'package:flutter/material.dart';

import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/badge.dart';
import '../widgets/chips.dart';
import '../widgets/sheets.dart';

/// Page « Applications » : les candidatures clients (pré-inscriptions) que
/// le chef d'agence doit approuver (en assignant un collecteur) ou rejeter.
class BoApplicationsPage extends StatefulWidget {
  const BoApplicationsPage({
    super.key,
    required this.store,
    this.desktop = false,
    this.search = '',
  });

  final BackofficeStore store;

  /// Layout desktop (web-first) : padding adapté (pas de tab bar ni FAB).
  final bool desktop;

  /// Recherche live venue de la topbar (nom, zone, agence, téléphone).
  final String search;

  @override
  State<BoApplicationsPage> createState() => _BoApplicationsPageState();
}

class _BoApplicationsPageState extends State<BoApplicationsPage> {
  String _filter = 'All';

  static const _labels = <String, String>{
    'pending': 'Pending',
    'approved': 'Approved',
    'rejected': 'Rejected',
  };

  List<RegistrationModel> get _items {
    final all = widget.store.registrations;
    final q = widget.search.toLowerCase().trim();
    bool match(RegistrationModel r) {
      if (q.isEmpty) return true;
      return r.fullName.toLowerCase().contains(q) ||
          r.zone.toLowerCase().contains(q) ||
          r.agenceName.toLowerCase().contains(q) ||
          r.phone.toLowerCase().contains(q);
    }

    if (_filter == 'All') return all.where(match).toList();
    return all
        .where((r) => r.status == _filter.toLowerCase() && match(r))
        .toList();
  }

  void _review(RegistrationModel reg) {
    showBoReviewSheet(context, store: widget.store, reg: reg);
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
              options: const ['All', 'Pending', 'Approved', 'Rejected'],
              selected: _filter,
              onSelect: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? _EmptyState(text: 'No applications found')
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        widget.desktop ? 2 : 16,
                        0,
                        widget.desktop ? 2 : 16,
                        widget.desktop ? 24 : 110,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, i) =>
                          _card(context, items[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, RegistrationModel reg) {
    final pending = reg.status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BackofficeTheme.card(),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: BackofficeTheme.greenSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              boInitials(reg.fullName),
              style: BackofficeTheme.inter(
                12.5,
                weight: FontWeight.w700,
                color: BackofficeTheme.green,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reg.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    13,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${reg.zone} · ${reg.agenceName} · ${boFmtDate(reg.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    11,
                    color: BackofficeTheme.muted,
                  ),
                ),
                // Automatic approval: why the system left it to the
                // manager, or that the collector was chosen automatically.
                if (pending && reg.autoStatus == 'manual')
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Needs your review: ${reg.autoReason}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(
                        11,
                        weight: FontWeight.w600,
                        color: const Color(0xFFB7791F),
                      ),
                    ),
                  )
                else if (reg.status == 'approved' &&
                    reg.autoStatus == 'approved')
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      switch (reg.autoReason) {
                        'zone_area' =>
                          'Approved automatically · inside the collector\'s zone',
                        'zone' =>
                          'Approved automatically · collector of the zone',
                        _ => 'Approved automatically · nearest collector',
                      },
                      style: BackofficeTheme.inter(
                        11,
                        color: BackofficeTheme.green,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (pending)
            Material(
              color: BackofficeTheme.green,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                onTap: () => _review(reg),
                borderRadius: BorderRadius.circular(9),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    'Review',
                    style: BackofficeTheme.inter(
                      11.5,
                      weight: FontWeight.w600,
                      color: BackofficeTheme.cream,
                    ),
                  ),
                ),
              ),
            )
          else
            BoBadge(status: _labels[reg.status] ?? reg.status),
        ],
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
            Icon(
              Icons.how_to_reg_rounded,
              size: 34,
              color: BackofficeTheme.border,
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: BackofficeTheme.inter(
                12.5,
                color: BackofficeTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
