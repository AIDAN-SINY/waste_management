import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/societe_model.dart';
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
import 'societe_detail_page.dart';

class SocietesPage extends StatefulWidget {
  const SocietesPage({super.key});

  @override
  State<SocietesPage> createState() => SocietesPageState();
}

class SocietesPageState extends State<SocietesPage> {
  static const List<String> _filters = ['All', 'Active', 'Suspended'];

  int _filter = 0;
  final Map<String, dynamic> _form = {};

  /// Recherche live sur la page courante (nom, adresse, téléphone).
  final _searchCtrl = TextEditingController();
  String _search = '';

  /// Id de la société affichée dans la fiche détail (pleine page). Null =
  /// on est sur la liste.
  String? _detailSocieteId;

  /// Opens the "New company" drawer (used by the command palette).
  void openCreate() {
    _form
      ..clear()
      ..['status'] = 'Active';
    showCrudDrawer(
      context,
      title: 'New company',
      body: _buildForm(),
      onSave: () async {
        try {
          final raisonSociale =
              requireField(_form, 'raisonSociale', 'Company name');
          await context.read<PlatformStore>().addSociete(
                raisonSociale: raisonSociale,
                adresse: _form['adresse']?.toString().trim() ?? '',
                telephone: _form['telephone']?.toString().trim() ?? '',
                email: _form['email']?.toString().trim() ?? '',
                status: _form['status']?.toString() ?? 'Active',
              );
          ToastService.show('Company created successfully.');
        } catch (e) {
          ToastService.show(e.toString(), isError: true);
          rethrow;
        }
      },
    );
  }

  void openEdit(SocieteModel societe) {
    _form
      ..clear()
      ..addAll(societe.toMap());
    showCrudDrawer(
      context,
      title: 'Edit company',
      body: _buildForm(),
      onSave: () async {
        try {
          final raisonSociale =
              requireField(_form, 'raisonSociale', 'Company name');
          await context.read<PlatformStore>().updateSociete(
                societe.copyWith(
                  raisonSociale: raisonSociale,
                  adresse: _form['adresse']?.toString().trim(),
                  telephone: _form['telephone']?.toString().trim(),
                  email: _form['email']?.toString().trim(),
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

  /// Ouvre la fiche détail d'une société — page pleine grandeur (le super
  /// admin voit tout : KPIs, graphiques, agences, managers, clients,
  /// collecteurs de la compagnie).
  void openDetail(SocieteModel societe) {
    setState(() => _detailSocieteId = societe.id);
  }

  /// Revient de la fiche détail à la liste des sociétés.
  void _closeDetail() {
    setState(() => _detailSocieteId = null);
  }

  Future<void> confirmDelete(SocieteModel societe) async {
    // A société with attached agences cannot be deleted: this would leave
    // orphan agences referencing a company that no longer exists.
    final agences = context
        .read<PlatformStore>()
        .agences
        .where((a) => a.societe == societe.raisonSociale)
        .toList();
    if (agences.isNotEmpty) {
      ToastService.show(
        'Cannot delete: ${agences.length} agenc'
        '${agences.length > 1 ? 'ies' : 'y'} linked'
        '${agences.length > 1 ? '' : ''} to this company.',
        isError: true,
      );
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this company?',
      message:
          '"${societe.raisonSociale}" will be permanently deleted. This action is irreversible.',
    );
    if (confirmed == true && mounted) {
      try {
        await context.read<PlatformStore>().deleteSociete(societe.id);
        // Supprimée depuis la fiche détail → retour à la liste.
        if (mounted && _detailSocieteId == societe.id) _closeDetail();
        if (mounted) ToastService.show('Item deleted.');
      } catch (e) {
        if (mounted) ToastService.show(e.toString(), isError: true);
      }
    }
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SaTextField(
          label: 'Company name',
          initial: _form['raisonSociale']?.toString(),
          hint: 'Ex. WastePro Yaoundé SARL',
          onChanged: (v) => _form['raisonSociale'] = v,
        ),
        const SizedBox(height: 16),
        SaTextField(
          label: 'Address',
          initial: _form['adresse']?.toString(),
          hint: 'Ex. Bastos, Yaoundé',
          onChanged: (v) => _form['adresse'] = v,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SaTextField(
                label: 'Phone',
                initial: _form['telephone']?.toString(),
                hint: '+237 2XX XX XX XX',
                keyboardType: TextInputType.phone,
                onChanged: (v) => _form['telephone'] = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SaTextField(
                label: 'Email',
                initial: _form['email']?.toString(),
                hint: 'contact@company.cm',
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => _form['email'] = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SaSelectField(
          label: 'Status',
          options: const ['Active', 'Suspended'],
          initial: _form['status']?.toString() ?? 'Active',
          onChanged: (v) => _form['status'] = v,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlatformStore>();

    // Fiche détail pleine page : on remplace la liste tant qu'une société
    // est sélectionnée. La société est re-résolue à chaque build depuis le
    // store (elle peut avoir été éditée/supprimée entre-temps).
    if (_detailSocieteId != null) {
      SocieteModel? societe;
      for (final s in store.societes) {
        if (s.id == _detailSocieteId) {
          societe = s;
          break;
        }
      }
      // Supprimée depuis la fiche → retour à la liste.
      if (societe != null) {
        return SocieteDetailPage(
          societeId: societe.id,
          onBack: _closeDetail,
          onEdit: openEdit,
          onDelete: (s) => confirmDelete(s),
        );
      }
    }

    final statusFilter =
        _filter == 1 ? 'Active' : (_filter == 2 ? 'Suspended' : null);
    // Match both the English values and the legacy French ones ('Actif' /
    // 'Suspendu') so records created before the switch stay visible.
    final rows = store.societes.where((s) {
      final statusOk = statusFilter == null
          ? true
          : (statusFilter == 'Active'
              ? (s.status == 'Active' || s.status == 'Actif')
              : (s.status == 'Suspended' || s.status == 'Suspendu'));
      if (!statusOk) return false;
      if (_search.isEmpty) return true;
      return s.raisonSociale.toLowerCase().contains(_search) ||
          s.adresse.toLowerCase().contains(_search) ||
          s.telephone.toLowerCase().contains(_search) ||
          s.email.toLowerCase().contains(_search);
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
            label: 'New company',
            icon: Icons.add_rounded,
            onTap: openCreate,
          ),
        ),
        const SizedBox(height: 12),
        SaSearchField(
          key: const Key('sa_search_societes'),
          controller: _searchCtrl,
          hint: 'Search companies...',
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 16),
        AppTable<SocieteModel>(
          rows: rows,
          emptyText: 'No companies found',
          footer: '${rows.length} compan${rows.length > 1 ? 'ies' : 'y'}',
          columns: [
            TableColumnSpec(
              label: 'Company',
              sortValue: (s) => s.raisonSociale,
              flex: 3,
              cell: (s) => saNameCell(s.raisonSociale),
            ),
            TableColumnSpec(
              label: 'Address',
              sortValue: (s) => s.adresse,
              flex: 2,
              cell: (s) => saTextCell(s.adresse),
            ),
            TableColumnSpec(
              label: 'Phone',
              sortValue: (s) => s.telephone,
              flex: 2,
              cell: (s) => saTextCell(s.telephone),
            ),
            TableColumnSpec(
              label: 'Status',
              sortValue: (s) => s.status,
              flex: 1,
              cell: (s) => StatusBadge(status: s.status),
            ),
          ],
          actions: (s) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RowActionButton(
                icon: Icons.edit_rounded,
                onTap: () => openEdit(s),
              ),
              RowActionButton(
                icon: Icons.delete_outline_rounded,
                onTap: () => confirmDelete(s),
                danger: true,
              ),
            ],
          ),
          // Clic sur une ligne → fiche détail pleine page de la société.
          onRowTap: openDetail,
        ),
      ],
    );
  }
}
