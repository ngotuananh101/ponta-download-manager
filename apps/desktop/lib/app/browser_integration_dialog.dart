import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/core/services/browser_extension_installer.dart';
import 'package:pdm/core/services/browser_integration_service.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

/// Everything the browser-integration dialog shows: what each browser
/// profile looks like, plus the instructions that only a user can follow.
class BrowserIntegrationSnapshot {
  const BrowserIntegrationSnapshot({
    required this.statuses,
    this.manualSteps,
    this.hostPath,
    this.hostRegistration,
    this.setupReason,
  });

  final List<BrowserExtensionStatus> statuses;

  /// Platform-specific instructions for the browsers the app cannot set up
  /// itself (Windows Chrome/Edge, Firefox). Null when there are none.
  final String? manualSteps;

  /// The native host binary the manifests point at, for the "host" line.
  final String? hostPath;
  final BrowserIntegrationResult? hostRegistration;
  final String? setupReason;

  bool get allReady =>
      hostRegistration?.reason == null &&
      hostRegistration?.ok == true &&
      statuses.isNotEmpty &&
      statuses.every((s) => s.status == ExtensionStatus.installed);
}

/// Reads every Chromium profile and the native host state.
///
/// A FutureProvider so the dialog can refresh it: after the user quits a
/// browser and taps "Check again", the install runs once more and the list
/// re-renders from the new state.
final browserIntegrationStatusProvider =
    FutureProvider<BrowserIntegrationSnapshot>(
      (ref) => loadBrowserIntegrationSnapshot(),
    );

/// Runs the same real registration/setup used at startup. Overrides select
/// temporary paths/platforms in tests without replacing the service behavior.
Future<BrowserIntegrationSnapshot> loadBrowserIntegrationSnapshot({
  String? programDirectory,
  String? homeDir,
  String? configHome,
  String? localAppData,
  String? appData,
  bool? isWindows,
  bool? isReleaseBuild,
  bool Function(String profilePath)? isBrowserRunning,
  Map<String, String>? environment,
}) async {
  final windows = isWindows ?? Platform.isWindows;
  final env = environment ?? Platform.environment;
  String? nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
  final home =
      nonEmpty(homeDir) ?? nonEmpty(env[windows ? 'USERPROFILE' : 'HOME']);
  final config =
      nonEmpty(configHome) ??
      nonEmpty(env['XDG_CONFIG_HOME']) ??
      (home == null ? null : p.join(home, '.config'));
  final local =
      nonEmpty(localAppData) ??
      nonEmpty(env['LOCALAPPDATA']) ??
      (home == null ? null : p.windows.join(home, 'AppData', 'Local'));
  final roaming =
      nonEmpty(appData) ??
      nonEmpty(env['APPDATA']) ??
      (home == null ? null : p.windows.join(home, 'AppData', 'Roaming'));
  final base = programDirectory ?? p.dirname(Platform.resolvedExecutable);
  final paths = await BrowserIntegrationService.prepareBundlePaths(
    programDirectory: base,
    isWindows: windows,
    isReleaseBuild: isReleaseBuild,
    environment: environment,
  );
  final extensionDirectory = paths.extensionPath;
  final hostPath = paths.hostPath;
  final host = await BrowserIntegrationService.ensureNativeHosts(
    hostBinaryPath: hostPath,
    homeDir: home,
    configHome: config,
    localAppData: local,
    appData: roaming,
    environment: env,
    isWindows: windows,
    isReleaseBuild: isReleaseBuild,
  );
  final install = await BrowserExtensionInstaller.install(
    extensionDirectory: extensionDirectory,
    configHome: config,
    localAppData: local,
    isWindows: windows,
    environment: env,
    isReleaseBuild: isReleaseBuild,
    isBrowserRunning: isBrowserRunning,
  );
  final statuses = [
    ...install.alreadyInstalled,
    ...install.installed,
    ...install.skipped,
  ];
  statuses.sort(
    (a, b) => '${a.browserLabel}/${a.profilePath}'.compareTo(
      '${b.browserLabel}/${b.profilePath}',
    ),
  );
  return BrowserIntegrationSnapshot(
    statuses: statuses,
    hostPath: hostPath,
    hostRegistration: host,
    setupReason: install.reason,
    manualSteps: manualInstallSteps(extensionDirectory, isWindows: windows),
  );
}

/// The instructions for the browsers no unattended install exists for.
///
/// Windows needs a browser-controlled Load unpacked step. Firefox needs a
/// signed release for permanent installation; none is published yet.
String? manualInstallSteps(String extensionDirectory, {bool? isWindows}) {
  final chromium = (isWindows ?? Platform.isWindows)
      ? 'Open chrome://extensions (or edge://extensions), turn on Developer '
            'mode, then choose "Load unpacked" and pick $extensionDirectory.\n'
      : '';
  return '${chromium}Firefox: permanent installation requires a signed PDM add-on '
      '(not yet published). Temporary loading in about:debugging is for development.';
}

/// Shows the browser-integration dialog: which browsers have the extension,
/// which still need a step, and what to do about it.
Future<void> showBrowserIntegrationDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    builder: (context) => const BrowserIntegrationDialog(),
  );
}

/// The dialog body. Riverpod-backed so it works both inside the app and in a
/// widget test with an overridden status provider.
class BrowserIntegrationDialog extends ConsumerWidget {
  const BrowserIntegrationDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(browserIntegrationStatusProvider);
    return PdmDialog(
      title: 'Browser integration',
      width: 520,
      actions: [
        PdmDialogButton.secondary(
          label: 'Check again',
          onPressed: () => ref.invalidate(browserIntegrationStatusProvider),
        ),
        PdmDialogButton.primary(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Flexible(
        child: SingleChildScrollView(
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s5),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text(
              'Could not read the browser profiles: $error',
              style: AppTextSize.xs.textStyle(),
            ),
            data: (snapshot) => _body(context, snapshot),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, BrowserIntegrationSnapshot snapshot) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The extension sends downloads to PDM through the native host (com.ponta.pdm).',
          style: AppTextSize.xs.textStyle(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          snapshot.hostRegistration == null
              ? 'Native host registration has not been checked.'
              : snapshot.hostRegistration!.registered.isEmpty
              ? 'Native host is not registered: ${snapshot.hostRegistration!.reason ?? "no browser found"}'
              : 'Native host registered for ${snapshot.hostRegistration!.registered.map((b) => b.label).join(", ")}'
                    '${snapshot.hostRegistration!.reason == null ? "" : " — ${snapshot.hostRegistration!.reason}"}',
          style: AppTextSize.xs.textStyle(),
        ),
        if (snapshot.hostPath != null)
          Text(
            snapshot.hostPath!,
            style: AppTextSize.xs.textStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        if (snapshot.setupReason != null)
          Text(
            snapshot.setupReason!,
            style: AppTextSize.xs.textStyle(color: colorScheme.error),
          ),
        const SizedBox(height: AppSpacing.s4),
        if (snapshot.statuses.isEmpty)
          Text(
            'No Chromium browser profile was found. Run Chrome, Chromium, '
            'Edge, Brave or Vivaldi once, then choose "Check again".',
            style: AppTextSize.xs.textStyle(),
          )
        else
          for (final status in snapshot.statuses)
            _StatusRow(
              key: ValueKey(status.profilePath + status.browserId),
              status: status,
            ),
        if (snapshot.manualSteps != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            snapshot.manualSteps!,
            style: AppTextSize.xs.textStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({super.key, required this.status});

  final BrowserExtensionStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (status.status) {
      ExtensionStatus.installed => (
        Icons.check_circle_outline,
        'Extension is listed as enabled',
        colorScheme.primary,
      ),
      ExtensionStatus.notInstalled => (
        Icons.download_outlined,
        'Not installed — use Load unpacked if automatic setup is unavailable',
        colorScheme.onSurfaceVariant,
      ),
      ExtensionStatus.needsRepair => (
        Icons.error_outline,
        'Needs repair',
        colorScheme.error,
      ),
      ExtensionStatus.browserRunning => (
        Icons.pause_circle_outline,
        'Close the browser, then choose "Check again"',
        colorScheme.onSurfaceVariant,
      ),
      ExtensionStatus.needsUserAction => (
        Icons.open_in_new,
        'Needs one step from you',
        colorScheme.error,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.browserLabel,
                  style: AppTextSize.xs.textStyle(
                    weight: AppFontWeight.semibold,
                  ),
                ),
                Text(
                  p.basename(status.profilePath.replaceAll('\\', '/')),
                  style: AppTextSize.xs.textStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  status.reason == null ||
                          status.status == ExtensionStatus.installed
                      ? label
                      : '$label — ${status.reason}',
                  style: AppTextSize.xs.textStyle(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
