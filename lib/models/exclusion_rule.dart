import 'managed_rule.dart';

/// Where an [ExclusionRule] came from in the DRS tree. This used to be
/// a bare `String` ('managed' / 'external' / 'nvidia_default' /
/// 'inherited') scattered across the codebase, which made it easy to
/// mistype a literal and silently render a row in the wrong tab.
///
/// The enum decodes and encodes the same wire strings so persisted
/// state, tests, and any external consumer (e.g. exported logs) all
/// keep working unchanged.
enum ExclusionSource {
  /// Tracked by the local `managed_rules` table — adopted or added by
  /// the user through this app.
  managed('managed'),

  /// Detected on the driver but not tracked locally. User has the
  /// option to adopt it.
  external('external'),

  /// NVIDIA-predefined profile setting carried over from the driver's
  /// shipped defaults. The Defaults tab's territory.
  nvidiaDefault('nvidia_default'),

  /// Inherited from the DRS `Base Profile` / global setting chain.
  inherited('inherited');

  const ExclusionSource(this.wire);

  /// Canonical wire/DB string — stable across versions. Do not reuse
  /// these values for anything user-facing.
  final String wire;

  /// Reverse lookup for the wire value. Throws [ArgumentError] on an
  /// unknown string so corrupt persistence doesn't silently downgrade
  /// to a default category.
  static ExclusionSource fromWire(String value) {
    for (final s in ExclusionSource.values) {
      if (s.wire == value) return s;
    }
    throw ArgumentError.value(value, 'value', 'Unknown ExclusionSource');
  }
}

class ExclusionRule {
  final String exePath;
  final String exeName;
  final String profileName;
  final bool isManaged;
  final bool isPredefined;
  final int currentValue;
  final int? previousValue;
  final ExclusionSource source;
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
    required this.source,
    this.createdAt,
    this.updatedAt,
  });

  /// Back-compat string accessor. Existing call sites that compared
  /// `rule.sourceType == 'managed'` keep working without churn;
  /// greenfield code should match on [source] directly.
  String get sourceType => source.wire;

  factory ExclusionRule.fromManagedRule(ManagedRule rule) {
    return ExclusionRule(
      exePath: rule.exePath,
      exeName: rule.exeName,
      profileName: rule.profileName,
      isManaged: true,
      isPredefined: rule.profileWasPredefined,
      currentValue: rule.intendedValue,
      previousValue: rule.previousValue,
      source: ExclusionSource.managed,
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
    ExclusionSource? source,
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
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Two rules are considered equal when their `(exePath, profileName,
  /// source)` triple matches. `source` is part of identity because the
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
          source == other.source;

  @override
  int get hashCode => Object.hash(exePath, profileName, source);
}
