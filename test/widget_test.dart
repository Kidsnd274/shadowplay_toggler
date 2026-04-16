import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadowplay_toggler/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ShadowPlayTogglerApp()),
    );

    expect(find.text('ShadowPlay Toggler'), findsOneWidget);
    expect(find.text('NVAPI: Uninitialized'), findsOneWidget);
  });
}
