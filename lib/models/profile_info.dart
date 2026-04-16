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
    return ProfileInfo(
      name: json['name'] as String? ?? '',
      index: json['index'] as int? ?? -1,
      numApplications: json['numApplications'] as int? ?? 0,
      numSettings: json['numSettings'] as int? ?? 0,
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
