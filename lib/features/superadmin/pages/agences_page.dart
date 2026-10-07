import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/agence_model.dart';
import '../data/platform_store.dart';
import '../widgets/app_table.dart';
import '../widgets/app_toast.dart';
import '../widgets/cells.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/crud_drawer.dart';
import '../widgets/filter_pills.dart';
import '../widgets/form_fields.dart';
import '../widgets/form_validation.dart';
import '../widgets/page_toolbar.dart';
import '../widgets/primary_button.dart';
import '../widgets/sa_search_field.dart';
import '../widgets/status_badge.dart';

class AgencesPage extends StatefulWidget {
  const AgencesPage({super.key});

  @override
  State<AgencesPage> createState() => AgencesPageState();
}

class AgencesPageState extends State<AgencesPage> {
  static const List<String> _filters = ['All', 'Active', 'Suspended'];

  int _filter = 0;
  final Map<String, dynamic> _form = {};

  /// Recherche live sur la page courante (ville, société, responsable).
  final _searchCtrl = TextEditingController();
  String _search = '';

  List<String> get _societeOptions =>
      context.read<PlatformStore>().societes.map((s) => s.raisonSociale).toList();

  /// Id de la société correspondant à un nom (raisonSociale), ou '' si
  /// introuvable — pour lier l'agence à sa société (Phase 2).
  String _societeIdFor(String nom) {
    for (final s in context.read<PlatformStore>().societes) {
      if (s.raisonSociale == nom) return s.id;
    }
    return '';
  }

  /// Opens the "New agency" drawer (used by the command palette).
  void openCreate() {
    final options = _societeOptions;
    // An agency must belong to an existing company.
    if (options.isEmpty) {
      ToastService.show(
        'Create a company first before adding an agency.',
        isError: true,
      );
      return;
    }
    _form
      ..clear()
      ..['status'] = 'Active'
      ..['societe'] = options.first;
    showCrudDrawer(
      context,
      title: 'New agency',
      body: _buildForm(options),
      onSave: () async {
        try {
          final ville = requireField(_form, 'ville', 'City');
          final societe = _form['societe']?.toString() ?? '';
          await context.read<PlatformStore>().addAgence(
                societe: societe,
                societeId: _societeIdFor(societe),
                ville: ville,
                responsable: _form['responsable']?.toString().trim() ?? '',
                telephone: _form['telephone']?.toString().trim() ?? '',
                status: _form['status']?.toString() ?? 'Active',
              );
          ToastService.show('Agency created successfully.');
        } catch (e) {
          ToastService.show(e.toString(), isError: true);
          rethrow;
        }
      },
    );
  }

  void openEdit(AgenceModel agence) {
    _form
      ..clear()
      ..addAll(agence.toMap());
    showCrudDrawer(
      context,
      title: 'Edit agency',
      body: _buildForm(_societeOptions),
      onSave: () async {
        try {
          final ville = requireField(_form, 'ville', 'City');
          final societe = _form['societe']?.toString();
          await context.read<PlatformStore>().updateAgence(
                agence.copyWith(
                  societe: societe,
                  societeId:
                      societe == null ? null : _societeIdFor(societe),
                  ville: ville,
                  responsable: _form['responsable']?.toString().trim(),
                  telephone: _form['telephone']?.toString().trim(),
                  status: _form['status']?.toString(),
                ),
              );
          ToastService.show('Changes saved.');
        } catch (e) {
          ToastService.show(e.toString(), isError: true);
          rethrow;
        }
      },
    );
  }

  Future<void> confirmDelete(AgenceModel agence) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this agency?',
      message:
          '"${agence.ville}" will be permanently deleted. This action is irreversible.',
    );
    if (confirmed == true && mounted) {
      try {
        await context.read<PlatformStore>().deleteAgence(agence.id);
        if (mounted) ToastService.show('Item deleted.');
      } catch (e) {
        if (mounted) ToastService.show(e.toString(), isError: true);
      }
    }
  }

  Widget _buildForm(List<String> societeOptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SaSelectField(
          label: 'Company',
          options: societeOptions,
          initial: _form['societe']?.toString(),
          onChanged: (v) => _form['societe'] = v,
        ),
        const SizedBox(height: 16),
        SaTextField(
          label: 'City',
          initial: _form['ville']?.toString(),
          hint: 'Ex. Yaoundé — Bastos',
          onChanged: (v) => _form['ville'] = v,
        ),
        const SizedBox(height: 16),
        SaTextField(
          label: 'Manager',
          initial: _form['responsable']?.toString(),
          hint: 'Manager name',
          onChanged: (v) => _form['responsable'] = v,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SaTextField(
                label: 'Phone',
                initial: _form['telephone']?.toString(),
                hint: '+237 6XX XX XX XX',
                keyboardType: TextInputType.phone,
                onChanged: (v) => _form['telephone'] = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SaSelectField(
                label: 'Status',
                options: const ['Active', 'Suspended'],
                initial: _form['status']?.toString() ?? 'Active',
                onChanged: (v) => _form['status'] = v,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlatformStore>();
    final statusFilter =
        _filter == 1 ? 'Active' : (_filter == 2 ? 'Suspended' : null);
    // Match both the English values and the legacy French ones ('Actif' /
    // 'Suspendu') so records created before the switch stay visible.
    final rows = store.agences.where((a) {
      final statusOk = statusFilter == null
          ? true
          : (statusFilter == 'Active'
              ? (a.status == 'Active' || a.status == 'Actif')
              : (a.status == 'Suspended' || a.status == 'Suspendu'));
      if (!statusOk) return false;
      if (_search.isEmpty) return true;
      return a.ville.toLowerCase().contains(_search) ||
          a.societe.toLowerCase().contains(_search) ||
          a.responsable.toLowerCase().contains(_search) ||
          a.telephone.toLowerCase().contains(_search);
    }).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        PageToolbar(
          filters: FilterPills(
            labels: _filters,
            activeIndex: _filter,
            onChanged: (i) => setState(() => _filter = i),
          ),
          action: PrimaryButton(
            label: 'New agency',
            icon: Icons.add_rounded,
            onTap: openCreate,
          ),
        ),
        const SizedBox(height: 12),
        SaSearchField(
          key: const Key('sa_search_agences'),
          controller: _searchCtrl,
          hint: 'Search agencies...',
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 16),
        AppTable<AgenceModel>(
          rows: rows,
          emptyText: 'No agencies found',
          footer: '${rows.length} agenc${rows.length > 1 ? 'ies' : 'y'}',
          columns: [
            TableColumnSpec(
              label: 'Agency',
              sortValue: (a) => a.ville,
              flex: 2,
              cell: (a) => saNameCell(a.ville),
            ),
            TableColumnSpec(
              label: 'Company',
              sortValue: (a) => a.societe,
              flex: 2,
              cell: (a) => saTextCell(a.societe),
            ),
            TableColumnSpec(
              label: 'Manager',
              sortValue: (a) => a.responsable,
              flex: 2,
              cell: (a) => saTextCell(a.responsable),
            ),
            TableColumnSpec(
              label: 'Status',
              sortValue: (a) => a.status,
              flex: 1,
              cell: (a) => StatusBadge(status: a.status),
            ),
          ],
          actions: (a) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RowActionButton(
                icon: Icons.edit_rounded,
                onTap: () => openEdit(a),
              ),
              RowActionButton(
                icon: Icons.delete_outline_rounded,
                onTap: () => confirmDelete(a),
                danger: true,
              ),
            ],
          ),
          onRowTap: openEdit,
        ),
      ],
    );
  }
}
