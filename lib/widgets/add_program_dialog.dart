import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/add_program_result.dart';
import '../models/exclusion_rule.dart';
import '../models/managed_rule.dart';
import '../providers/add_program_provider.dart';
import '../providers/managed_rules_provider.dart';
import '../providers/selected_rule_provider.dart';
import '../providers/selected_tab_provider.dart';
import '../services/add_program_service.dart';
import 'backup_dialog.dart';

/// Entry point for the Add Program flow. Returns the final result once
/// the dialog is dismissed, or null if the user cancelled at any step.
///
/// When [presetPath] is provided (e.g. from a drag-and-drop operation),
/// the file-picker step is skipped and the flow jumps directly into the
/// confirmation dialog for that path. The caller is responsible for
/// ensuring the path points to an `.exe`.
Future<AddProgramResult?> runAddProgramFlow(
  BuildContext context,
  WidgetRef ref, {
  String? presetPath,
}) async {
  String? path = presetPath;

  if (path == null) {
    final pick = await FilePicker.pickFiles(
      dialogTitle: 'Select an executable',
      type: FileType.custom,
      allowedExtensions: const ['exe'],
      lockParentWindow: true,
    );
    if (pick == null || pick.files.isEmpty) return null;
    path = pick.files.single.path;
    if (path == null) return null;
  }

  if (!context.mounted) return null;

  final result = await showDialog<AddProgramResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddProgramDialog(exePath: path!),
  );

  if (result != null && result.success && context.mounted) {
    await ref.read(managedRulesProvider.notifier).refresh();
    _autoSelectNewRule(ref, result);
  }

  return result;
}

void _autoSelectNewRule(WidgetRef ref, AddProgramResult result) {
  final rules = ref.read(managedRulesProvider).valueOrNull;
  if (rules == null) return;
  final added = rules.firstWhere(
    (r) => r.exePath == result.exePath,
    orElse: () => _stub(result),
  );
  ref.read(selectedTabProvider.notifier).state = LeftPaneTab.managed;
  ref.read(selectedRuleProvider.notifier).state =
      ExclusionRule.fromManagedRule(added);
}

ManagedRule _stub(AddProgramResult r) => ManagedRule(
      exePath: r.exePath,
      exeName: r.exeName,
      profileName: r.profileName,
      profileWasPredefined: false,
      profileWasCreated: false,
      intendedValue: 0x10000000,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

enum _DialogStep { loading, confirm, applying, done, error }

class _AddProgramDialog extends ConsumerStatefulWidget {
  final String exePath;
  const _AddProgramDialog({required this.exePath});

  @override
  ConsumerState<_AddProgramDialog> createState() => _AddProgramDialogState();
}

class _AddProgramDialogState extends ConsumerState<_AddProgramDialog> {
  _DialogStep _step = _DialogStep.loading;
  AddProgramPreview? _preview;
  AddProgramResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runPreview();
  }

  Future<void> _runPreview() async {
    final service = ref.read(addProgramServiceProvider);
    try {
      final preview = await service.preview(widget.exePath);
      if (!mounted) return;
      if (preview.hasError) {
        setState(() {
          _step = _DialogStep.error;
          _error = preview.errorMessage;
        });
        return;
      }
      setState(() {
        _preview = preview;
        _step = _DialogStep.confirm;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _DialogStep.error;
        _error = 'Unexpected error: $e';
      });
    }
  }

  Future<void> _runCommit() async {
    // Plan 24: offer a DRS backup before the *first* driver write. After
    // the one-shot prompt has been handled (or skipped), subsequent
    // additions skip straight to the commit.
    final shouldProceed = await offerFirstBackupIfNeeded(context, ref);
    if (!shouldProceed) {
      if (!mounted) return;
      Navigator.of(context).pop(null);
      return;
    }

    if (!mounted) return;
    setState(() => _step = _DialogStep.applying);
    final service = ref.read(addProgramServiceProvider);
    try {
      final result = await service.commit(widget.exePath);
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = result.success ? _DialogStep.done : _DialogStep.error;
        _error = result.errorMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _DialogStep.error;
        _error = 'Unexpected error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_step) {
            _DialogStep.loading => _Loading(exePath: widget.exePath),
            _DialogStep.confirm => _Confirm(
                preview: _preview!,
                onCancel: () => Navigator.of(context).pop(null),
                onConfirm: _runCommit,
              ),
            _DialogStep.applying => const _Applying(),
            _DialogStep.done => _Done(
                result: _result!,
                onClose: () => Navigator.of(context).pop(_result),
              ),
            _DialogStep.error => _Error(
                message: _error ?? 'Unknown error',
                onClose: () => Navigator.of(context).pop(
                  _result ??
                      AddProgramResult.error(
                        exePath: widget.exePath,
                        exeName: widget.exePath.split(RegExp(r'[\\/]')).last,
                        message: _error ?? 'Unknown error',
                      ),
                ),
              ),
          },
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  final String exePath;
  const _Loading({required this.exePath});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Checking NVIDIA profile…', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(exePath,
            style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        const Center(
            child: SizedBox(
                height: 24, width: 24, child: CircularProgressIndicator())),
      ],
    );
  }
}

class _Confirm extends StatelessWidget {
  final AddProgramPreview preview;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _Confirm({
    required this.preview,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = preview.alreadyInLocalDb
        ? 'Already in your Managed list'
        : preview.profileAlreadyExisted
            ? 'This executable already has an NVIDIA profile'
            : 'Create a new exclusion rule';

    final body = preview.alreadyInLocalDb
        ? "A managed rule for '${preview.exeName}' already exists. Re-applying "
            "will refresh the NVIDIA profile setting and update the local "
            "record."
        : preview.profileAlreadyExisted
            ? "'${preview.exeName}' is already attached to profile "
                "'${preview.matchedProfileName}'"
                "${preview.profileIsPredefined ? ' (NVIDIA-predefined).' : '.'} "
                "The capture-exclusion setting will be applied to that "
                "existing profile."
            : "A new NVIDIA profile named '${preview.exeName}' will be "
                "created, the executable attached to it, and the "
                "capture-exclusion setting will be applied.";

    final ctaLabel = preview.alreadyInLocalDb
        ? 'Reapply'
        : preview.profileAlreadyExisted
            ? 'Apply Exclusion'
            : 'Create Rule';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _PathCard(path: preview.exePath),
        const SizedBox(height: 12),
        Text(body, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: onConfirm, child: Text(ctaLabel)),
          ],
        ),
      ],
    );
  }
}

class _Applying extends StatelessWidget {
  const _Applying();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Applying exclusion…', style: theme.textTheme.titleMedium),
        const SizedBox(height: 20),
        const Center(
            child: SizedBox(
                height: 24, width: 24, child: CircularProgressIndicator())),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  final AddProgramResult result;
  final VoidCallback onClose;

  const _Done({required this.result, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Exclusion applied', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        _KeyValue('Executable', result.exeName),
        _KeyValue('Profile', result.profileName),
        if (result.exclusionAlreadyApplied)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The setting was already applied — no changes needed.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Tip: restart the target app for the change to fully take effect.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(onPressed: onClose, child: const Text('Done')),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _Error({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Text('Unable to add program', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        Text(message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onClose, child: const Text('Close')),
        ),
      ],
    );
  }
}

class _PathCard extends StatelessWidget {
  final String path;
  const _PathCard({required this.path});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        path,
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
