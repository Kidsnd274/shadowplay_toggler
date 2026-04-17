import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../constants/nvapi_status.dart';
import '../models/exclusion_rule.dart';
import '../providers/database_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/nvapi_service_provider.dart';
import '../providers/reconciliation_provider.dart';
import '../services/notification_service.dart';
import '../services/nvapi_service.dart';

/// Known community-identified values for the capture-exclusion setting.
/// Keep this list short — only add entries for values we've verified have
/// a stable meaning across recent drivers. Entries appear in the dropdown
/// reference in the advanced editor.
const List<_KnownValue> _knownValues = [
  _KnownValue(
    label: 'Exclude from capture',
    hex: AppConstants.captureDisableValue,
    description: 'Community-identified. Disables NVIDIA overlay/capture '
        'for this application.',
  ),
  _KnownValue(
    label: 'No override (clear)',
    hex: AppConstants.captureEnableValue,
    description: 'Zero-value override. Prefer "Reset to default" — '
        'writing 0x00000000 is semantically different from deleting '
        'the setting key.',
  ),
];

class _KnownValue {
  final String label;
  final int hex;
  final String description;
  const _KnownValue({
    required this.label,
    required this.hex,
    required this.description,
  });
}

/// Expandable "Advanced" panel embedded in the rule detail pane.
///
/// Shows raw setting info for [rule] and, when the rule is managed,
/// exposes a hex editor for writing arbitrary values to setting
/// `0x809D5F60`. Detected/default rules get read-only raw info only.
class AdvancedEditor extends ConsumerStatefulWidget {
  final ExclusionRule rule;

  /// Whether the hex editor is writable (true for managed rules, false
  /// for read-only detected/default entries). Even when writable, the
  /// panel still respects NVAPI-ready state.
  final bool allowEdit;

  const AdvancedEditor({
    super.key,
    required this.rule,
    this.allowEdit = false,
  });

  @override
  ConsumerState<AdvancedEditor> createState() => _AdvancedEditorState();
}

class _AdvancedEditorState extends ConsumerState<AdvancedEditor> {
  bool _expanded = false;
  late TextEditingController _hexController;
  bool _busy = false;

  /// Live info pulled via `getSetting(profileIndex, settingId)` after the
  /// panel expands. Null until the first load, or when lookup fails.
  _SettingSnapshot? _live;

  /// Cached profile index. -1 while the lookup has never succeeded, null
  /// while we have no data at all yet.
  int? _profileIndex;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: _formatHex(widget.rule.currentValue),
    );
  }

  @override
  void didUpdateWidget(AdvancedEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The detail view swaps in a different ExclusionRule when the user
    // selects a new row. Reset the editor state so stale hex input from
    // the previous rule doesn't leak across.
    if (oldWidget.rule.exePath != widget.rule.exePath ||
        oldWidget.rule.profileName != widget.rule.profileName) {
      _hexController.text = _formatHex(widget.rule.currentValue);
      _live = null;
      _profileIndex = null;
      if (_expanded) {
        unawaited(_refreshLiveInfo());
      }
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _toggleExpanded() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _live == null) {
      await _refreshLiveInfo();
    }
  }

  Future<void> _refreshLiveInfo() async {
    final index = await _resolveProfileIndex();
    if (!mounted) return;
    if (index == null) {
      setState(() {
        _live = null;
        _profileIndex = -1;
      });
      return;
    }

    try {
      final nvapi = ref.read(nvapiServiceProvider);
      final data = await nvapi.getSetting(index, AppConstants.captureSettingId);
      if (!mounted) return;
      setState(() {
        _profileIndex = index;
        _live = data != null ? _SettingSnapshot.fromMap(data) : null;
        _hexController.text =
            _formatHex(_live?.currentValue ?? widget.rule.currentValue);
      });
    } on NvapiBridgeException {
      if (!mounted) return;
      setState(() {
        _profileIndex = index;
        _live = null;
      });
    }
  }

  /// Looks up the profile index by profile name using the full profile
  /// list. Cached per panel lifetime.
  Future<int?> _resolveProfileIndex() async {
    if (_profileIndex != null && _profileIndex! >= 0) return _profileIndex;
    try {
      final nvapi = ref.read(nvapiServiceProvider);
      final profiles = await nvapi.getAllProfiles();
      for (final p in profiles) {
        if (p.name == widget.rule.profileName) return p.index;
      }
    } on NvapiBridgeException {
      return null;
    }
    return null;
  }

  /// Backstop for raw hex writes while a scan or reconciliation is in
  /// flight — we must not enter the shared bridge session concurrently.
  /// The Apply / Reset buttons already grey out via [bridgeBusyProvider],
  /// but keyboard shortcuts or rapid clicks can still land mid-transition.
  bool _assertBridgeFree() {
    if (!ref.read(bridgeBusyProvider)) return true;
    final reconciling = ref.read(isReconcilingProvider);
    final msg = reconciling
        ? 'Startup reconciliation is still running — try again in a moment.'
        : 'A scan is in progress — try again in a moment.';
    NotificationService.showInfo(msg);
    return false;
  }

  Future<void> _applyHex() async {
    if (!_assertBridgeFree()) return;
    final parsed = _parseHex(_hexController.text);
    if (parsed == null) {
      NotificationService.showWarning(
        'Enter a valid hex value (e.g. 0x10000000 or 10000000).',
      );
      return;
    }

    final index = await _resolveProfileIndex();
    if (index == null) {
      NotificationService.showError(
        'Could not locate profile ${widget.rule.profileName}.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final nvapi = ref.read(nvapiServiceProvider);
      final status = await nvapi.setDwordSettingRaw(
        index,
        AppConstants.captureSettingId,
        parsed,
      );
      if (status != 0) {
        NotificationService.showError(
          humanizeNvapiStatus(
            status,
            'Failed to write setting.',
          ),
        );
        return;
      }
      await nvapi.saveSettings();
      await _persistIntendedValue(parsed);
      await _refreshLiveInfo();
      NotificationService.showSuccess(
        'Setting updated to ${_formatHex(parsed)}.',
      );
      NotificationService.showRestartTargetHint(widget.rule.exeName);
    } on NvapiBridgeException catch (e) {
      NotificationService.showError(
        humanizeNvapiStatus(e.statusCode, 'Failed to write setting.'),
        details: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetToDefault() async {
    if (!_assertBridgeFree()) return;
    final index = await _resolveProfileIndex();
    if (index == null) {
      NotificationService.showError(
        'Could not locate profile ${widget.rule.profileName}.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final nvapi = ref.read(nvapiServiceProvider);
      final status = await nvapi.restoreSettingDefaultRaw(
        index,
        AppConstants.captureSettingId,
      );
      if (status != 0) {
        // Some profiles have no predefined value — fall back to delete.
        final deleteStatus = await nvapi.deleteSettingRaw(
          index,
          AppConstants.captureSettingId,
        );
        if (deleteStatus != 0) {
          NotificationService.showError(
            humanizeNvapiStatus(
              deleteStatus,
              'Failed to reset setting.',
            ),
          );
          return;
        }
      }
      await nvapi.saveSettings();
      await _refreshLiveInfo();
      NotificationService.showSuccess('Setting reset to default.');
      NotificationService.showRestartTargetHint(widget.rule.exeName);
    } on NvapiBridgeException catch (e) {
      NotificationService.showError(
        humanizeNvapiStatus(e.statusCode, 'Failed to reset setting.'),
        details: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persistIntendedValue(int value) async {
    // Only managed rules are tracked in the local DB. For detected/default
    // rules we leave persistence to the adopt flow (plan 27).
    if (widget.rule.sourceType != 'managed') return;

    final repo = ref.read(managedRulesRepositoryProvider);
    final existing = await repo.getRuleByExePath(widget.rule.exePath);
    if (existing == null) return;

    final now = DateTime.now();
    await repo.updateRule(
      existing.copyWith(intendedValue: value, updatedAt: now),
    );
    await ref.read(managedRulesProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bridgeBusy = ref.watch(bridgeBusyProvider);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.code, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Advanced',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    'Setting 0x${AppConstants.captureSettingId.toRadixString(16).toUpperCase()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WarningBanner(),
                  const SizedBox(height: 12),
                  _RawInfoTable(rule: widget.rule, live: _live),
                  const SizedBox(height: 16),
                  if (widget.allowEdit)
                    _HexEditorRow(
                      controller: _hexController,
                      busy: _busy || bridgeBusy,
                      onApply: _applyHex,
                      onReset: _resetToDefault,
                    )
                  else
                    Text(
                      'Read-only. Adopt this rule to edit its raw value.',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 16),
                  _KnownValuesReference(
                    onPick: widget.allowEdit
                        ? (v) => _hexController.text = _formatHex(v)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA000).withValues(alpha: 0.15),
        border: Border.all(
          color: const Color(0xFFFFA000).withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Color(0xFFFFA000),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Advanced mode: this setting is not officially documented by '
              'NVIDIA. Values may behave differently across driver versions. '
              'Use at your own risk.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _RawInfoTable extends StatelessWidget {
  final ExclusionRule rule;
  final _SettingSnapshot? live;

  const _RawInfoTable({required this.rule, required this.live});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv(theme, 'Setting ID',
            '0x${AppConstants.captureSettingId.toRadixString(16).toUpperCase().padLeft(8, '0')}'),
        _kv(theme, 'Setting name',
            'Capture exclusion (community-identified)'),
        _kv(
          theme,
          'Current value',
          _formatHex(live?.currentValue ?? rule.currentValue),
          suffix: _decimalOf(live?.currentValue ?? rule.currentValue),
        ),
        if (live?.predefinedValue != null)
          _kv(
            theme,
            'Predefined value',
            _formatHex(live!.predefinedValue!),
            suffix: _decimalOf(live!.predefinedValue!),
          ),
        _kv(
          theme,
          'Current is predefined',
          (live?.isCurrentPredefined ?? false) ? 'Yes' : 'No',
        ),
        if (live?.settingLocation != null)
          _kv(theme, 'Setting location', live!.settingLocation!),
      ],
    );
  }

  Widget _kv(ThemeData theme, String label, String value, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              suffix != null ? '$value  $suffix' : value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HexEditorRow extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final Future<void> Function() onApply;
  final Future<void> Function() onReset;

  const _HexEditorRow({
    required this.controller,
    required this.busy,
    required this.onApply,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Raw hex value', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                style: const TextStyle(fontFamily: 'monospace'),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9a-fA-FxX]'),
                  ),
                ],
                decoration: const InputDecoration(
                  hintText: '0x10000000',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final parsed = _parseHex(value.text);
                return SizedBox(
                  width: 110,
                  child: Text(
                    parsed != null ? _decimalOf(parsed) : '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onApply,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Apply'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : onReset,
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('Reset to Default'),
            ),
            if (busy) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _KnownValuesReference extends StatelessWidget {
  final ValueChanged<int>? onPick;

  const _KnownValuesReference({this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Known values', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        for (final v in _knownValues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    _formatHex(v.hex),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.label, style: theme.textTheme.bodyMedium),
                      Text(v.description, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (onPick != null)
                  TextButton(
                    onPressed: () => onPick!(v.hex),
                    child: const Text('Use'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SettingSnapshot {
  final int currentValue;
  final int? predefinedValue;
  final bool isCurrentPredefined;
  final String? settingLocation;

  const _SettingSnapshot({
    required this.currentValue,
    required this.predefinedValue,
    required this.isCurrentPredefined,
    required this.settingLocation,
  });

  factory _SettingSnapshot.fromMap(Map<String, dynamic> map) {
    int? parse(dynamic v) {
      if (v is int) return v;
      if (v is String) {
        final cleaned = v.startsWith('0x') || v.startsWith('0X')
            ? v.substring(2)
            : v;
        return int.tryParse(cleaned, radix: 16);
      }
      return null;
    }

    return _SettingSnapshot(
      currentValue: parse(map['currentValue']) ?? 0,
      predefinedValue: parse(map['predefinedValue']),
      isCurrentPredefined: (map['isCurrentPredefined'] as bool?) ?? false,
      settingLocation: map['settingLocation'] as String?,
    );
  }
}

// ── Shared helpers ──────────────────────────────────────────────────

String _formatHex(int value) =>
    '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';

String _decimalOf(int value) => '($value)';

int? _parseHex(String raw) {
  if (raw.trim().isEmpty) return null;
  var cleaned = raw.trim();
  if (cleaned.startsWith('0x') || cleaned.startsWith('0X')) {
    cleaned = cleaned.substring(2);
  }
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned, radix: 16);
}
