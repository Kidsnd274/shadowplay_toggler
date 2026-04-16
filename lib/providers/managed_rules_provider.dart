import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exclusion_rule.dart';

final managedRulesProvider = StateProvider<List<ExclusionRule>>(
  (ref) => [],
);
