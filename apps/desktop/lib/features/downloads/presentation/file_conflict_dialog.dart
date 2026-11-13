import 'package:download_api/download_api.dart';
import 'package:material_ui/material_ui.dart';
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
              style: AppTextSize.xs.textStyle(
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
                    title: Text(
                      'Overwrite',
                      style: AppTextSize.xs.textStyle(),
                    ),
                    subtitle: Text(
                      'Replace the existing file',
                      style: AppTextSize.xs.textStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: FileConflictPolicy.overwrite,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<FileConflictPolicy>(
                    title: Text(
                      'Rename',
                      style: AppTextSize.xs.textStyle(),
                    ),
                    subtitle: Text(
                      'Save as "$renamedName"',
                      style: AppTextSize.xs.textStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: FileConflictPolicy.rename,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              title: Text(
                'Remember my choice',
                style: AppTextSize.xs.textStyle(),
              ),
              value: remember,
              onChanged: (value) => setState(() => remember = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    ),
  );
}
