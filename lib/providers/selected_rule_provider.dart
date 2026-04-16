import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exclusion_rule.dart';

final selectedRuleProvider = StateProvider<ExclusionRule?>(
  (ref) => null,
);
