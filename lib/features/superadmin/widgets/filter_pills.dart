import 'package:flutter/material.dart';

import '../theme.dart';

/// Row of filter pills (Toutes / Actives / Suspendues...) from the design.
class FilterPills extends StatelessWidget {
  const FilterPills({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < labels.length; i++)
          _pill(labels[i], active: i == activeIndex, onTap: () => onChanged(i)),
      ],
    );
  }

  Widget _pill(String label, {required bool active, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? SuperAdminTheme.ink : SuperAdminTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? SuperAdminTheme.ink : SuperAdminTheme.border,
          ),
        ),
        child: Text(
          label,
          style: SuperAdminTheme.inter(
            12,
            weight: FontWeight.w500,
            color: active ? SuperAdminTheme.cream : SuperAdminTheme.muted,
          ),
        ),
      ),
    );
  }
}
