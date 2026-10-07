import 'package:flutter/material.dart';

import '../theme.dart';

/// Horizontal scrollable filter chips, faithful to the design's `.chip-row`.
class BoChipRow extends StatelessWidget {
  const BoChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Chip(
              label: options[i],
              active: options[i] == selected,
              onTap: () => onSelect(options[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? BackofficeTheme.green : BackofficeTheme.surface,
            border: Border.all(
              color: active ? BackofficeTheme.green : BackofficeTheme.border,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: BackofficeTheme.inter(
              11.5,
              weight: FontWeight.w500,
              color: active ? BackofficeTheme.cream : BackofficeTheme.muted,
            ),
          ),
        ),
      ),
    );
  }
}
