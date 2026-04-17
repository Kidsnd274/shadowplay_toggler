import 'package:flutter/material.dart';
import 'constants/app_constants.dart';
import 'constants/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'widgets/error_boundary.dart';

class ShadowPlayTogglerApp extends StatelessWidget {
  const ShadowPlayTogglerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      scaffoldMessengerKey: NotificationService.messengerKey,
      builder: (context, child) {
        return ErrorBoundary(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeScreen(),
    );
  }
}
