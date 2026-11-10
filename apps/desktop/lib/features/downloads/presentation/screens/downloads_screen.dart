import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pdm/app/app_header.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/presentation/downloads_filtering.dart';
import 'package:pdm/features/downloads/presentation/drop_parsing.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/dashed_border.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoUrl = 'https://github.com/ngotuananh101/ponta-download-manager';

/// The home screen, laid out like Free Download Manager: a custom
/// title bar on top, a toolbar (select / sort / filter / Add / search /
/// menu), the download list (or a drop zone when empty), and a status
/// bar with the total speed at the bottom.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  DownloadSort _sort = DownloadSort.newest;
  DownloadFilter _filter = DownloadFilter.all;
  String _query = '';
  final _searchController = TextEditingController();
  final _selected = <String>{};
  bool _dragOver = false;

  /// Whether the global toggle is OFF (all active downloads paused).
  bool _globalPaused = false;

  /// The downloads this toggle paused, so turning it back ON resumes
  /// exactly those and not ones the user paused by hand.
  Set<String> _globalPausedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadsProvider);
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: downloads.when(
              data: (items) => _buildContent(items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<Download> items) {
    final visible = visibleDownloads(
      items,
      sort: _sort,
      filter: _filter,
      query: _query,
    );
    final totalSpeed = items
        .where((d) => d.state == DownloadState.downloading)
        .fold<int>(0, (sum, d) => sum + d.bytesPerSecond);
    return Column(
      children: [
        _buildToolbar(visible),
        if (_selected.isNotEmpty) _buildBulkBar(),
        Expanded(child: _buildBody(items, visible)),
        _buildStatusBar(items, totalSpeed),
      ],
    );
  }

  // --- Toolbar ---

  Widget _buildToolbar(List<Download> visible) {
    final allSelected =
        visible.isNotEmpty && visible.every((d) => _selected.contains(d.id));
    final someSelected = visible.any((d) => _selected.contains(d.id));
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected ? true : (someSelected ? null : false),
            tristate: true,
            onChanged: (_) => _toggleSelectAll(visible),
          ),
          const Icon(Icons.sort, size: 18),
          const SizedBox(width: AppSpacing.s1),
          DropdownButton<DownloadSort>(
            value: _sort,
            underline: const SizedBox.shrink(),
            items: DownloadSort.values
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(_sortLabel(s)),
                  ),
                )
                .toList(),
            onChanged: (s) {
              if (s != null) setState(() => _sort = s);
            },
          ),
          const SizedBox(width: AppSpacing.s2),
          const Icon(Icons.filter_list, size: 18),
          const SizedBox(width: AppSpacing.s1),
          DropdownButton<DownloadFilter>(
            value: _filter,
            underline: const SizedBox.shrink(),
            items: DownloadFilter.values
                .map(
                  (f) => DropdownMenuItem(
                    value: f,
                    child: Text(_filterLabel(f)),
                  ),
                )
                .toList(),
            onChanged: (f) {
              if (f != null) setState(() => _filter = f);
            },
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _showAddDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add download'),
          ),
          const SizedBox(width: AppSpacing.s3),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search in downloads...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onSelected: _onMenuSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'pause-all', child: Text('Pause all')),
              PopupMenuItem(value: 'resume-all', child: Text('Resume all')),
            ],
          ),
        ],
      ),
    );
  }

  String _sortLabel(DownloadSort sort) {
    switch (sort) {
      case DownloadSort.newest:
        return 'Newest';
      case DownloadSort.oldest:
        return 'Oldest';
      case DownloadSort.name:
        return 'Name';
      case DownloadSort.size:
        return 'Size';
    }
  }

  String _filterLabel(DownloadFilter filter) {
    switch (filter) {
      case DownloadFilter.all:
        return 'All files';
      case DownloadFilter.downloading:
        return 'Downloading';
      case DownloadFilter.queued:
        return 'Queued';
      case DownloadFilter.paused:
        return 'Paused';
      case DownloadFilter.completed:
        return 'Completed';
      case DownloadFilter.failed:
        return 'Failed';
      case DownloadFilter.cancelled:
        return 'Cancelled';
    }
  }

  void _toggleSelectAll(List<Download> visible) {
    setState(() {
      final allSelected =
          visible.isNotEmpty && visible.every((d) => _selected.contains(d.id));
      if (allSelected) {
        for (final d in visible) {
          _selected.remove(d.id);
        }
      } else {
        for (final d in visible) {
          _selected.add(d.id);
        }
      }
    });
  }

  Future<void> _onMenuSelected(String value) async {
    final items = ref.read(downloadsProvider).value ?? const [];
    switch (value) {
      case 'pause-all':
        await _pauseActive(items);
      case 'resume-all':
        await _resumePaused(items);
    }
  }

  Future<void> _pauseActive(List<Download> items) async {
    final actions = ref.read(downloadsActionsProvider);
    for (final d in items) {
      if (d.state == DownloadState.downloading ||
          d.state == DownloadState.queued) {
        await actions.pauseDownload(d.id);
      }
    }
  }

  Future<void> _resumePaused(List<Download> items) async {
    final actions = ref.read(downloadsActionsProvider);
    for (final d in items) {
      if (d.state == DownloadState.paused) {
        await actions.resumeDownload(d.id);
      }
    }
  }

  // --- Bulk selection bar ---

  Widget _buildBulkBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text('${_selected.length} selected'),
          const SizedBox(width: AppSpacing.s3),
          TextButton.icon(
            onPressed: () => _bulkPause(),
            icon: const Icon(Icons.pause, size: 18),
            label: const Text('Pause'),
          ),
          TextButton.icon(
            onPressed: () => _bulkCancel(),
            icon: const Icon(Icons.cancel, size: 18),
            label: const Text('Cancel'),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear selection',
            onPressed: () => setState(() => _selected.clear()),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkPause() async {
    final actions = ref.read(downloadsActionsProvider);
    final ids = _selected.toList();
    for (final id in ids) {
      await actions.pauseDownload(id);
    }
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _bulkCancel() async {
    final actions = ref.read(downloadsActionsProvider);
    final ids = _selected.toList();
    for (final id in ids) {
      await actions.cancelDownload(id);
    }
    if (mounted) setState(() => _selected.clear());
  }

  // --- Body: list / drop zone ---

  Widget _buildBody(List<Download> items, List<Download> visible) {
    final Widget content;
    if (items.isEmpty &&
        _filter == DownloadFilter.all &&
        _query.isEmpty) {
      content = _buildDropZone();
    } else if (visible.isEmpty) {
      content = const Center(child: Text('No downloads match.'));
    } else {
      content = ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final item = visible[index];
          return _DownloadRow(
            item: item,
            selected: _selected.contains(item.id),
            onSelectedChanged: (value) => setState(() {
              if (value == true) {
                _selected.add(item.id);
              } else {
                _selected.remove(item.id);
              }
            }),
          );
        },
      );
    }

    final stack = Stack(
      children: [
        content,
        if (_dragOver)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.primary.withValues(
                alpha: 0.08,
              ),
              child: const Center(
                child: Text('Drop to add download'),
              ),
            ),
          ),
      ],
    );
    // The native library behind DropTarget is only bundled in a built
    // app; in a widget test it is absent, so the target is skipped
    // there (see dropTargetEnabledProvider).
    if (!ref.watch(dropTargetEnabledProvider)) return stack;
    return DropTarget(
      onEnter: (_) => setState(() => _dragOver = true),
      onLeave: () => setState(() => _dragOver = false),
      onDrop: _onDrop,
      child: stack,
    );
  }

  Widget _buildDropZone() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: DashedBorder(
        color: _dragOver ? colorScheme.primary : colorScheme.outline,
        radius: AppRadius.lg,
        child: InkWell(
          onTap: () => _showAddDialog(),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mouse,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.s2),
                Text(
                  'Drag-and-drop URL or torrent file',
                  style: AppTextSize.base.textStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onDrop(DropDetails details) async {
    setState(() => _dragOver = false);
    final result = parseDroppedContent(
      strings: details.items.whereType<DropStringItem>().toList(),
      fileNames: details.items
          .whereType<DropFileItem>()
          .map((f) => f.name)
          .toList(),
    );
    if (result.hasTorrent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent chưa hỗ trợ.')),
      );
    } else if (result.hasOtherFile &&
        result.urls.isEmpty &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ hỗ trợ kéo-thả URL.')),
      );
    }
    final actions = ref.read(downloadsActionsProvider);
    for (final url in result.urls) {
      final addResult = await actions.addDownload(url);
      addResult.fold(
        (failure) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(failure.message)));
          }
        },
        (_) {},
      );
    }
  }

  // --- Status bar ---

  Widget _buildStatusBar(List<Download> items, int totalSpeed) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _buildGlobalToggle(items),
          const SizedBox(width: AppSpacing.s4),
          Icon(
            Icons.arrow_downward,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text('${_formatBytes(totalSpeed)}/s'),
          const SizedBox(width: AppSpacing.s4),
          Icon(
            Icons.arrow_upward,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s1),
          const Text('0 B/s'),
          const SizedBox(width: AppSpacing.s4),
          _buildHighBadge(),
          const Spacer(),
          _buildSupportButton(),
        ],
      ),
    );
  }

  Widget _buildGlobalToggle(List<Download> items) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOff = _globalPaused;
    return InkWell(
      onTap: () => _toggleGlobalPause(items),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: isOff
              ? colorScheme.errorContainer
              : colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.power_settings_new,
              size: 14,
              color: isOff
                  ? colorScheme.onErrorContainer
                  : colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: AppSpacing.s1),
            Text(
              isOff ? 'OFF' : 'ON',
              style: AppTextSize.xs.textStyle(
                weight: AppFontWeight.semibold,
                color: isOff
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleGlobalPause(List<Download> items) async {
    final actions = ref.read(downloadsActionsProvider);
    if (!_globalPaused) {
      final active = items
          .where(
            (d) =>
                d.state == DownloadState.downloading ||
                d.state == DownloadState.queued,
          )
          .map((d) => d.id)
          .toList();
      for (final id in active) {
        await actions.pauseDownload(id);
      }
      if (mounted) {
        setState(() {
          _globalPaused = true;
          _globalPausedIds = active.toSet();
        });
      }
    } else {
      final ids = _globalPausedIds.toList();
      for (final id in ids) {
        await actions.resumeDownload(id);
      }
      if (mounted) {
        setState(() {
          _globalPaused = false;
          _globalPausedIds = {};
        });
      }
    }
  }

  Widget _buildHighBadge() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed,
            size: 14,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            'HIGH',
            style: AppTextSize.xs.textStyle(
              weight: AppFontWeight.semibold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportButton() {
    return TextButton.icon(
      onPressed: _openSupport,
      icon: const Icon(Icons.favorite_outline, size: 18),
      label: const Text('Support the project'),
    );
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse(_repoUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không mở được $_repoUrl')),
      );
    }
  }

  // --- Add download dialog ---

  Future<void> _showAddDialog() async {
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
          if (mounted) {
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
  const _DownloadRow({
    required this.item,
    required this.selected,
    required this.onSelectedChanged,
  });

  final Download item;
  final bool selected;
  final ValueChanged<bool?> onSelectedChanged;

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
      leading: Checkbox(value: selected, onChanged: onSelectedChanged),
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
