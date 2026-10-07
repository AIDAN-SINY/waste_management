import 'package:flutter/material.dart';

import '../theme.dart';

/// Labeled text field matching the design's form inputs.
class SaTextField extends StatelessWidget {
  const SaTextField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initial,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final String? initial;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextFormField(
          initialValue: initial,
          onChanged: onChanged,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: SuperAdminTheme.inter(13, color: SuperAdminTheme.text),
          decoration: _decoration(hint),
        ),
      ],
    );
  }
}

/// Labeled dropdown matching the design's form selects.
class SaSelectField extends StatelessWidget {
  const SaSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.initial,
  });

  final String label;
  final List<String> options;
  final String? initial;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // Guard against an initial value that is no longer in the options
    // (e.g. the referenced société/agence was deleted) to avoid a
    // DropdownButton assertion error at runtime.
    final resolvedInitial =
        (initial != null && options.contains(initial))
        ? initial
        : (options.isNotEmpty ? options.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        DropdownButtonFormField<String>(
          initialValue: resolvedInitial,
          isExpanded: true,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
          style: SuperAdminTheme.inter(13, color: SuperAdminTheme.text),
          decoration: _decoration(null),
        ),
      ],
    );
  }
}

Widget _label(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: SuperAdminTheme.inter(11.5, weight: FontWeight.w600, color: SuperAdminTheme.muted),
    ),
  );
}

InputDecoration _decoration(String? hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: SuperAdminTheme.inter(12.5, color: SuperAdminTheme.muted),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    filled: true,
    fillColor: SuperAdminTheme.bg,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: SuperAdminTheme.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: SuperAdminTheme.ink),
    ),
  );
}
