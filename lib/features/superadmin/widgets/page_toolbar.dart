import 'package:flutter/material.dart';

/// Toolbar used by the entity pages: filter pills + primary action.
///
/// On wide screens the action sits on the right of the filters; on narrow
/// screens the toolbar stacks vertically.
class PageToolbar extends StatelessWidget {
  const PageToolbar({
    super.key,
    required this.filters,
    required this.action,
  });

  final Widget filters;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Row(
            children: [
              Expanded(child: filters),
              const SizedBox(width: 12),
              action,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filters,
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      },
    );
  }
}
