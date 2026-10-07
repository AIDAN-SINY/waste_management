import 'package:flutter/material.dart';

import '../theme.dart';

/// Champ de recherche compact, style console superadmin.
///
/// Réutilisé par les pages Agences / Sociétés / Utilisateurs du superadmin
/// et par la console entreprise (recherche agences / managers).
class SaSearchField extends StatelessWidget {
  const SaSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search…',
  });

  final TextEditingController controller;

  /// Appelé à chaque frappe (déjà trimmed par les appelants).
  final ValueChanged<String> onChanged;

  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: SuperAdminTheme.inter(13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: SuperAdminTheme.inter(12.5, color: SuperAdminTheme.muted),
        prefixIcon: Icon(Icons.search_rounded,
            size: 16, color: SuperAdminTheme.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SuperAdminTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SuperAdminTheme.ink),
        ),
        filled: true,
        fillColor: SuperAdminTheme.surface,
      ),
    );
  }
}
