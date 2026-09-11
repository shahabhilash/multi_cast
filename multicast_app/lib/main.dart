import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/main_shell_screen.dart';

void main() async {
  runApp(
    const ProviderScope(
      child: MultiCastApp(),
    ),
  );
}

class MultiCastApp extends StatelessWidget {
  const MultiCastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MultiCast',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const MainShellScreen(),
    );
  }
}
