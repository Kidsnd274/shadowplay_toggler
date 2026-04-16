import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backup_info.dart';
import '../services/backup_service.dart';
import 'nvapi_service_provider.dart';

/// App-state key marking whether the user has been offered the "before
/// first write" backup prompt. Stored in the `app_state` table via
/// [AppStateRepository].
const kFirstBackupDoneKey = 'first_backup_done';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.read(nvapiServiceProvider));
});

/// `AsyncNotifier`-backed list of existing backups. Call [refresh] after
/// creating or deleting one.
class BackupListNotifier extends AsyncNotifier<List<BackupInfo>> {
  late final BackupService _service;

  @override
  Future<List<BackupInfo>> build() async {
    _service = ref.watch(backupServiceProvider);
    return _service.listBackups();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_service.listBackups);
  }
}

final backupListProvider =
    AsyncNotifierProvider<BackupListNotifier, List<BackupInfo>>(
  BackupListNotifier.new,
);

/// True while a backup / restore operation is in flight. The dialog uses
/// this to disable buttons and show a spinner.
final isBackingUpProvider = StateProvider<bool>((ref) => false);
