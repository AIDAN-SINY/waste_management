import 'package:flutter/material.dart';

import '../../superadmin/theme.dart';
import '../../superadmin/widgets/form_fields.dart';

/// Centered modal used by the General Administrator console to create an
/// agency.
///
/// At the top, a non-editable badge shows the company the new agency will
/// belong to — `Creating agency for: <company>` — the name being resolved
/// by the caller from the logged-in user's company object.
///
/// The form asks for the agency name, location, manager, manager phone,
/// city and agency phone. [onSave] receives the collected form values and
/// is responsible for persisting + showing toasts; on error it should
/// rethrow so the modal stays open for a retry.
Future<void> showCreateAgencyModal(
  BuildContext context, {
  required String companyName,
  required Future<void> Function(Map<String, dynamic> form) onSave,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => _CreateAgencyModal(
      companyName: companyName,
      onSave: onSave,
    ),
    transitionBuilder: (context, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _CreateAgencyModal extends StatefulWidget {
  const _CreateAgencyModal({
    required this.companyName,
    required this.onSave,
  });

  final String companyName;
  final Future<void> Function(Map<String, dynamic> form) onSave;

  @override
  State<_CreateAgencyModal> createState() => _CreateAgencyModalState();
}

class _CreateAgencyModalState extends State<_CreateAgencyModal> {
  final Map<String, dynamic> _form = {};
  bool _saving = false;

  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_form);
      // Only close on success; on error the caller shows a toast and the
      // modal stays open so the user can fix the form.
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Swallowed: error toasts are the caller's responsibility.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final dialogWidth = (width * 0.92).clamp(0.0, 520.0);

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: height * 0.9,
        ),
        child: Material(
          color: SuperAdminTheme.surface,
          borderRadius: BorderRadius.circular(SuperAdminTheme.radius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHead(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CompanyBadge(companyName: widget.companyName),
                      const SizedBox(height: 20),
                      SaTextField(
                        label: 'Agency name',
                        hint: 'Ex. Bastos',
                        onChanged: (v) => _form['nom'] = v,
                      ),
                      const SizedBox(height: 16),
                      SaTextField(
                        label: 'Location',
                        hint: 'Ex. Rue de la Paix, Nlongkak',
                        onChanged: (v) => _form['location'] = v,
                      ),
                      const SizedBox(height: 16),
                      SaTextField(
                        label: 'Manager',
                        hint: 'Manager name',
                        onChanged: (v) => _form['responsable'] = v,
                      ),
                      const SizedBox(height: 16),
                      SaTextField(
                        label: 'Manager phone',
                        hint: '+237 6XX XX XX XX',
                        keyboardType: TextInputType.phone,
                        onChanged: (v) => _form['managerPhone'] = v,
                      ),
                      const SizedBox(height: 16),
                      SaTextField(
                        label: 'City',
                        hint: 'Ex. Yaoundé',
                        onChanged: (v) => _form['ville'] = v,
                      ),
                      const SizedBox(height: 16),
                      SaTextField(
                        label: 'Phone',
                        hint: '+237 6XX XX XX XX',
                        keyboardType: TextInputType.phone,
                        onChanged: (v) => _form['telephone'] = v,
                      ),
                    ],
                  ),
                ),
              ),
              _buildFoot(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHead() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SuperAdminTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'New agency',
              style: SuperAdminTheme.sora(16, weight: FontWeight.w700),
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: SuperAdminTheme.border),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 15,
                color: SuperAdminTheme.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoot() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SuperAdminTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: SuperAdminTheme.border),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: SuperAdminTheme.inter(
                  12.5,
                  weight: FontWeight.w600,
                  color: SuperAdminTheme.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11),
                backgroundColor: SuperAdminTheme.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _saving ? null : _handleSave,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SuperAdminTheme.cream,
                      ),
                    )
                  : Text(
                      'Save',
                      style: SuperAdminTheme.inter(
                        12.5,
                        weight: FontWeight.w600,
                        color: SuperAdminTheme.cream,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-editable badge pinned at the top of the modal: the company the new
/// agency will belong to, from the logged-in user's company object.
class _CompanyBadge extends StatelessWidget {
  const _CompanyBadge({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SuperAdminTheme.goldSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: SuperAdminTheme.gold.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: SuperAdminTheme.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.business_rounded,
              size: 15,
              color: SuperAdminTheme.goldDim,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Creating agency for: ',
                style: SuperAdminTheme.inter(
                  12,
                  weight: FontWeight.w500,
                  color: SuperAdminTheme.muted,
                ),
                children: [
                  TextSpan(
                    text: companyName,
                    style: SuperAdminTheme.inter(
                      12.5,
                      weight: FontWeight.w700,
                      color: SuperAdminTheme.text,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
