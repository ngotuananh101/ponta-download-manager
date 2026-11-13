import 'package:material_ui/material_ui.dart';
import 'package:pdm/shared/theme/app_theme.dart';

/// Shown when the app fails to start (engine, IPC server, or window
/// setup throws before the first frame) instead of dying silently.
/// The message is selectable so it can be copied into a bug report.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ponta Download Manager',
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ponta Download Manager',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Không thể khởi động ứng dụng.'),
                const SizedBox(height: 8),
                SelectableText(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
