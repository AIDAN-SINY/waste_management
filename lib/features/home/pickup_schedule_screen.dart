import 'package:flutter/material.dart';

import '../backoffice/data/backoffice_store.dart';
import '../backoffice/models.dart';
import '../backoffice/theme.dart';

/// Weekly pickup schedule of the agency — rendered inside the backoffice
/// shell (no Scaffold/AppBar of its own).
///
/// Groups the agency's contracts by collection day (Monday → Sunday), each
/// row showing the client, plan, pickup time window and contract status.
/// Contracts without collection days fall back to their `frequence` label.
class PickupScheduleScreen extends StatelessWidget {
  const PickupScheduleScreen({super.key, required this.store});

  /// Agency backoffice store — source of the contracts.
  final BackofficeStore store;

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final contracts = store.contrats;
    if (contracts.isEmpty) {
      return _emptyState();
    }

    final unscheduled =
        contracts.where((c) => c.collectionDays.isEmpty).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final day in _weekdays) ..._daySection(day, contracts),
        // Contrats sans jours de collecte (legacy / non renseignés) :
        // on les affiche quand même, avec leur fréquence en repère.
        if (unscheduled.isNotEmpty) ..._unscheduledSection(unscheduled),
      ],
    );
  }

  List<Widget> _unscheduledSection(List<ContratModel> contracts) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(
          children: [
            Text(
              'Unscheduled',
              style: BackofficeTheme.sora(13, weight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: BackofficeTheme.graySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${contracts.length}',
                style: BackofficeTheme.inter(
                  10.5,
                  weight: FontWeight.w700,
                  color: BackofficeTheme.muted,
                ),
              ),
            ),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: BackofficeTheme.surface,
          border: Border.all(color: BackofficeTheme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < contracts.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, color: BackofficeTheme.border),
              _clientRow(contracts[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: BackofficeTheme.greenSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.calendar_month_outlined,
              size: 26,
              color: BackofficeTheme.green,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No scheduled pickups yet',
            style: BackofficeTheme.sora(14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Contracts with collection days will appear here.',
            style: BackofficeTheme.inter(12, color: BackofficeTheme.muted),
          ),
        ],
      ),
    );
  }

  List<Widget> _daySection(String day, List<ContratModel> contracts) {
    final onDay = contracts.where((c) => c.collectionDays.contains(day)).toList();
    if (onDay.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(
          children: [
            Text(
              day,
              style: BackofficeTheme.sora(13, weight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: BackofficeTheme.greenSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${onDay.length}',
                style: BackofficeTheme.inter(
                  10.5,
                  weight: FontWeight.w700,
                  color: BackofficeTheme.green,
                ),
              ),
            ),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: BackofficeTheme.surface,
          border: Border.all(color: BackofficeTheme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < onDay.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, color: BackofficeTheme.border),
              _clientRow(onDay[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _clientRow(ContratModel contract) {
    // Sans fenêtre horaire renseignée, on affiche un tiret : la fréquence
    // est déjà en sous-titre, l'afficher ici débordait sur mobile.
    final time = contract.pickupTime.isNotEmpty ? contract.pickupTime : '—';
    final active = contract.status.toLowerCase() == 'active';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active ? BackofficeTheme.greenSoft : BackofficeTheme.graySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: 17,
              color: active ? BackofficeTheme.green : BackofficeTheme.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contract.client,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(13, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  contract.frequence,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: BackofficeTheme.muted,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(12, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          _statusPill(contract.status),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final active = status.toLowerCase() == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? BackofficeTheme.greenSoft
            : BackofficeTheme.redSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: BackofficeTheme.inter(
          9.5,
          weight: FontWeight.w700,
          color: active ? BackofficeTheme.green : BackofficeTheme.red,
        ),
      ),
    );
  }
}