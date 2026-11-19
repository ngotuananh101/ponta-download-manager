import 'dart:async';

import 'package:download_external/download_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

import 'external_tools_providers.dart';

class ExternalToolsSection extends ConsumerWidget {
  const ExternalToolsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(externalToolsControllerProvider);
    final busyState = ref.watch(externalToolsBusyProvider);
    final busy = busyState.asData?.value ?? true;
    final controller = ref.read(externalToolsControllerProvider.notifier);
    final working = state.checking || state.mutating;
    final statuses = {for (final status in state.snapshot?.tools ?? <ExternalToolStatus>[]) status.tool: status};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Updates are stored in your user data directory and used immediately. '
        'These actions are independent of Settings Save or Cancel.', style: AppTextSize.xs.textStyle()),
      const SizedBox(height: AppSpacing.s3),
      Align(alignment: Alignment.centerLeft, child: PdmDialogButton.secondary(
        label: state.checking ? 'Checking…' : 'Check now',
        onPressed: working ? null : () => unawaited(controller.checkNow()))),
      const SizedBox(height: AppSpacing.s4),
      for (final tool in ExternalTool.values) ...[
        _toolCard(context, tool, statuses[tool], state, controller, disabled: working || busy),
        const SizedBox(height: AppSpacing.s3),
      ],
      if (state.error != null) Text(state.error!, style: AppTextSize.xs.textStyle(color: Theme.of(context).colorScheme.error)),
      if (busy) Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        child: Text('Installation and removal are unavailable while a download, probe or tool update is running.',
          style: AppTextSize.xs.textStyle())),
      if (busyState.hasError) Text('Could not determine tool availability.', style: AppTextSize.xs.textStyle()),
      Text('Removing an update returns to the bundled or system tool. Bundled files are never changed.',
        style: AppTextSize.xs.textStyle()),
    ]);
  }

  Widget _toolCard(BuildContext context, ExternalTool tool, ExternalToolStatus? installed,
      ExternalToolsUiState state, ExternalToolsController controller, {required bool disabled}) {
    final colors = Theme.of(context).colorScheme;
    final status = installed == null ? (state.checking ? 'Checking versions…' : 'Not checked')
        : installed.hasUpdate ? '${installed.latest!.version} available'
        : installed.currentVersion == null ? (installed.origin == ExternalToolOrigin.missing ? 'Missing' : 'Unknown version')
        : installed.checkError != null ? 'Check failed' : installed.latest == null ? 'Not checked' : 'Up to date';
    final progress = state.progress?.tool == tool ? state.progress : null;
    return Container(
      key: Key('external-tool-${tool.name}'),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_label(tool), style: AppTextSize.sm.textStyle(weight: AppFontWeight.semibold)),
        const SizedBox(height: AppSpacing.s1),
        Text('${installed?.currentVersion ?? '—'} · ${installed?.origin.name ?? 'Unknown source'}',
          style: AppTextSize.xs.textStyle(color: colors.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.s2),
        Text(status, style: AppTextSize.xs.textStyle()),
        if (installed?.path != null) Text(installed!.path!, style: AppTextSize.xs.textStyle(color: colors.onSurfaceVariant), softWrap: true),
        if (installed?.checkError != null) Text(installed!.checkError!, style: AppTextSize.xs.textStyle(color: colors.error)),
        if (progress != null) ...[
          const SizedBox(height: AppSpacing.s2),
          Text('${progress.phase}'
            '${progress.totalBytes != null && progress.totalBytes! > 0 ? ' · ${(100 * progress.receivedBytes / progress.totalBytes!).floor()}%' : ''}',
            style: AppTextSize.xs.textStyle()),
          const SizedBox(height: AppSpacing.s2),
          const LinearProgressIndicator(),
        ],
        for (final result in state.results.where((result) => result.tool == tool)) ...[
          const SizedBox(height: AppSpacing.s2),
          Text(result.error ?? (result.changed ? 'Done' : 'No change'),
            style: AppTextSize.xs.textStyle(color: result.error == null ? null : colors.error)),
        ],
        const SizedBox(height: AppSpacing.s3),
        Wrap(spacing: AppSpacing.s2, runSpacing: AppSpacing.s2, children: [
          PdmDialogButton.primary(label: 'Update',
            onPressed: disabled || !(installed?.hasUpdate ?? false)
              ? null : () => unawaited(controller.installUpdate(tool))),
          PdmDialogButton.secondary(label: 'Remove downloaded version',
            onPressed: disabled || !(installed?.hasDownloadedCopy ?? false)
              ? null : () => unawaited(controller.removeDownloaded(tool))),
        ]),
      ]),
    );
  }

  static String _label(ExternalTool tool) => switch (tool) {
    ExternalTool.ffmpeg => 'ffmpeg', ExternalTool.ytDlp => 'yt-dlp', ExternalTool.quickjs => 'QuickJS',
  };
}
