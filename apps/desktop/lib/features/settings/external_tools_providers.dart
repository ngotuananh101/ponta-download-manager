import 'package:download_external/download_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdm/core/services/external_tools_service.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';

class ExternalToolsUiState {
  const ExternalToolsUiState({this.snapshot, this.checking = false, this.mutating = false,
    this.results = const [], this.progress, this.error});

  final ExternalToolsSnapshot? snapshot;
  final bool checking;
  final bool mutating;
  final List<ToolMutationResult> results;
  final ToolUpdateProgress? progress;
  final String? error;
  bool get hasUpdates => snapshot?.hasUpdates ?? false;
}

final externalToolsControllerProvider = NotifierProvider<ExternalToolsController, ExternalToolsUiState>(ExternalToolsController.new);
final externalToolsStartupCheckProvider = FutureProvider<void>((ref) =>
  // Defer state writes until after the first widget build.
  Future<void>(() => ref.read(externalToolsControllerProvider.notifier).checkNow()));
final externalToolsBusyProvider = StreamProvider<bool>((ref) =>
  ref.watch(downloadDatasourceProvider).externalToolsBusyChanges);

class ExternalToolsController extends Notifier<ExternalToolsUiState> {
  @override
  ExternalToolsUiState build() => const ExternalToolsUiState();

  Future<void> checkNow() async {
    if (state.checking || state.mutating) return;
    state = ExternalToolsUiState(snapshot: state.snapshot, checking: true);
    try {
      final snapshot = await ref.read(externalToolsUpdateServiceProvider).checkAll();
      if (ref.mounted) state = ExternalToolsUiState(snapshot: snapshot);
    } catch (error) {
      if (ref.mounted) state = ExternalToolsUiState(snapshot: state.snapshot, error: error.toString());
    }
  }

  Future<void> installUpdate(ExternalTool tool) => _mutate(tool: tool, remove: false);
  Future<void> removeDownloaded(ExternalTool tool) => _mutate(tool: tool, remove: true);

  Future<void> _mutate({required ExternalTool tool, required bool remove}) async {
    if (state.checking || state.mutating) return;
    final previous = state.snapshot;
    if (!remove && previous == null) return;
    state = ExternalToolsUiState(snapshot: previous, mutating: true);
    try {
      final datasource = ref.read(downloadDatasourceProvider);
      final service = ref.read(externalToolsUpdateServiceProvider);
      await datasource.withExternalToolsMaintenance((refresh) async {
        final results = remove ? await service.removeDownloaded(tool: tool)
            : await service.installUpdates(previous!, tool: tool, onProgress: (progress) {
                if (ref.mounted) {
                  state = ExternalToolsUiState(snapshot: previous,
                    mutating: true, progress: progress);
                }
              });
        // Refresh even if local inspection later fails, before releasing gate.
        if (results.any((result) => result.changed)) await refresh();
        final snapshot = await service.inspectInstalled(previous ?? ExternalToolsSnapshot(const []));
        if (ref.mounted) state = ExternalToolsUiState(snapshot: snapshot, results: results);
      });
    } catch (error) {
      if (ref.mounted) state = ExternalToolsUiState(snapshot: previous, error: error.toString());
    }
  }
}
