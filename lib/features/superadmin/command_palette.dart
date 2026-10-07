import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// A command palette entry.
class CmdItem {
  const CmdItem({
    required this.icon,
    required this.label,
    required this.hint,
    required this.run,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback run;
}

/// Shows the command palette (design's `cmdk`).
Future<void> showCommandPalette(
  BuildContext context, {
  required List<CmdItem> navItems,
  required List<CmdItem> actionItems,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) =>
        _CommandPalette(navItems: navItems, actionItems: actionItems),
    transitionBuilder: (context, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.05),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      );
    },
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.navItems, required this.actionItems});

  final List<CmdItem> navItems;
  final List<CmdItem> actionItems;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  late final TextEditingController _controller = TextEditingController();
  late final ScrollController _scrollController = ScrollController();

  // Intercepts arrows / enter / escape while the field is focused,
  // and lets text keys fall through to the TextField.
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _onKey);

  List<CmdItem> get _navItems =>
      _query.isEmpty ? widget.navItems : _filter(widget.navItems);
  List<CmdItem> get _actionItems =>
      _query.isEmpty ? widget.actionItems : _filter(widget.actionItems);
  List<CmdItem> get _flat => [..._navItems, ..._actionItems];

  String get _query => _controller.text.trim().toLowerCase();
  int _activeIndex = 0;

  List<CmdItem> _filter(List<CmdItem> items) =>
      items.where((i) => i.label.toLowerCase().contains(_query)).toList();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final items = _flat;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (items.isNotEmpty) _setActive((_activeIndex + 1).clamp(0, items.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (items.isNotEmpty) _setActive((_activeIndex - 1).clamp(0, items.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (items.isNotEmpty) {
        final item = items[_activeIndex];
        Navigator.of(context).pop();
        item.run();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setActive(int index) {
    setState(() => _activeIndex = index);
    final offset = (index * 42.0) - 90;
    if (_scrollController.hasClients && offset > 0) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  void _run(CmdItem item) {
    Navigator.of(context).pop();
    item.run();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.9).clamp(0.0, 560.0);
    final navItems = _navItems;
    final actionItems = _actionItems;

    return Center(
      child: Align(
        alignment: Alignment(0, -0.55),
        child: Material(
          color: SuperAdminTheme.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Input row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: SuperAdminTheme.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 15,
                        color: SuperAdminTheme.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          style: SuperAdminTheme.inter(15),
                          decoration: const InputDecoration(
                            hintText: "Go to... or create...",
                            hintStyle: TextStyle(color: SuperAdminTheme.muted),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onChanged: (_) => setState(() => _activeIndex = 0),
                        ),
                      ),
                      _kbd('Esc'),
                    ],
                  ),
                ),
                // Results
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView(
                        controller: _scrollController,
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        children: [
                          if (navItems.isNotEmpty) ...[
                            _groupLabel('Navigation'),
                            for (var i = 0; i < navItems.length; i++)
                              _item(navItems[i], i),
                          ],
                          if (actionItems.isNotEmpty) ...[
                            _groupLabel('Actions'),
                            for (var i = 0; i < actionItems.length; i++)
                              _item(actionItems[i], navItems.length + i),
                          ],
                          if (navItems.isEmpty && actionItems.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  'No results',
                                  style: SuperAdminTheme.inter(
                                    12.5,
                                    color: SuperAdminTheme.muted,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Text(
        label.toUpperCase(),
        style: SuperAdminTheme.inter(
          10,
          weight: FontWeight.w600,
          color: SuperAdminTheme.muted,
          // letter spacing simulated by padding
        ),
      ),
    );
  }

  Widget _item(CmdItem item, int index) {
    final active = index == _activeIndex;
    return InkWell(
      onTap: () => _run(item),
      onHover: (_) => setState(() => _activeIndex = index),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? SuperAdminTheme.rowHover : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 13,
              color: active ? SuperAdminTheme.goldDim : SuperAdminTheme.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: SuperAdminTheme.inter(13),
              ),
            ),
            Text(
              item.hint,
              style: SuperAdminTheme.inter(
                10.5,
                color: SuperAdminTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kbd(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: SuperAdminTheme.bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: SuperAdminTheme.border),
      ),
      child: Text(
        text,
        style: SuperAdminTheme.inter(10.5, color: SuperAdminTheme.muted),
      ),
    );
  }
}
