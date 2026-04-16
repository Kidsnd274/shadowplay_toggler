import 'package:flutter/material.dart';
import 'constants/app_constants.dart';
import 'constants/app_theme.dart';
import 'screens/home_screen.dart';

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
      home: const HomeScreen(),
    );
  }
}
