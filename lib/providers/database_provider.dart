import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_state_repository.dart';
import '../services/database_service.dart';
import '../services/managed_rules_repository.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(() => service.close());
  return service;
});

final managedRulesRepositoryProvider = Provider<ManagedRulesRepository>((ref) {
  return ManagedRulesRepository(ref.read(databaseServiceProvider));
});

final appStateRepositoryProvider = Provider<AppStateRepository>((ref) {
  return AppStateRepository(ref.read(databaseServiceProvider));
});
