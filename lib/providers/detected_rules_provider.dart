import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exclusion_rule.dart';

final detectedRulesProvider = StateProvider<List<ExclusionRule>>(
  (ref) => [],
);
