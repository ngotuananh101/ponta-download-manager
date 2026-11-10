import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/shared/theme/app_tokens.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: downloads.when(
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

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.item});

  final Download item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A total of -1 means the server never sent a Content-Length, so
    // there is no percentage to show: an indeterminate bar while it
    // runs, a full bar once it completed, and no "-1 B (0%)" text.
    final hasTotal = item.totalBytes > 0;
    final double? barValue = hasTotal
        ? item.progress
        : item.state == DownloadState.completed
            ? 1
            : item.state == DownloadState.downloading ||
                    item.state == DownloadState.queued
                ? null
                : 0;
    final status = hasTotal
        ? '${_formatBytes(item.downloadedBytes)} / '
            '${_formatBytes(item.totalBytes)} '
            '(${(item.progress * 100).round()}%) · ${item.state.name}'
        : '${_formatBytes(item.downloadedBytes)} (total unknown) · '
            '${item.state.name}';
    return ListTile(
      title: Text(item.fileName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.url),
          const SizedBox(height: AppSpacing.s1),
          LinearProgressIndicator(value: barValue),
          const SizedBox(height: AppSpacing.s1),
          Text(status),
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
