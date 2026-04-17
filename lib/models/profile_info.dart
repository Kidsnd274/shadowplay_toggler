class ProfileInfo {
  final String name;
  final int index;
  final int numApplications;
  final int numSettings;
  final bool isPredefined;

  const ProfileInfo({
    required this.name,
    required this.index,
    required this.numApplications,
    required this.numSettings,
    required this.isPredefined,
  });

  factory ProfileInfo.fromJson(Map<String, dynamic> json) {
    // Parse numeric fields via `num?` then `toInt()` so a JSON value
    // serialized as `42.0` (perfectly legal per the spec, and how some
    // C++ JSON libraries emit integers) still lands on the right
    // field instead of throwing a `TypeError` mid-parse. Plan F-39.
    int intOr(String key, int fallback) {
      final v = json[key];
      if (v is num) return v.toInt();
      return fallback;
    }

    return ProfileInfo(
      name: json['name'] as String? ?? '',
      index: intOr('index', -1),
      numApplications: intOr('numApplications', 0),
      numSettings: intOr('numSettings', 0),
      isPredefined: json['isPredefined'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'index': index,
        'numApplications': numApplications,
        'numSettings': numSettings,
        'isPredefined': isPredefined,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          index == other.index;

  @override
  int get hashCode => name.hashCode ^ index.hashCode;

  @override
  String toString() =>
      'ProfileInfo(name: $name, index: $index, apps: $numApplications, '
      'settings: $numSettings, predefined: $isPredefined)';
}
