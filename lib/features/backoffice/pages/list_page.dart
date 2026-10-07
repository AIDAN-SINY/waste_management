import 'package:flutter/material.dart';

import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/item_card.dart';
import '../widgets/sheets.dart';
import '../widgets/toast.dart';
import 'vehicle_maintenance_page.dart';

/// Generic list page for the backoffice (clients, collecteurs, contrats,
/// collectes, factures) with filter chips, search and item CRUD.
class BoListPage extends StatelessWidget {
  const BoListPage({
    super.key,
    required this.store,
    required this.type,
    required this.search,
    this.desktop = false,
  });

  final BackofficeStore store;
  final BoEntity type;
  final String search;

  /// Layout desktop (web-first) : padding adapté (pas de tab bar ni FAB).
  final bool desktop;

  String get _entityName => switch (type) {
        BoEntity.client => 'client',
        BoEntity.collecteur => 'collector',
        BoEntity.contrat => 'contract',
        BoEntity.collecte => 'collection',
        BoEntity.facture => 'invoice',
        BoEntity.frequence => 'frequency',
        BoEntity.issue => 'issue',
        BoEntity.zone => 'zone',
        BoEntity.assignment => 'assignment',
        BoEntity.vehicle => 'vehicle',
      };

  String get _emptyText => switch (type) {
        BoEntity.client => 'No clients found',
        BoEntity.collecteur => 'No collectors found',
        BoEntity.contrat => 'No contracts found',
        BoEntity.collecte => 'No collections found',
        BoEntity.facture => 'No invoices found',
        BoEntity.frequence => 'No frequencies',
        BoEntity.issue => 'No issues found',
        BoEntity.zone => 'No zones found',
        BoEntity.assignment => 'No assignments found',
        BoEntity.vehicle => 'No vehicles found',
      };

  /// (label shown, status value used for filtering) per the design.
  List<(String, String)> get _filters => switch (type) {
        BoEntity.client => [
            ('All', 'All'),
            ('Active', 'Active'),
            ('Suspended', 'Suspended'),
          ],
        BoEntity.collecteur => [
            ('All', 'All'),
            ('Active', 'Active'),
            ('Inactive', 'Inactive'),
          ],
        BoEntity.contrat => [
            ('All', 'All'),
            ('Active', 'Active'),
            ('Expired', 'Expired'),
          ],
        BoEntity.collecte => [
            ('All', 'All'),
            ('Completed', 'Completed'),
            ('Scheduled', 'Scheduled'),
            ('Missed', 'Missed'),
          ],
        BoEntity.facture => [
            ('All', 'All'),
            ('Paid', 'Paid'),
            ('Pending', 'Pending'),
            ('Overdue', 'Overdue'),
          ],
        BoEntity.frequence => [('All', 'All')],
        BoEntity.issue => [('All', 'All')],
        BoEntity.zone => [('All', 'All')],
        BoEntity.assignment => [('All', 'All')],
        BoEntity.vehicle => [
            ('All', 'All'),
            ('Active', 'Active'),
            ('Maintenance', 'Maintenance'),
            ('Retired', 'Retired'),
          ],
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = _buildList();
        final selValue = store.filterFor(type);
        final selLabel = _filters
            .firstWhere((f) => f.$2 == selValue, orElse: () => _filters.first)
            .$1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            BoChipRow(
              options: _filters.map((f) => f.$1).toList(),
              selected: selLabel,
              onSelect: (label) {
                final value =
                    _filters.firstWhere((f) => f.$1 == label).$2;
                store.selectFilter(type, value);
              },
            ),
            // Zone filter dropdown (shown only for clients & collectors).
            if (type == BoEntity.client || type == BoEntity.collecteur) ...[
              const SizedBox(height: 8),
              _ZoneDropdown(store: store),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? _EmptyState(text: _emptyText)
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 2 : 16,
                        0,
                        desktop ? 2 : 16,
                        desktop ? 24 : 110,
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

  /// Matches a status filter against both the English values and the legacy
  /// French ones (e.g. 'Active' also matches 'Actif') so records created
  /// before the switch to English stay visible when filtering.
  bool _statusMatches(String filter, String status) {
    if (filter == 'All') return true;
    const legacy = {
      'Active': {'Actif'},
      'Suspended': {'Suspendu'},
      'Inactive': {'Inactif'},
      'Completed': {'Effectué'},
      'Scheduled': {'Prévu'},
      'Missed': {'Manqué'},
      'Paid': {'Payée'},
      'Pending': {'En attente'},
      'Overdue': {'En retard'},
      'Expired': {'Expiré'},
    };
    return status == filter || (legacy[filter]?.contains(status) ?? false);
  }

  List<Object> _buildList() {
    final q = search.toLowerCase();
    bool match(String value) => q.isEmpty || value.toLowerCase().contains(q);
    final sel = store.filterFor(type);

    switch (type) {
      case BoEntity.client:
        final zoneSel = store.zoneFilter;
        return store.clients
            .where((c) =>
                _statusMatches(sel, c.status) &&
                (zoneSel == 'All' || c.zone == zoneSel) &&
                (match(c.name) || match(c.zone)))
            .toList()
            .cast<Object>();
      case BoEntity.collecteur:
        final zoneSel = store.zoneFilter;
        return store.collecteurs
            .where((c) =>
                _statusMatches(sel, c.status) &&
                (zoneSel == 'All' || c.zone == zoneSel) &&
                (match(c.name) || match(c.zone)))
            .toList()
            .cast<Object>();
      case BoEntity.contrat:
        return store.contrats
            .where((c) => _statusMatches(sel, c.status) && match(c.client))
            .toList()
            .cast<Object>();
      case BoEntity.collecte:
        final sorted = [...store.collectes]..sort((a, b) => b.date.compareTo(a.date));
        return sorted
            .where((c) => _statusMatches(sel, c.status) && match(c.client))
            .toList()
            .cast<Object>();
      case BoEntity.facture:
        return store.factures
            .where((f) => _statusMatches(sel, f.status) && match(f.client))
            .toList()
            .cast<Object>();
      case BoEntity.frequence:
        return store.frequences.toList().cast<Object>();
      case BoEntity.issue:
        return store.issues.toList().cast<Object>();
      case BoEntity.zone:
        return store.zones.toList().cast<Object>();
      case BoEntity.assignment:
        return store.assignments.toList().cast<Object>();
      case BoEntity.vehicle:
        return store.vehicles
            .where((v) => _statusMatches(sel, v.status) && (match(v.plateNumber) || match(v.type) || match(v.brand)))
            .toList()
            .cast<Object>();
    }
  }

  Widget _card(BuildContext context, Object item) {
    switch (type) {
      case BoEntity.client:
        final c = item as ClientModel;
        final collector = collecteurNameFor(store.collecteurs, c.collecteurId);
        return BoItemCard(
          avatarText: boInitials(c.name),
          title: c.name,
          subtitle:
              '${c.zone} · ${c.plan}${collector.isEmpty ? '' : ' · $collector'}',
          status: c.status,
          onKebab: () => _onKebab(context, c),
        );
      case BoEntity.collecteur:
        final c = item as CollecteurModel;
        return BoItemCard(
          avatarText: boInitials(c.name),
          title: c.name,
          subtitle: c.rating > 0
              ? '${c.zone} · rating ${c.rating.toStringAsFixed(1)}'
              : c.zone,
          status: c.status,
          onKebab: () => _onKebab(context, c),
        );
      case BoEntity.contrat:
        final c = item as ContratModel;
        return BoItemCard(
          avatarText: boInitials(c.client),
          title: c.client,
          subtitle: '${c.frequence} · ${boMoney(c.prix)} XAF',
          status: c.status,
          onKebab: () => _onKebab(context, c),
        );
      case BoEntity.collecte:
        final c = item as CollecteModel;
        return BoItemCard(
          avatarText: boInitials(c.client),
          title: c.client,
          subtitle:
              '${c.collecteur} · ${boFmtDate(c.date)}${c.poids > 0 ? ' · ${c.poids}kg' : ''}',
          status: c.status,
          onKebab: () => _onKebab(context, c),
        );
      case BoEntity.facture:
        final c = item as FactureModel;
        return BoItemCard(
          avatarText: boInitials(c.client),
          title: c.client,
          subtitle: '${boMoney(c.montant)} XAF · due ${boFmtDate(c.echeance)}',
          status: c.status,
          onKebab: () => _onKebab(context, c),
        );
      case BoEntity.frequence:
        return BoItemCard(
          avatarText: 'Fq',
          title: (item as FrequenceModel).libelle,
          subtitle: 'Every ${item.jours} days',
          status: 'Active',
          onKebab: () => _onKebab(context, item),
        );
      case BoEntity.issue:
        return const SizedBox.shrink(); // Issues have their own page
      case BoEntity.zone:
        return const SizedBox.shrink(); // Zones have their own page
      case BoEntity.assignment:
        return const SizedBox.shrink(); // Assignments have their own page
      case BoEntity.vehicle:
        final v = item as VehicleModel;
        return BoItemCard(
          avatarText: v.plateNumber.length > 4 ? v.plateNumber.substring(0, 4) : v.plateNumber,
          title: '${v.type} — ${v.plateNumber}',
          subtitle: '${v.brand} ${v.model} · ${v.year > 0 ? v.year : 'N/A'}${v.assignedCollecteurName.isNotEmpty ? ' · ${v.assignedCollecteurName}' : ''}',
          status: v.status,
          onKebab: () => _onKebab(context, v),
        );
    }
  }

  void _onKebab(BuildContext context, Object item) {
    // Les clients ont une action dédiée : réassigner leur collecteur.
    // Les véhicules ont une action dédiée : maintenance.
    final isClient = type == BoEntity.client;
    final isVehicle = type == BoEntity.vehicle;
    showBoActionSheet(
      context,
      onEdit: () =>
          showBoFormSheet(context, store: store, type: type, existing: item),
      onDelete: () => _delete(context, item),
      extraLabel: isClient ? 'Reassign collector' : (isVehicle ? 'Maintenance' : null),
      onExtra: isClient
          ? () => showBoReassignSheet(
                context,
                store: store,
                client: item as ClientModel,
              )
          : isVehicle
              ? () => _openMaintenance(context, item as VehicleModel)
              : null,
    );
  }

  void _openMaintenance(BuildContext context, VehicleModel vehicle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleMaintenancePage(store: store, vehicle: vehicle),
      ),
    );
  }

  void _delete(BuildContext context, Object item) {
    switch (type) {
      case BoEntity.client:
        store.deleteClient((item as ClientModel).id);
      case BoEntity.collecteur:
        store.deleteCollecteur((item as CollecteurModel).id);
      case BoEntity.contrat:
        store.deleteContrat((item as ContratModel).id);
      case BoEntity.collecte:
        store.deleteCollecte((item as CollecteModel).id);
      case BoEntity.facture:
        store.deleteFacture((item as FactureModel).id);
      case BoEntity.frequence:
        store.deleteFrequence((item as FrequenceModel).id);
      case BoEntity.issue:
        break; // Issues are resolved, not deleted
      case BoEntity.zone:
        break; // Zones are managed via their own page
      case BoEntity.assignment:
        break; // Assignments are managed via their own page
      case BoEntity.vehicle:
        store.deleteVehicle((item as VehicleModel).id);
    }
    BoToastService.show('$_entityName deleted');
  }
}

class _ZoneDropdown extends StatelessWidget {
  const _ZoneDropdown({required this.store});
  final BackofficeStore store;

  @override
  Widget build(BuildContext context) {
    final zones = store.availableZones;
    final current = store.zoneFilter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: BackofficeTheme.surface,
          border: Border.all(color: BackofficeTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.map_outlined, size: 16, color: BackofficeTheme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: current,
                  isDense: true,
                  style: BackofficeTheme.inter(12.5),
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: BackofficeTheme.muted,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text('All zones'),
                    ),
                    ...zones.map((z) => DropdownMenuItem(
                          value: z,
                          child: Text(z),
                        )),
                  ],
                  onChanged: (v) {
                    if (v != null) store.selectZoneFilter(v);
                  },
                ),
              ),
            ),
          ],
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
            Icon(Icons.search_off_rounded, size: 34, color: BackofficeTheme.border),
            const SizedBox(height: 10),
            Text(
              text,
              style: BackofficeTheme.inter(12.5, color: BackofficeTheme.muted),
            ),
          ],
        ),
      ),
    );
  }
}
