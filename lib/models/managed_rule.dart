class ManagedRule {
  final int? id;
  final String exePath;
  final String exeName;
  final String profileName;
  final bool profileWasPredefined;
  final bool profileWasCreated;
  final int intendedValue;
  final int? previousValue;
  final String? driverVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ManagedRule({
    this.id,
    required this.exePath,
    required this.exeName,
    required this.profileName,
    required this.profileWasPredefined,
    required this.profileWasCreated,
    required this.intendedValue,
    this.previousValue,
    this.driverVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ManagedRule.fromMap(Map<String, dynamic> map) {
    return ManagedRule(
      id: map['id'] as int?,
      exePath: map['exe_path'] as String,
      exeName: map['exe_name'] as String,
      profileName: map['profile_name'] as String,
      profileWasPredefined: (map['profile_was_predefined'] as int) == 1,
      profileWasCreated: (map['profile_was_created'] as int) == 1,
      intendedValue: map['intended_value'] as int,
      previousValue: map['previous_value'] as int?,
      driverVersion: map['driver_version'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'exe_path': exePath,
      'exe_name': exeName,
      'profile_name': profileName,
      'profile_was_predefined': profileWasPredefined ? 1 : 0,
      'profile_was_created': profileWasCreated ? 1 : 0,
      'intended_value': intendedValue,
      'previous_value': previousValue,
      'driver_version': driverVersion,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Plan F-36: this `copyWith` cannot express "clear `previousValue`
  /// / `driverVersion` / `id`" — passing `null` for those parameters
  /// is indistinguishable from "don't change it". No caller today
  /// needs that, but anyone reaching for it should switch to a
  /// sentinel (e.g. `const _unset = Object();`) rather than shoe-
  /// horning it through `null`. The model instead exposes direct
  /// construction via the main constructor for the rare cases that
  /// need to rebuild the whole record.
  ManagedRule copyWith({
    int? id,
    String? exePath,
    String? exeName,
    String? profileName,
    bool? profileWasPredefined,
    bool? profileWasCreated,
    int? intendedValue,
    int? previousValue,
    String? driverVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ManagedRule(
      id: id ?? this.id,
      exePath: exePath ?? this.exePath,
      exeName: exeName ?? this.exeName,
      profileName: profileName ?? this.profileName,
      profileWasPredefined: profileWasPredefined ?? this.profileWasPredefined,
      profileWasCreated: profileWasCreated ?? this.profileWasCreated,
      intendedValue: intendedValue ?? this.intendedValue,
      previousValue: previousValue ?? this.previousValue,
      driverVersion: driverVersion ?? this.driverVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedRule &&
          runtimeType == other.runtimeType &&
          exePath == other.exePath;

  @override
  int get hashCode => exePath.hashCode;

  @override
  String toString() => 'ManagedRule(id: $id, exe: $exeName, '
      'profile: $profileName, value: 0x${intendedValue.toRadixString(16)})';
}
