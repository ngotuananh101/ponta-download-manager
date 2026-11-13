import 'package:download_api/download_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/services/disk_space_service.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/pdm_dialog.dart';
import 'download_table.dart';

/// The user's choices in the New download dialog: where to save, under
/// what name, and whether the download starts later instead of now.
class NewDownloadDecision {
  const NewDownloadDecision({
    required this.directory,
    required this.fileName,
    required this.paused,
  });

  final String directory;
  final String fileName;

  /// True when the download should sit paused (Download later, or
  /// DOWNLOAD with the Scheduler box checked) instead of starting now.
  final bool paused;
}

/// Shows the New download dialog for a probed URL: the save location
/// and file name, the Scheduler box, and the probed size next to the
/// free disk space. Returns null when the user cancels or closes it.
/// [pickDirectory] and [freeSpace] are seams for tests; they default
/// to the system folder picker and the real disk-space lookup.
Future<NewDownloadDecision?> showNewDownloadDialog({
  required BuildContext context,
  required ProbeResult probe,
  required String defaultDirectory,
  List<String> recentDirectories = const [],
  Future<String?> Function()? pickDirectory,
  Future<int?> Function(String path)? freeSpace,
}) {
  return showDialog<NewDownloadDecision>(
    context: context,
    builder: (context) => NewDownloadDialog(
      probe: probe,
      defaultDirectory: defaultDirectory,
      recentDirectories: recentDirectories,
      pickDirectory: pickDirectory ?? () => FilePicker.getDirectoryPath(),
      freeSpace: freeSpace ?? const DiskSpaceService().freeBytes,
    ),
  );
}

class NewDownloadDialog extends StatefulWidget {
  const NewDownloadDialog({
    super.key,
    required this.probe,
    required this.defaultDirectory,
    this.recentDirectories = const [],
    required this.pickDirectory,
    required this.freeSpace,
  });

  final ProbeResult probe;
  final String defaultDirectory;
  final List<String> recentDirectories;
  final Future<String?> Function() pickDirectory;
  final Future<int?> Function(String path) freeSpace;

  @override
  State<NewDownloadDialog> createState() => _NewDownloadDialogState();
}

class _NewDownloadDialogState extends State<NewDownloadDialog> {
  late final TextEditingController _fileNameController;
  late List<String> _directories;
  late String _directory;
  var _scheduled = false;
  int? _freeBytes;
  var _freeBytesLoading = true;

  @override
  void initState() {
    super.initState();
    _fileNameController = TextEditingController(text: widget.probe.fileName);
    _directories = [
      widget.defaultDirectory,
      ...widget.recentDirectories.where(
        (d) => d != widget.defaultDirectory,
      ),
    ];
    _directory = widget.defaultDirectory;
    _refreshFreeSpace();
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  Future<void> _refreshFreeSpace() async {
    final free = await widget.freeSpace(_directory);
    if (!mounted) return;
    setState(() {
      _freeBytes = free;
      _freeBytesLoading = false;
    });
  }

  bool get _fileNameValid {
    final name = _fileNameController.text.trim();
    return name.isNotEmpty &&
        !name.contains('/') &&
        !name.contains('\\');
  }

  String get _sizeText {
    final total = widget.probe.totalBytes;
    final size = total < 0 ? 'Unknown size' : formatBytes(total);
    final disk = _freeBytesLoading
        ? '…'
        : _freeBytes == null
        ? '—'
        : formatBytes(_freeBytes!);
    return 'Size: $size (Disk space: $disk)';
  }

  Future<void> _pickDirectory() async {
    final picked = await widget.pickDirectory();
    if (picked == null || !mounted) return;
    setState(() {
      if (!_directories.contains(picked)) _directories.add(picked);
      _directory = picked;
      _freeBytesLoading = true;
    });
    await _refreshFreeSpace();
  }

  void _submit(bool downloadLater) {
    Navigator.of(context).pop(
      NewDownloadDecision(
        directory: _directory,
        fileName: _fileNameController.text.trim(),
        paused: downloadLater || _scheduled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PdmDialog(
      title: 'New download',
      actions: [
        PdmDialogButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PdmDialogButton.secondary(
          label: 'Download later',
          onPressed: _fileNameValid ? () => _submit(true) : null,
        ),
        PdmDialogButton.primary(
          label: 'DOWNLOAD',
          onPressed: _fileNameValid ? () => _submit(false) : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save to', style: AppTextSize.xs.textStyle()),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              Expanded(child: _saveToDropdown()),
              const SizedBox(width: AppSpacing.s2),
              _folderButton(),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          Text('File name', style: AppTextSize.xs.textStyle()),
          const SizedBox(height: AppSpacing.s2),
          TextField(
            controller: _fileNameController,
            style: AppTextSize.xs.textStyle(),
            decoration: InputDecoration(
              hintStyle: AppTextSize.xs.textStyle(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s2,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (!_fileNameValid) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              'File name can\'t be empty or contain / or \\.',
              style: AppTextSize.xs.textStyle(color: colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.s3),
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _scheduled,
                  onChanged: (value) =>
                      setState(() => _scheduled = value ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              GestureDetector(
                onTap: () => setState(() => _scheduled = !_scheduled),
                child: Text(
                  'Scheduler',
                  style: AppTextSize.xs.textStyle(),
                ),
              ),
              Expanded(
                child: Text(
                  _sizeText,
                  style: AppTextSize.xs.textStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _saveToDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Choose a folder',
      onSelected: (value) async {
        setState(() {
          _directory = value;
          _freeBytesLoading = true;
        });
        await _refreshFreeSpace();
      },
      itemBuilder: (context) => [
        for (final dir in _directories)
          PopupMenuItem<String>(
            value: dir,
            child: Text(dir, style: AppTextSize.xs.textStyle()),
          ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _directory,
                style: AppTextSize.xs.textStyle(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderButton() {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Browse for a folder',
      child: InkWell(
        onTap: _pickDirectory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Icon(
            Icons.folder_open,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
