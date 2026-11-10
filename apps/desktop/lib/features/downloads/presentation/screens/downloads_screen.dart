import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pdm/app/app_header.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/presentation/download_table.dart';
import 'package:pdm/features/downloads/presentation/downloads_filtering.dart';
import 'package:pdm/features/downloads/presentation/drop_parsing.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/dashed_border.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoUrl = 'https://github.com/ngotuananh101/ponta-download-manager';

/// The home screen, laid out like Free Download Manager: a custom
/// title bar on top, a toolbar (select / sort / filter / Add / search /
/// menu), the download table (or a drop zone when empty), and a status
/// bar with the total speed at the bottom. The background is one
/// uniform color; the toolbar, the table and the status bar are not
/// separated by borders.
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
        _buildStatusBar(items, visible, totalSpeed),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          _toolbarPill(
            Checkbox(
              value: allSelected ? true : (someSelected ? null : false),
              tristate: true,
              onChanged: (_) => _toggleSelectAll(visible),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          _toolbarPill(
            PopupMenuButton<DownloadSort>(
              tooltip: 'Sort',
              padding: EdgeInsets.zero,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (context) => DownloadSort.values
                  .map(
                    (s) => PopupMenuItem(
                      value: s,
                      child: Text(_sortLabel(s)),
                    ),
                  )
                  .toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: AppSpacing.s1),
                  Text(_sortLabel(_sort)),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          _toolbarPill(
            PopupMenuButton<DownloadFilter>(
              tooltip: 'Filter',
              padding: EdgeInsets.zero,
              onSelected: (f) => setState(() => _filter = f),
              itemBuilder: (context) => DownloadFilter.values
                  .map(
                    (f) => PopupMenuItem(
                      value: f,
                      child: Text(_filterLabel(f)),
                    ),
                  )
                  .toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list, size: 18),
                  const SizedBox(width: AppSpacing.s1),
                  Text(_filterLabel(_filter)),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _showAddDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add download'),
          ),
          const SizedBox(width: AppSpacing.s2),
          // The search box is exactly as tall as the pills and the Add
          // button (36px) and at most 200px wide, so it sits snugly in
          // the right group instead of towering over the buttons. It
          // shrinks below 200px when the window is narrow rather than
          // overflowing the toolbar.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search in downloads...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
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

  /// A dark rounded pill behind a toolbar control, like FDM's
  /// dropdowns and search field.
  Widget _toolbarPill(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: child,
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

  // --- Body: table / drop zone ---

  Widget _buildBody(List<Download> items, List<Download> visible) {
    final Widget content;
    if (items.isEmpty &&
        _filter == DownloadFilter.all &&
        _query.isEmpty) {
      content = _buildDropZone();
    } else if (visible.isEmpty) {
      content = const Center(child: Text('No downloads match.'));
    } else {
      content = _buildTable(visible);
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

  /// The FDM table on top, the drop zone filling the rest below it.
  /// The rows area is capped so the drop zone always keeps at least
  /// 120px; with more rows than fit, the table scrolls.
  Widget _buildTable(List<Download> visible) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const headerHeight = 32.0;
        const rowHeight = 40.0;
        const minDropZoneHeight = 120.0;
        final available = constraints.maxHeight;
        final rowsHeight = (visible.length * rowHeight).clamp(
          0.0,
          (available - headerHeight - minDropZoneHeight).clamp(
            0.0,
            double.infinity,
          ),
        );
        return Column(
          children: [
            _buildTableHeader(),
            SizedBox(
              height: rowsHeight,
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) =>
                    _buildTableRow(visible[index]),
              ),
            ),
            Expanded(child: _buildDropZone()),
          ],
        );
      },
    );
  }

  Widget _buildTableHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = AppTextSize.xs.textStyle(
      weight: AppFontWeight.semibold,
      color: colorScheme.onSurfaceVariant,
    );
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      child: Row(
        children: [
          SizedBox(
            width: DownloadTableColumns.check,
            child: Text('#', style: labelStyle),
          ),
          Expanded(child: Text('Name', style: labelStyle)),
          SizedBox(
            width: DownloadTableColumns.size,
            child: Text('Size', style: labelStyle),
          ),
          SizedBox(
            width: DownloadTableColumns.status,
            child: Text('Status', style: labelStyle),
          ),
          const SizedBox(width: DownloadTableColumns.menu),
          SizedBox(
            width: DownloadTableColumns.speed,
            child: Text('Download', style: labelStyle),
          ),
          SizedBox(
            width: DownloadTableColumns.speed,
            child: Text('Upload', style: labelStyle),
          ),
          SizedBox(
            width: DownloadTableColumns.added,
            child: Text('Added', style: labelStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(Download item) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selected.contains(item.id);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: DownloadTableColumns.check,
            child: Center(
              child: Checkbox(
                value: selected,
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(item.id);
                  } else {
                    _selected.remove(item.id);
                  }
                }),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    item.fileName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: DownloadTableColumns.size,
            child: Text(downloadSizeText(item)),
          ),
          SizedBox(
            width: DownloadTableColumns.status,
            child: Text(
              downloadStatusText(item),
              style: TextStyle(
                color: downloadStatusColor(colorScheme, item.state),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: DownloadTableColumns.menu,
            child: _buildRowMenu(item),
          ),
          SizedBox(
            width: DownloadTableColumns.speed,
            child: Text('${formatBytes(item.bytesPerSecond)}/s'),
          ),
          SizedBox(
            width: DownloadTableColumns.speed,
            child: const Text('0 B/s'),
          ),
          SizedBox(
            width: DownloadTableColumns.added,
            child: Text(
              formatAdded(item.createdAt),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// The `⋮` row menu (Pause / Resume / Retry / Cancel, by state).
  /// Completed and cancelled downloads have no row actions.
  Widget _buildRowMenu(Download item) {
    switch (item.state) {
      case DownloadState.completed:
      case DownloadState.cancelled:
        return const SizedBox.shrink();
      case DownloadState.downloading:
      case DownloadState.queued:
      case DownloadState.paused:
      case DownloadState.failed:
        break;
    }
    return Center(
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        tooltip: 'Actions',
        padding: EdgeInsets.zero,
        onSelected: (value) => _onRowAction(item, value),
        itemBuilder: (context) {
          final entries = <PopupMenuEntry<String>>[];
          switch (item.state) {
            case DownloadState.downloading:
            case DownloadState.queued:
              entries.add(
                const PopupMenuItem(value: 'pause', child: Text('Pause')),
              );
              entries.add(
                const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
              );
            case DownloadState.paused:
              entries.add(
                const PopupMenuItem(value: 'resume', child: Text('Resume')),
              );
              entries.add(
                const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
              );
            case DownloadState.failed:
              entries.add(
                const PopupMenuItem(value: 'retry', child: Text('Retry')),
              );
              entries.add(
                const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
              );
            case DownloadState.completed:
            case DownloadState.cancelled:
              break;
          }
          return entries;
        },
      ),
    );
  }

  Future<void> _onRowAction(Download item, String action) async {
    final actions = ref.read(downloadsActionsProvider);
    Future<Either<Failure, Unit>> Function() call;
    switch (action) {
      case 'pause':
        call = () => actions.pauseDownload(item.id);
      case 'resume':
        call = () => actions.resumeDownload(item.id);
      case 'cancel':
        call = () => actions.cancelDownload(item.id);
      case 'retry':
        call = () => actions.retryDownload(item.id);
      default:
        return;
    }
    final result = await call();
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

  Widget _buildStatusBar(
    List<Download> items,
    List<Download> visible,
    int totalSpeed,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusFile = _statusFile(visible);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      color: colorScheme.surface,
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
          Text('${formatBytes(totalSpeed)}/s'),
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
          const SizedBox(width: AppSpacing.s4),
          _buildSupportButton(),
          const Spacer(),
          if (statusFile != null)
            Flexible(
              child: Text(
                statusFile.fileName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  /// The file named at the far right of the status bar: the selected
  /// one, else the newest download.
  Download? _statusFile(List<Download> visible) {
    if (_selected.isNotEmpty) {
      final selected =
          visible.where((d) => _selected.contains(d.id)).toList();
      if (selected.isNotEmpty) return selected.first;
    }
    return visible.isNotEmpty ? visible.first : null;
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
              ? colorScheme.surfaceContainerHighest
              : colorScheme.primary,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              size: 14,
              color: isOff ? colorScheme.onSurface : colorScheme.onPrimary,
            ),
            const SizedBox(width: AppSpacing.s1),
            Text(
              isOff ? 'OFF' : 'ON',
              style: AppTextSize.xs.textStyle(
                weight: AppFontWeight.semibold,
                color: isOff ? colorScheme.onSurface : colorScheme.onPrimary,
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
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed,
            size: 14,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            'HIGH',
            style: AppTextSize.xs.textStyle(
              weight: AppFontWeight.semibold,
              color: colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportButton() {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: _openSupport,
      icon: const Icon(Icons.favorite_outline, size: 18),
      label: const Text('Support the project'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.secondary,
        side: BorderSide(color: colorScheme.secondary),
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
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
