import 'package:download_api/download_api.dart';
import 'package:flutter/material.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

/// The user's answer to the file-exists dialog: which policy to apply
/// for this download, and whether to remember it for the next conflict.
class FileConflictDecision {
  const FileConflictDecision({required this.policy, required this.remember});

  final FileConflictPolicy policy;
  final bool remember;
}

/// Asks what to do when the destination file already exists.
/// Returns null when the dialog is dismissed (Cancel).
Future<FileConflictDecision?> showFileConflictDialog({
  required BuildContext context,
  required String fileName,
  required String renamedName,
}) {
  // Rename is the safe default: it never destroys an existing file.
  var policy = FileConflictPolicy.rename;
  var remember = false;
  return showDialog<FileConflictDecision>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => PdmDialog(
        title: 'File already exists',
        actions: [
          PdmDialogButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          PdmDialogButton.primary(
            label: 'Download',
            onPressed: () => Navigator.of(context).pop(
              FileConflictDecision(policy: policy, remember: remember),
            ),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: AppTextSize.base.textStyle(
                weight: AppFontWeight.semibold,
              ),
            ),
            RadioGroup<FileConflictPolicy>(
              groupValue: policy,
              onChanged: (value) => setState(() => policy = value ?? policy),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<FileConflictPolicy>(
                    title: const Text('Overwrite'),
                    subtitle: const Text('Replace the existing file'),
                    value: FileConflictPolicy.overwrite,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<FileConflictPolicy>(
                    title: const Text('Rename'),
                    subtitle: Text('Save as "$renamedName"'),
                    value: FileConflictPolicy.rename,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              title: const Text('Remember my choice'),
              value: remember,
              onChanged: (value) => setState(() => remember = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    ),
  );
}
