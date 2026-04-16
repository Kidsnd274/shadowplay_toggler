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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExclusionRule &&
          runtimeType == other.runtimeType &&
          exePath == other.exePath &&
          profileName == other.profileName;

  @override
  int get hashCode => exePath.hashCode ^ profileName.hashCode;
}
