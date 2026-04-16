import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadowplay_toggler/constants/app_theme.dart';
import 'package:shadowplay_toggler/models/managed_rule.dart';
import 'package:shadowplay_toggler/providers/managed_rules_provider.dart';
import 'package:shadowplay_toggler/providers/search_provider.dart';
import 'package:shadowplay_toggler/widgets/left_pane.dart';

class _FakeManagedRulesNotifier extends ManagedRulesNotifier {
  final List<ManagedRule> _rules;
  _FakeManagedRulesNotifier(this._rules);

  @override
  Future<List<ManagedRule>> build() async => _rules;
}

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('LeftPane shows three tabs and defaults to Managed',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const LeftPane(),
      overrides: [
        managedRulesProvider.overrideWith(() => _FakeManagedRulesNotifier([])),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Managed'), findsOneWidget);
    expect(find.text('Detected'), findsOneWidget);
    expect(find.text('Defaults'), findsOneWidget);

    expect(find.text('No managed rules yet'), findsOneWidget);
  });

  testWidgets('Managed tab shows rules from provider', (tester) async {
    final now = DateTime(2024, 1, 1);
    final rules = [
      ManagedRule(
        id: 1,
        exePath: r'C:\Games\foo.exe',
        exeName: 'foo.exe',
        profileName: 'foo.exe',
        profileWasPredefined: false,
        profileWasCreated: true,
        intendedValue: 0x10000000,
        previousValue: 0,
        driverVersion: '555.55',
        createdAt: now,
        updatedAt: now,
      ),
      ManagedRule(
        id: 2,
        exePath: r'C:\Games\bar.exe',
        exeName: 'bar.exe',
        profileName: 'bar.exe',
        profileWasPredefined: false,
        profileWasCreated: true,
        intendedValue: 0x10000000,
        previousValue: 0,
        driverVersion: '555.55',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await tester.pumpWidget(_wrap(
      const LeftPane(),
      overrides: [
        managedRulesProvider
            .overrideWith(() => _FakeManagedRulesNotifier(rules)),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('foo.exe'), findsWidgets);
    expect(find.text('bar.exe'), findsWidgets);
  });

  testWidgets('Search filter narrows the managed list', (tester) async {
    final now = DateTime(2024, 1, 1);
    final rules = [
      ManagedRule(
        id: 1,
        exePath: r'C:\Games\foo.exe',
        exeName: 'foo.exe',
        profileName: 'foo.exe',
        profileWasPredefined: false,
        profileWasCreated: true,
        intendedValue: 0x10000000,
        createdAt: now,
        updatedAt: now,
      ),
      ManagedRule(
        id: 2,
        exePath: r'C:\Games\bar.exe',
        exeName: 'bar.exe',
        profileName: 'bar.exe',
        profileWasPredefined: false,
        profileWasCreated: true,
        intendedValue: 0x10000000,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          managedRulesProvider
              .overrideWith(() => _FakeManagedRulesNotifier(rules)),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.darkTheme,
              home: const Scaffold(body: LeftPane()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    container.read(searchProvider.notifier).state = 'foo';
    await tester.pumpAndSettle();

    expect(find.text('foo.exe'), findsWidgets);
    expect(find.text('bar.exe'), findsNothing);
  });

  testWidgets('Detected tab shows pre-scan message', (tester) async {
    await tester.pumpWidget(_wrap(
      const LeftPane(),
      overrides: [
        managedRulesProvider.overrideWith(() => _FakeManagedRulesNotifier([])),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Detected'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Scan NVIDIA Profiles'),
      findsWidgets,
    );
  });
}
