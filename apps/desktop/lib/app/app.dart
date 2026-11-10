import 'package:flutter/material.dart';
import 'package:pdm/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:pdm/shared/theme/app_theme.dart';

class PdmApp extends StatelessWidget {
  const PdmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ponta Download Manager',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // FDM is a dark-only app: always use the dark (FDM) theme so the
      // UI matches the Free Download Manager screenshot, whatever the
      // OS theme is. AppTheme.light is kept in code if a light theme is
      // ever wanted back.
      themeMode: ThemeMode.dark,
      home: const DownloadsScreen(),
    );
  }
}
