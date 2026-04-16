import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/nvidia_defaults_provider.dart';
import '../providers/detected_rules_provider.dart';
import '../providers/search_provider.dart';
import '../providers/selected_tab_provider.dart';
import 'detected_rules_tab.dart';
import 'managed_rules_tab.dart';
import 'nvidia_defaults_tab.dart';

class LeftPane extends ConsumerStatefulWidget {
  final VoidCallback? onScanProfiles;

  const LeftPane({super.key, this.onScanProfiles});

  @override
  ConsumerState<LeftPane> createState() => _LeftPaneState();
}

class _LeftPaneState extends ConsumerState<LeftPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(selectedTabProvider);
    _tabController = TabController(
      length: LeftPaneTab.values.length,
      vsync: this,
      initialIndex: initial.index,
    );
    _tabController.addListener(_handleTabChanged);

    _searchController = TextEditingController(text: ref.read(searchProvider));
    _searchController.addListener(_handleSearchChanged);
    _searchFocus = FocusNode();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    final newTab = LeftPaneTab.values[_tabController.index];
    if (ref.read(selectedTabProvider) != newTab) {
      ref.read(selectedTabProvider.notifier).state = newTab;
    }
  }

  void _handleSearchChanged() {
    final text = _searchController.text;
    if (ref.read(searchProvider) != text) {
      ref.read(searchProvider.notifier).state = text;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _searchFocus.hasFocus) {
      _searchController.clear();
      _searchFocus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ref.listen<LeftPaneTab>(selectedTabProvider, (prev, next) {
      if (_tabController.index != next.index) {
        _tabController.animateTo(next.index);
      }
    });

    return Focus(
      autofocus: false,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 260),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            right: BorderSide(color: theme.dividerTheme.color ?? Colors.grey),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchField(
              controller: _searchController,
              focusNode: _searchFocus,
            ),
            _LeftPaneTabBar(controller: _tabController),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  const ManagedRulesTab(),
                  DetectedRulesTab(onScanProfiles: widget.onScanProfiles),
                  NvidiaDefaultsTab(onScanProfiles: widget.onScanProfiles),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _SearchField({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search rules…',
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  splashRadius: 16,
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: controller.clear,
                );
              },
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 8,
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftPaneTabBar extends ConsumerWidget {
  final TabController controller;
  const _LeftPaneTabBar({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final defaultsCount = ref.watch(
      nvidiaDefaultsProvider.select((s) => s.rules.length),
    );
    final managedCount = ref.watch(
      managedRulesProvider.select((a) => a.valueOrNull?.length ?? 0),
    );
    final detectedCount = ref.watch(
      detectedRulesProvider.select((s) => s.rules.length),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerTheme.color ?? Colors.transparent,
          ),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: false,
        labelPadding: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        tabs: [
          _buildTab('Managed', managedCount),
          _buildTab('Detected', detectedCount),
          _buildTab('Defaults', defaultsCount),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int count) {
    return Tab(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          if (count > 0) ...[
            const SizedBox(width: 6),
            _CountBadge(count: count),
          ],
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
