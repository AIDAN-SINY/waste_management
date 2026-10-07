import 'package:flutter/material.dart';

import '../theme.dart';

/// Column definition for [AppTable].
class TableColumnSpec<T> {
  const TableColumnSpec({
    required this.label,
    required this.cell,
    this.sortValue,
    this.flex = 1,
  });

  final String label;

  /// Optional comparables — when provided the column becomes sortable.
  final Comparable Function(T row)? sortValue;
  final Widget Function(T row) cell;
  final int flex;
}

/// Sortable, hoverable table matching the design's `table-card`.
///
/// Responsive: on narrow screens (< 640px) each row renders as a card
/// instead of a table, so the console stays usable on phones.
class AppTable<T> extends StatefulWidget {
  const AppTable({
    super.key,
    required this.rows,
    required this.columns,
    this.actions,
    this.onRowTap,
    this.emptyText = 'No items found',
    this.footer,
  });

  final List<T> rows;
  final List<TableColumnSpec<T>> columns;
  final Widget Function(T row)? actions;

  /// Optional tap handler on a row (and on a card in mobile mode) — used to
  /// open the edit form, keeping desktop and mobile behaviour identical.
  final void Function(T row)? onRowTap;
  final String emptyText;
  final String? footer;

  @override
  State<AppTable<T>> createState() => _AppTableState<T>();
}

class _AppTableState<T> extends State<AppTable<T>> {
  int? _sortIndex;
  bool _ascending = true;
  int? _hoverIndex;

  List<T> get _sortedRows {
    final rows = widget.rows;
    if (_sortIndex == null || _sortIndex! >= widget.columns.length) return rows;
    final sortValue = widget.columns[_sortIndex!].sortValue;
    if (sortValue == null) return rows;
    final sorted = [...rows]..sort((a, b) {
        final comparison = sortValue(a).compareTo(sortValue(b));
        return _ascending ? comparison : -comparison;
      });
    return sorted;
  }

  void _toggleSort(int index) {
    if (widget.columns[index].sortValue == null) return;
    setState(() {
      if (_sortIndex == index) {
        _ascending = !_ascending;
      } else {
        _sortIndex = index;
        _ascending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedRows;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sorted.isEmpty)
                _emptyState()
              else
                for (var i = 0; i < sorted.length; i++) _card(sorted[i]),
              if (widget.footer != null) _footer(widget.footer!),
            ],
          );
        }

        return Container(
          decoration: SuperAdminTheme.card(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                color: SuperAdminTheme.rowHover,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.columns.length; i++)
                      Expanded(flex: widget.columns[i].flex, child: _headerCell(i)),
                    if (widget.actions != null) const SizedBox(width: 76),
                  ],
                ),
              ),
              // Rows
              if (sorted.isEmpty)
                _emptyState()
              else
                for (var i = 0; i < sorted.length; i++)
                  _row(sorted[i], i == sorted.length - 1, i),
              // Footer
              if (widget.footer != null) _footer(widget.footer!),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: SuperAdminTheme.card(),
      child: Center(
        child: Text(
          widget.emptyText,
          style: SuperAdminTheme.inter(12.5, color: SuperAdminTheme.muted),
        ),
      ),
    );
  }

  Widget _footer(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SuperAdminTheme.border)),
      ),
      child: Text(
        text,
        style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
      ),
    );
  }

  /// Mobile rendering: each row becomes a card.
  /// First column is the card header, last column (e.g. the status badge)
  /// sits on the right, middle columns are shown as labelled rows.
  Widget _card(T row) {
    final first = widget.columns.first;
    final last = widget.columns.length > 1 ? widget.columns.last : null;
    final middle = widget.columns.length > 2
        ? widget.columns.sublist(1, widget.columns.length - 1)
        : <TableColumnSpec<T>>[];

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SuperAdminTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SuperAdminTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first.cell(row)),
              if (last != null) last.cell(row),
            ],
          ),
          for (final column in middle) ...[
            const SizedBox(height: 12),
            Text(
              column.label.toUpperCase(),
              style: SuperAdminTheme.inter(
                10,
                weight: FontWeight.w600,
                color: SuperAdminTheme.muted,
              ),
            ),
            const SizedBox(height: 4),
            column.cell(row),
          ],
          if (widget.actions != null) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Enlarge the action buttons on mobile (28 -> ~45px) so they
                // meet the 44px touch-target guideline.
                Transform.scale(
                  scale: 1.6,
                  alignment: Alignment.centerRight,
                  child: widget.actions!(row),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (widget.onRowTap == null) return card;
    return InkWell(
      onTap: () => widget.onRowTap!(row),
      borderRadius: BorderRadius.circular(14),
      child: card,
    );
  }

  Widget _headerCell(int index) {
    final column = widget.columns[index];
    final sortable = column.sortValue != null;
    final isSorted = _sortIndex == index;

    return InkWell(
      onTap: sortable ? () => _toggleSort(index) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              column.label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: SuperAdminTheme.inter(
                10.5,
                weight: FontWeight.w600,
                color: SuperAdminTheme.muted,
              ),
            ),
          ),
          if (sortable) ...[
            const SizedBox(width: 5),
            Icon(
              isSorted
                  ? (_ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: 11,
              color: isSorted
                  ? SuperAdminTheme.goldDim
                  : SuperAdminTheme.muted.withValues(alpha: 0.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(T row, bool isLast, int index) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: _hoverIndex == index ? SuperAdminTheme.rowHover : null,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: SuperAdminTheme.border),
              ),
      ),
      child: Row(
        children: [
          for (final column in widget.columns)
            Expanded(
              flex: column.flex,
              child: column.cell(row),
            ),
          if (widget.actions != null)
            SizedBox(
              width: 76,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  widget.actions!(row),
                ],
              ),
            ),
        ],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) => setState(() => _hoverIndex = null),
      child: widget.onRowTap != null
          ? InkWell(onTap: () => widget.onRowTap!(row), child: content)
          : content,
    );
  }
}

/// Small square row-action button (edit / delete) from the design.
class RowActionButton extends StatelessWidget {
  const RowActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SuperAdminTheme.border),
        ),
        child: Icon(
          icon,
          size: 12.5,
          color: danger ? SuperAdminTheme.red : SuperAdminTheme.muted,
        ),
      ),
    );
  }
}
