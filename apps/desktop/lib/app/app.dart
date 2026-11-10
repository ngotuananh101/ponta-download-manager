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
      home: const DownloadsScreen(),
    );
  }
}
