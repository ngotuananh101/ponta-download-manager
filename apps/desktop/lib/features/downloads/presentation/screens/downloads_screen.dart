import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    final connected = ref.watch(engineConnectedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: Column(
        children: [
          connected.when(
            data: (isConnected) => isConnected
                ? const SizedBox.shrink()
                : const _DisconnectedBanner(),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          Expanded(
            child: downloads.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('No downloads yet.'));
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return _DownloadRow(item: items[index]);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add download'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'https://...'),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      final result =
          await ref.read(downloadsActionsProvider).addDownload(url);
      result.fold(
        (failure) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(failure.message)));
          }
        },
        (_) {},
      );
    }
  }
}

class _DisconnectedBanner extends ConsumerWidget {
  const _DisconnectedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Text('Engine not running — retrying…')),
          TextButton(
            onPressed: () => ref.invalidate(downloadDatasourceProvider),
            child: const Text('Retry now'),
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.item});

  final Download item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(item.fileName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.url),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: item.progress),
          const SizedBox(height: 4),
          Text(
            '${_formatBytes(item.downloadedBytes)} / '
            '${_formatBytes(item.totalBytes)} '
            '(${(item.progress * 100).round()}%) · ${item.state.name}',
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: _actions(context, ref),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final actions = ref.read(downloadsActionsProvider);

    Future<void> run(Future<Either<Failure, Unit>> Function() call) async {
      final result = await call();
      result.fold(
        (failure) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(failure.message)));
          }
        },
        (_) {},
      );
    }

    switch (item.state) {
      case DownloadState.downloading:
      case DownloadState.queued:
        return [
          IconButton(
            icon: const Icon(Icons.pause),
            tooltip: 'Pause',
            onPressed: () => run(() => actions.pauseDownload(item.id)),
          ),
          IconButton(
            icon: const Icon(Icons.cancel),
            tooltip: 'Cancel',
            onPressed: () => run(() => actions.cancelDownload(item.id)),
          ),
        ];
      case DownloadState.paused:
        return [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Resume',
            onPressed: () => run(() => actions.resumeDownload(item.id)),
          ),
          IconButton(
            icon: const Icon(Icons.cancel),
            tooltip: 'Cancel',
            onPressed: () => run(() => actions.cancelDownload(item.id)),
          ),
        ];
      case DownloadState.failed:
        return [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Retry',
            onPressed: () => run(() => actions.retryDownload(item.id)),
          ),
          IconButton(
            icon: const Icon(Icons.cancel),
            tooltip: 'Cancel',
            onPressed: () => run(() => actions.cancelDownload(item.id)),
          ),
        ];
      case DownloadState.completed:
      case DownloadState.cancelled:
        return const [];
    }
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GiB';
}
