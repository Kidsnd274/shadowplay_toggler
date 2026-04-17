import 'managed_rule.dart';

class ExclusionRule {
  final String exePath;
  final String exeName;
  final String profileName;
  final bool isManaged;
  final bool isPredefined;
  final int currentValue;
  final int? previousValue;
  final String sourceType; // 'managed', 'external', 'nvidia_default', 'inherited'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExclusionRule({
    required this.exePath,
    required this.exeName,
    required this.profileName,
    required this.isManaged,
    required this.isPredefined,
    required this.currentValue,
    this.previousValue,
    required this.sourceType,
    this.createdAt,
    this.updatedAt,
  });

  factory ExclusionRule.fromManagedRule(ManagedRule rule) {
    return ExclusionRule(
      exePath: rule.exePath,
      exeName: rule.exeName,
      profileName: rule.profileName,
      isManaged: true,
      isPredefined: rule.profileWasPredefined,
      currentValue: rule.intendedValue,
      previousValue: rule.previousValue,
      sourceType: 'managed',
      createdAt: rule.createdAt,
      updatedAt: rule.updatedAt,
    );
  }

  /// Plan F-36: same limitation as `ManagedRule.copyWith` — passing
  /// `null` for any nullable field here (`previousValue`, `createdAt`,
  /// `updatedAt`) is interpreted as "leave it alone", not "clear it",
  /// because the standard `param ?? this.param` pattern cannot
  /// distinguish "user omitted" from "user wants null". No call site
  /// currently needs the clearing semantics; if one does, introduce a
  /// sentinel wrapper or build a fresh instance via the constructor.
  ExclusionRule copyWith({
    String? exePath,
    String? exeName,
    String? profileName,
    bool? isManaged,
    bool? isPredefined,
    int? currentValue,
    int? previousValue,
    String? sourceType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExclusionRule(
      exePath: exePath ?? this.exePath,
      exeName: exeName ?? this.exeName,
      profileName: profileName ?? this.profileName,
      isManaged: isManaged ?? this.isManaged,
      isPredefined: isPredefined ?? this.isPredefined,
      currentValue: currentValue ?? this.currentValue,
      previousValue: previousValue ?? this.previousValue,
      sourceType: sourceType ?? this.sourceType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Two rules are considered equal when their `(exePath, profileName,
  /// sourceType)` triple matches. `sourceType` is part of identity because the
  /// same exe+profile pair can appear in multiple tabs (Managed / Detected /
  /// NVIDIA Default) and clicking the "same-looking" row in a different tab
  /// must reselect, not be swallowed as a no-op by [StateController.state=].
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExclusionRule &&
          runtimeType == other.runtimeType &&
          exePath == other.exePath &&
          profileName == other.profileName &&
          sourceType == other.sourceType;

  @override
  int get hashCode => Object.hash(exePath, profileName, sourceType);
}
