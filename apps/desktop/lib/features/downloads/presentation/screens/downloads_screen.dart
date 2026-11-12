import 'package:download_api/download_api.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/app/app_header.dart';
import 'package:pdm/app/snail_icon.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/presentation/download_details_panel.dart';
import 'package:pdm/features/downloads/presentation/download_table.dart';
import 'package:pdm/features/downloads/presentation/downloads_filtering.dart';
import 'package:pdm/features/downloads/presentation/drop_parsing.dart';
import 'package:pdm/features/downloads/presentation/file_conflict_dialog.dart';
import 'package:pdm/features/downloads/presentation/new_download_dialog.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/shared/theme/app_theme.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';
import 'package:pdm/shared/widgets/dashed_border.dart';
import 'package:pdm_engine/pdm_engine.dart';

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

  /// Whether the details panel for the selected download is open.
  bool _detailsOpen = false;

  /// Snail mode: when ON, the global download speed is capped at
  /// [_snailModeBytesPerSecond] to keep the connection continuous
  /// with the server. OFF means unlimited.
  static const _snailModeBytesPerSecond = 8192;

  /// Whether snail mode is currently ON.
  bool _snailMode = false;

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
    final statusFile = _statusFile(visible);
    return Column(
      children: [
        _buildToolbar(visible),
        if (_selected.isNotEmpty) _buildBulkBar(),
        Expanded(child: _buildBody(items, visible)),
        if (_detailsOpen && statusFile != null)
          DownloadDetailsPanel(
            download: statusFile,
            onClose: () => setState(() => _detailsOpen = false),
          ),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _toolbarPill(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: allSelected ? true : (someSelected ? null : false),
                  tristate: true,
                  onChanged: (_) => _toggleSelectAll(visible),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                SizedBox(
                  width: 20,
                  height: 36,
                  child: PopupMenuButton<_SelectBy>(
                    tooltip: 'Select',
                    padding: EdgeInsets.zero,
                    onSelected: (option) => _selectBy(option, visible),
                    itemBuilder: (context) => [
                      _menuItem(_SelectBy.all, 'All'),
                      _menuItem(_SelectBy.downloadsOnly, 'Downloads only'),
                      _menuItem(_SelectBy.uploadsOnly, 'Uploads only'),
                      _menuItem(_SelectBy.completed, 'Completed'),
                      _menuItem(_SelectBy.stopped, 'Stopped'),
                    ],
                    // An explicit child (not the icon form): the icon
                    // form builds an IconButton whose 48px minimum
                    // would overflow the 36px pill.
                    child: const Center(
                      child: Icon(Icons.arrow_drop_down, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          _toolbarPill(
            PopupMenuButton<DownloadSort>(
              tooltip: 'Sort',
              padding: EdgeInsets.zero,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (context) => DownloadSort.values
                  .map((s) => _menuItem(s, _sortLabel(s)))
                  .toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: AppSpacing.s1),
                  Text(
                    _sortLabel(_sort),
                    style: AppTextSize.xs.textStyle(
                      color: const Color(0xFFF4F5F5),
                    ),
                  ),
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
              itemBuilder: (context) => [
                for (final f in DownloadFilter.values) ...[
                  if (f == DownloadFilter.torrent)
                    const PopupMenuDivider(),
                  _menuItem(f, _filterLabel(f)),
                ],
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list, size: 18),
                  const SizedBox(width: AppSpacing.s1),
                  Text(
                    _filterLabel(_filter),
                    style: AppTextSize.xs.textStyle(
                      color: const Color(0xFFF4F5F5),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          const Spacer(),
          // A SizedBox forces the height: relying on the button
          // style's minimumSize alone left the button short in the
          // rebuilt app even though the widget test read 36px.
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              onPressed: () => _showAddDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                'Add download',
                style: AppTextSize.xs.textStyle(weight: AppFontWeight.semibold),
              ),
              style: AppTheme.buttonStyle(AppButtonSize.sm).copyWith(
                // The default padded tap target forces a 48px minimum;
                // shrinkWrap lets the button fit in the 36px box.
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          // The search box is exactly as tall as the pills and the Add
          // button (36px) and 200px wide. It is a fixed-size box, not a
          // flex child: the Spacer above is the only flex child, so it
          // takes all the free space and pushes Add / search / menu
          // flush to the right edge. (A Flexible search shared the free
          // space with the Spacer, and the leftover past its 200px cap
          // sat empty after the menu button.)
          // The pill is drawn by the Container (like the toolbar
          // pills), not by the TextField: a TextField's own filled
          // decoration measured taller than 36px and off-center in the
          // rebuilt app even though the SizedBox was 36px.
          Container(
            width: 240,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: AppTextSize.xs.textStyle(),
              // The text and prefix icon must sit on the pill's center
              // line: isDense + vertical contentPadding top-aligned
              // them ~4px high in the rebuilt app.
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                hintText: 'Search in downloads...',
                prefixIcon: Icon(Icons.search, size: 18),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.s2),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          SizedBox(
            width: 36,
            height: 36,
            child: PopupMenuButton<String>(
              tooltip: 'Menu',
              padding: EdgeInsets.zero,
              onSelected: _onMenuSelected,
              itemBuilder: (context) => [
                _menuItem('pause-all', 'Pause all'),
                _menuItem('resume-all', 'Resume all'),
              ],
              // An explicit child (not the icon form): the icon form
              // builds an IconButton whose 48px minimum survives both
              // a SizedBox wrapper and PopupMenuButton.constraints.
              child: const Center(child: Icon(Icons.menu)),
            ),
          ),
        ],
      ),
    );
  }

  /// A dark rounded pill behind a toolbar control, like FDM's
  /// dropdowns and search field. Every pill is exactly 36px tall (the
  /// search box height) with its content centered, so all toolbar
  /// items share one top edge, one center and one bottom edge.
  Widget _toolbarPill(Widget child) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: child,
    );
  }

  // One menu row for the toolbar selects and the per-row action
  // menu: xs text like the table rows, in a compact 32px row instead
  // of the 48px PopupMenuItem default.
  PopupMenuItem<T> _menuItem<T>(T value, String label) {
    return PopupMenuItem<T>(
      value: value,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      child: Text(label, style: AppTextSize.xs.textStyle()),
    );
  }

  String _sortLabel(DownloadSort sort) {
    switch (sort) {
      case DownloadSort.newest:
        return 'Newest';
      case DownloadSort.oldest:
        return 'Old';
      case DownloadSort.nameAsc:
        return 'A-Z';
      case DownloadSort.nameDesc:
        return 'Z-A';
      case DownloadSort.sizeDesc:
        return 'By size: large';
      case DownloadSort.sizeAsc:
        return 'By size: small';
      case DownloadSort.statusAsc:
        return 'By status: ascending';
      case DownloadSort.statusDesc:
        return 'By status: descending';
    }
  }

  String _filterLabel(DownloadFilter filter) {
    switch (filter) {
      case DownloadFilter.all:
        return 'All files';
      case DownloadFilter.missing:
        return 'Missing Files';
      case DownloadFilter.active:
        return 'Active';
      case DownloadFilter.completed:
        return 'Completed';
      case DownloadFilter.torrent:
        return 'Torrent';
      case DownloadFilter.video:
        return 'Video';
      case DownloadFilter.music:
        return 'Music';
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

  /// Selects exactly the visible rows matching [option] (FDM's
  /// select dropdown). "Downloads only" selects all visible rows,
  /// because every row is a download; "Uploads only" selects nothing,
  /// because PDM has no uploads; "Stopped" is paused, cancelled or
  /// failed.
  void _selectBy(_SelectBy option, List<Download> visible) {
    setState(() {
      _selected.clear();
      switch (option) {
        case _SelectBy.all:
        case _SelectBy.downloadsOnly:
          for (final d in visible) {
            _selected.add(d.id);
          }
        case _SelectBy.uploadsOnly:
          break;
        case _SelectBy.completed:
          for (final d in visible) {
            if (d.state == DownloadState.completed) {
              _selected.add(d.id);
            }
          }
        case _SelectBy.stopped:
          for (final d in visible) {
            if (d.state == DownloadState.paused ||
                d.state == DownloadState.cancelled ||
                d.state == DownloadState.failed) {
              _selected.add(d.id);
            }
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
          Text(
            '${_selected.length} selected',
            style: AppTextSize.xs.textStyle(),
          ),
          const SizedBox(width: AppSpacing.s3),
          TextButton.icon(
            onPressed: () => _bulkPause(),
            icon: const Icon(Icons.pause, size: 18),
            label: Text('Pause', style: AppTextSize.xs.textStyle()),
          ),
          TextButton.icon(
            onPressed: () => _bulkCancel(),
            icon: const Icon(Icons.cancel, size: 18),
            label: Text('Cancel', style: AppTextSize.xs.textStyle()),
          ),
          TextButton.icon(
            onPressed: () => _bulkDelete(),
            icon: const Icon(Icons.delete, size: 18),
            label: Text('Delete', style: AppTextSize.xs.textStyle()),
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

  Future<void> _bulkDelete() async {
    final actions = ref.read(downloadsActionsProvider);
    final ids = _selected.toList();
    for (final id in ids) {
      await actions.deleteDownload(id);
    }
    if (mounted) setState(() => _selected.clear());
  }

  // --- Body: table / drop zone ---

  Widget _buildBody(List<Download> items, List<Download> visible) {
    final Widget content;
    if (items.isEmpty && _filter == DownloadFilter.all && _query.isEmpty) {
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
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              child: const Center(child: Text('Drop to add download')),
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
  /// The zone shows only when it gets its 120px without squeezing the
  /// rows: either the rows fit fully with 120px left over, or there
  /// are so many rows they overflow the body on their own (then the
  /// rows scroll under a 120px zone, as before). Otherwise the zone
  /// hides and the rows keep their full height: a 120px strip under
  /// rows capped to make room for it helps nobody.
  Widget _buildTable(List<Download> visible) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const headerHeight = 32.0;
        const rowHeight = 40.0;
        const minDropZoneHeight = 120.0;
        final available = constraints.maxHeight;
        final bodyAfterHeader = available - headerHeight;
        final rowsNatural = visible.length * rowHeight;
        final showDropZone = bodyAfterHeader >= minDropZoneHeight &&
            (rowsNatural + minDropZoneHeight <= bodyAfterHeader ||
                rowsNatural > bodyAfterHeader);
        final rowsCap = showDropZone && rowsNatural > bodyAfterHeader
            ? bodyAfterHeader - minDropZoneHeight
            : bodyAfterHeader;
        final rowsHeight = (visible.length * rowHeight).clamp(
          0.0,
          rowsCap.clamp(0.0, double.infinity),
        );
        return Column(
          children: [
            _buildTableHeader(),
            SizedBox(
              height: rowsHeight,
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) => _buildTableRow(visible[index]),
              ),
            ),
            if (showDropZone) Expanded(child: _buildDropZone()),
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

  /// Tapping a row selects (or deselects) it, like the checkbox.
  void _toggleRowSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Widget _buildTableRow(Download item) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selected.contains(item.id);
    final rowStyle = AppTextSize.xs.textStyle(weight: AppFontWeight.semibold);
    // Tapping anywhere on the row toggles its selection. The checkbox
    // and the row menu keep their own tap handling, so tapping them
    // does not also toggle the row.
    return GestureDetector(
      onTap: () => _toggleRowSelection(item.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      decoration: BoxDecoration(
        // Only a selected row keeps a fill; unselected rows are
        // transparent so the uniform window background shows through.
        color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
      ),
      child: Row(
        children: [
          SizedBox(
            width: DownloadTableColumns.check,
            child: Center(
              child: Transform.scale(
                scale: 0.8,
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
          ),
          Expanded(
            child: Row(
              children: [
                Icon(
                  downloadStateIcon(item.state),
                  size: 18,
                  color: downloadStatusColor(colorScheme, item.state),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    item.fileName,
                    style: rowStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: DownloadTableColumns.size,
            child: Text(downloadSizeText(item), style: rowStyle),
          ),
          SizedBox(
            width: DownloadTableColumns.status,
            child: _buildStatusCell(item, rowStyle, colorScheme),
          ),
          SizedBox(
            width: DownloadTableColumns.menu,
            child: _buildRowMenu(item),
          ),
          SizedBox(
            width: DownloadTableColumns.speed,
            child: Text(
              '${formatBytes(item.bytesPerSecond)}/s',
              style: rowStyle,
            ),
          ),
          SizedBox(
            width: DownloadTableColumns.speed,
            child: Text('0 B/s', style: rowStyle),
          ),
          SizedBox(
            width: DownloadTableColumns.added,
            child: Text(
              formatAdded(item.createdAt),
              style: rowStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// The `⋮` row menu (Pause / Resume / Retry / Cancel, by state,
  /// plus Delete on every row).
  Widget _buildStatusCell(
    Download item,
    TextStyle rowStyle,
    ColorScheme colorScheme,
  ) {
    final text = Text(
      downloadStatusText(item),
      style: rowStyle.copyWith(
        color: downloadStatusColor(colorScheme, item.state),
      ),
      overflow: TextOverflow.ellipsis,
    );
    final message = item.errorMessage;
    if (message == null || message.isEmpty) {
      return text;
    }
    return Tooltip(message: message, child: text);
  }

  Widget _buildRowMenu(Download item) {
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
              entries.add(_menuItem('pause', 'Pause'));
              entries.add(_menuItem('cancel', 'Cancel'));
            case DownloadState.paused:
              entries.add(_menuItem('resume', 'Resume'));
              entries.add(_menuItem('cancel', 'Cancel'));
            case DownloadState.failed:
              entries.add(_menuItem('retry', 'Retry'));
              entries.add(_menuItem('cancel', 'Cancel'));
            case DownloadState.completed:
            case DownloadState.cancelled:
              break;
          }
          // Every row can be deleted; the finished file on disk is
          // kept when a row is deleted.
          entries.add(_menuItem('delete', 'Delete'));
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
      case 'delete':
        call = () => actions.deleteDownload(item.id);
      default:
        return;
    }
    final result = await call();
    result.fold((failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }, (_) {
      if (action == 'delete' && mounted) {
        setState(() => _selected.remove(item.id));
      }
    });
  }

  Widget _buildDropZone() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: DashedBorder(
        color: _dragOver ? colorScheme.primary : colorScheme.outline,
        radius: AppRadius.lg,
        // Drop-only: no tap handler, so clicking the zone does nothing.
        // A download is added from the toolbar or by dropping a URL.
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
                style: AppTextSize.xs.textStyle(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Torrent chưa hỗ trợ.')));
    } else if (result.hasOtherFile && result.urls.isEmpty && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chỉ hỗ trợ kéo-thả URL.')));
    }
    for (final url in result.urls) {
      await _addDownload(url);
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
          _buildGlobalToggle(),
          const SizedBox(width: AppSpacing.s4),
          Icon(
            Icons.arrow_downward,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '${formatBytes(totalSpeed)}/s',
            style: AppTextSize.xs.textStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Icon(
            Icons.arrow_upward,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s1),
          Text(
            '0 B/s',
            style: AppTextSize.xs.textStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (statusFile != null) const Spacer(),
          if (statusFile != null)
            _buildStatusFileButton(statusFile, colorScheme),
        ],
      ),
    );
  }

  /// The selected file name at the far right of the status bar,
  /// built like a toolbar select: file name on the left, a chevron on
  /// the right that shows whether the details panel is open (up: tap
  /// to open it above the bar, down: tap to close it). Compact: it
  /// sizes to its content (capped at 320px) instead of filling the
  /// rest of the bar.
  Widget _buildStatusFileButton(Download file, ColorScheme colorScheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: InkWell(
        onTap: () => setState(() => _detailsOpen = !_detailsOpen),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s2,
            vertical: AppSpacing.s1,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  file.fileName,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextSize.xs.textStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s1),
              Icon(
                _detailsOpen
                    ? Icons.arrow_drop_down
                    : Icons.arrow_drop_up,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The file named at the far right of the status bar: the selected
  /// one only. Nothing is shown when no row is selected.
  Download? _statusFile(List<Download> visible) {
    if (_selected.isEmpty) {
      return null;
    }
    final selected = visible.where((d) => _selected.contains(d.id)).toList();
    return selected.isNotEmpty ? selected.first : null;
  }

  Widget _buildGlobalToggle() {
    final colorScheme = Theme.of(context).colorScheme;
    final isOff = !_snailMode;
    return InkWell(
      onTap: _toggleSnailMode,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
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
            SnailIcon(
              size: 16,
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

  Future<void> _toggleSnailMode() async {
    final actions = ref.read(downloadsActionsProvider);
    final enabling = !_snailMode;
    final result = await actions.setGlobalBandwidthLimit(
      enabling ? _snailModeBytesPerSecond : null,
    );
    if (!mounted) {
      return;
    }
    result.fold((failure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }, (_) => setState(() => _snailMode = enabling));
  }

  // --- Add download dialog ---

  /// Reads a URL from the clipboard, if it holds one. Best-effort: a
  /// clipboard failure or non-URL text leaves the field empty.
  Future<String?> _readClipboardUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return null;
      final uri = Uri.tryParse(text);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        return null;
      }
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Step 1 of the Add download flow: the URL, prefilled from the
  /// clipboard when it holds one. OK probes the URL (reachable +
  /// size); a failed probe stays in this dialog with the error inline,
  /// a successful one opens the New download dialog.
  Future<void> _showAddDialog() async {
    final initial = await _readClipboardUrl();
    if (!mounted) return;
    final probe = await showDialog<ProbeResult>(
      context: context,
      builder: (context) => _AddDownloadDialog(initialUrl: initial),
    );
    if (probe == null || !mounted) return;
    await _showNewDownload(probe);
  }

  /// Step 2 of the Add download flow: the save location, file name
  /// and immediate vs scheduled choice. A picked directory is
  /// remembered for the next Save to dropdown, most recent first.
  Future<void> _showNewDownload(ProbeResult probe) async {
    final settings = ref.read(fileConflictSettingsProvider);
    final defaultDirectory = ref.read(downloadDirectoryProvider);
    final decision = await showNewDownloadDialog(
      context: context,
      probe: probe,
      defaultDirectory: defaultDirectory,
      recentDirectories: settings.loadRecentDirectories(),
    );
    if (decision == null || !mounted) return;
    if (decision.directory != defaultDirectory) {
      final recent = [
        decision.directory,
        ...settings
            .loadRecentDirectories()
            .where((d) => d != decision.directory),
      ].take(5).toList();
      settings.saveRecentDirectories(recent);
    }
    await _addDownload(
      probe.url,
      directory: decision.directory,
      fileName: decision.fileName,
      paused: decision.paused,
    );
  }

  /// Adds one download, asking what to do when the destination file
  /// already exists. A remembered choice is applied without asking;
  /// the dialog's choice can be remembered for the next conflict.
  Future<void> _addDownload(
    String url, {
    String? directory,
    String? fileName,
    bool paused = false,
  }) async {
    final actions = ref.read(downloadsActionsProvider);
    final settings = ref.read(fileConflictSettingsProvider);
    final remembered = settings.load();
    if (remembered != null) {
      final result = await actions.addDownload(
        url,
        directory: directory,
        fileName: fileName,
        conflictPolicy: remembered,
        paused: paused,
      );
      result.fold(_showFailure, (_) {});
      return;
    }
    final result = await actions.addDownload(
      url,
      directory: directory,
      fileName: fileName,
      paused: paused,
    );
    if (!mounted) return;
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure == null) return;
    if (failure is! FileExistsFailure) {
      _showFailure(failure);
      return;
    }
    final decision = await showFileConflictDialog(
      context: context,
      fileName: p.basename(failure.destination),
      renamedName: p.basename(resolveUniquePath(failure.destination)),
    );
    if (decision == null || !mounted) return;
    if (decision.remember) settings.save(decision.policy);
    final retry = await actions.addDownload(
      url,
      directory: directory,
      fileName: fileName,
      conflictPolicy: decision.policy,
      paused: paused,
    );
    retry.fold(_showFailure, (_) {});
  }

  void _showFailure(Failure failure) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

/// The select dropdown's options (FDM). Kept private: the widget test
/// taps the menu items by their labels.
enum _SelectBy { all, downloadsOnly, uploadsOnly, completed, stopped }

/// Step 1 of the Add download flow: the URL field. The dialog owns its
/// [TextEditingController], so it is disposed with the dialog route
/// (after the exit animation), never while the field is still mounted.
class _AddDownloadDialog extends ConsumerStatefulWidget {
  const _AddDownloadDialog({required this.initialUrl});

  /// The URL prefilled from the clipboard, if it held one.
  final String? initialUrl;

  @override
  ConsumerState<_AddDownloadDialog> createState() =>
      _AddDownloadDialogState();
}

class _AddDownloadDialogState extends ConsumerState<_AddDownloadDialog> {
  late final TextEditingController _controller;
  String? _error;
  var _probing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
    if (widget.initialUrl != null) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialUrl!.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final url = _controller.text.trim();
    setState(() {
      _probing = true;
      _error = null;
    });
    final result = await ref.read(downloadsActionsProvider).probeUrl(url);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _probing = false;
        _error = failure.message;
      }),
      (probe) => Navigator.of(context).pop(probe),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PdmDialog(
      title: 'Add download',
      actions: [
        PdmDialogButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PdmDialogButton.primary(
          label: 'OK',
          onPressed: _probing || _controller.text.trim().isEmpty
              ? null
              : _probe,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            style: AppTextSize.xs.textStyle(),
            decoration: InputDecoration(
              hintText: 'https://...',
              hintStyle: AppTextSize.xs.textStyle(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s2,
              ),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
          ),
          if (_probing) ...[
            const SizedBox(height: AppSpacing.s2),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.s2),
                Text(
                  'Checking link…',
                  style: AppTextSize.xs.textStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              _error!,
              style: AppTextSize.xs.textStyle(
                color: colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
