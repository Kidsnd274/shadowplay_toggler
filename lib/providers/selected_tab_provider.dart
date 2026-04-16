import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LeftPaneTab { managed, detected, defaults }

final selectedTabProvider = StateProvider<LeftPaneTab>(
  (ref) => LeftPaneTab.managed,
);
