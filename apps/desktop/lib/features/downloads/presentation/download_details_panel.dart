import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/shared/theme/app_tokens.dart';

import '../domain/entities/download.dart';
import '../providers/download_providers.dart';
import 'download_table.dart';

/// The tab shown in the details panel.
enum DetailsTab { general, progress, connections }

/// The FDM-style details panel for the selected download, shown below
/// the table and above the status bar. Three tabs: GENERAL (name, path,
/// progress, downloaded, added, priority, URL), PROGRESS (a segment
/// bitmap), CONNECTIONS (host, port, connection count). The PROGRESS
/// and CONNECTIONS tabs fetch per-segment progress when they are
/// opened and whenever the download's bytes change; GENERAL needs no
/// segment data.
class DownloadDetailsPanel extends ConsumerStatefulWidget {
  const DownloadDetailsPanel({
    super.key,
    required this.download,
    required this.onClose,
  });

  final Download download;
  final VoidCallback onClose;

  @override
  ConsumerState<DownloadDetailsPanel> createState() =>
      _DownloadDetailsPanelState();
}

class _DownloadDetailsPanelState
    extends ConsumerState<DownloadDetailsPanel> {
  DetailsTab _tab = DetailsTab.general;
  List<DownloadSegment> _segments = [];

  Future<void> _fetchSegments() async {
    final result = await ref
        .read(downloadsActionsProvider)
        .getSegments(widget.download.id);
    if (!mounted) return;
    result.fold((_) {}, (segments) {
      setState(() => _segments = segments);
    });
  }

  void _setTab(DetailsTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (tab != DetailsTab.general) {
      unawaited(_fetchSegments());
    }
  }

  @override
  void didUpdateWidget(DownloadDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The panel follows the selected download: when the selection
    // changes, drop the old segments and fetch the new ones. When
    // the same download's bytes change, refresh the segments so the
    // bitmap and the connection count track the progress.
    final idChanged = oldWidget.download.id != widget.download.id;
    final bytesChanged =
        oldWidget.download.downloadedBytes !=
            widget.download.downloadedBytes ||
        oldWidget.download.totalBytes != widget.download.totalBytes;
    if (idChanged) {
      _segments = [];
    }
    if ((idChanged || bytesChanged) && _tab != DetailsTab.general) {
      unawaited(_fetchSegments());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 264,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          _buildTabBar(colorScheme),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: switch (_tab) {
                DetailsTab.general => _buildGeneral(colorScheme),
                DetailsTab.progress => _buildProgress(colorScheme),
                DetailsTab.connections => _buildConnections(colorScheme),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme colorScheme) {
    Widget tab(DetailsTab tab, String label) {
      final active = _tab == tab;
      return InkWell(
        onTap: () => _setTab(tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          child: Text(
            label,
            style: AppTextSize.xs.textStyle(
              weight: AppFontWeight.semibold,
              color: active
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(DetailsTab.general, 'GENERAL'),
        tab(DetailsTab.progress, 'PROGRESS'),
        tab(DetailsTab.connections, 'CONNECTIONS'),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Close',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: 32,
            height: 32,
          ),
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  // --- GENERAL ---

  Widget _buildGeneral(ColorScheme colorScheme) {
    final download = widget.download;
    final labelStyle = AppTextSize.xs.textStyle(
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = AppTextSize.xs.textStyle(
      weight: AppFontWeight.semibold,
    );
    final directory = download.filePath == null
        ? ''
        : p.dirname(download.filePath!);
    final percent = (download.progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.folder,
              size: 20,
              color: downloadStatusColor(colorScheme, download.state),
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Text(
                download.fileName,
                style: AppTextSize.base.textStyle(
                  weight: AppFontWeight.semibold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        _buildCopyRow(
          label: 'Path',
          value: directory,
          labelStyle: labelStyle,
          valueStyle: valueStyle,
          colorScheme: colorScheme,
        ),
        const SizedBox(height: AppSpacing.s1),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: download.totalBytes > 0 ? download.progress : null,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
                minHeight: 6,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Text('$percent%', style: valueStyle),
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        _buildLabelValue(
          'Downloaded',
          download.totalBytes > 0
              ? '${formatBytes(download.downloadedBytes)} / '
                    '${formatBytes(download.totalBytes)}'
              : formatBytes(download.downloadedBytes),
          labelStyle,
          valueStyle,
        ),
        const SizedBox(height: AppSpacing.s1),
        _buildLabelValue(
          'Added at',
          formatAddedFull(download.createdAt),
          labelStyle,
          valueStyle,
        ),
        const SizedBox(height: AppSpacing.s1),
        _buildLabelValue(
          'Priority',
          priorityLabel(download.priority),
          labelStyle,
          valueStyle,
        ),
        const SizedBox(height: AppSpacing.s1),
        _buildCopyRow(
          label: 'File',
          value: download.url,
          labelStyle: labelStyle,
          valueStyle: valueStyle,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildLabelValue(
    String label,
    String value,
    TextStyle labelStyle,
    TextStyle valueStyle,
  ) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label, style: labelStyle)),
        Expanded(child: Text(value, style: valueStyle)),
      ],
    );
  }

  Widget _buildCopyRow({
    required String label,
    required String value,
    required TextStyle labelStyle,
    required TextStyle valueStyle,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label, style: labelStyle)),
        Expanded(
          child: Text(
            value,
            style: valueStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InkWell(
          onTap: value.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: value)),
          child: Icon(
            Icons.copy,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // --- PROGRESS ---

  Widget _buildProgress(ColorScheme colorScheme) {
    final download = widget.download;
    if (download.totalBytes <= 0) {
      return Center(
        child: Text(
          'Total size unknown: ${formatBytes(download.downloadedBytes)} '
          'downloaded so far.',
          style: AppTextSize.xs.textStyle(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_segments.isEmpty) {
      return Center(
        child: Text(
          'No segment data yet.',
          style: AppTextSize.xs.textStyle(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const cellSize = 8.0;
        const gap = 2.0;
        const stride = cellSize + gap;
        final perRow = (constraints.maxWidth / stride).floor().clamp(1, 200);
        const rows = 6;
        final cellCount = perRow * rows;
        final cellBytes = download.totalBytes / cellCount;
        // A segment's downloaded range is [start, start + downloaded).
        final ranges = _segments
            .map((s) => (s.start, s.start + s.downloaded))
            .toList();
        bool isDownloaded(int cellIndex) {
          final byte = (cellIndex * cellBytes).floor();
          return ranges.any((r) => byte >= r.$1 && byte < r.$2);
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(cellCount, (i) {
            final done = isDownloaded(i);
            return Container(
              width: cellSize,
              height: cellSize,
              color: done
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
            );
          }),
        );
      },
    );
  }

  // --- CONNECTIONS ---

  Widget _buildConnections(ColorScheme colorScheme) {
    final uri = Uri.tryParse(widget.download.url);
    final host = uri?.host ?? '';
    final port = uri == null ? 0 : uri.port;
    final labelStyle = AppTextSize.xs.textStyle(
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = AppTextSize.xs.textStyle(
      weight: AppFontWeight.semibold,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelValue('Host', host, labelStyle, valueStyle),
        const SizedBox(height: AppSpacing.s1),
        _buildLabelValue('Port', '$port', labelStyle, valueStyle),
        const SizedBox(height: AppSpacing.s1),
        _buildLabelValue(
          'Connection count',
          '${_segments.length}',
          labelStyle,
          valueStyle,
        ),
      ],
    );
  }
}

/// The priority as FDM shows it: high / normal / low.
String priorityLabel(int priority) {
  if (priority > 0) return 'high';
  if (priority < 0) return 'low';
  return 'normal';
}

/// The full added date, FDM-style in Vietnamese:
/// "11 thg 11 2026, 17:10". Empty when the date is unknown.
String formatAddedFull(DateTime? added) {
  if (added == null) return '';
  final minute = added.minute.toString().padLeft(2, '0');
  return '${added.day} thg ${added.month} ${added.year}, '
      '${added.hour}:$minute';
}
