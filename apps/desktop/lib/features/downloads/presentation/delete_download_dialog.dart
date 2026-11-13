import 'package:material_ui/material_ui.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

/// The user's answer to the delete dialog: whether the file on disk
/// goes with the download record.
class DeleteDownloadDecision {
  const DeleteDownloadDecision({required this.deleteFile});

  final bool deleteFile;
}

/// Asks whether the file on disk should be deleted along with the
/// download. Returns null when the dialog is dismissed (Cancel).
/// Only call this when at least one selected download has a finished
/// file on disk; otherwise delete directly without asking.
Future<DeleteDownloadDecision?> showDeleteDownloadDialog({
  required BuildContext context,
  required int count,
  String? fileName,
}) {
  // Keeping the file is the safe default: it never destroys data the
  // user may still want.
  var deleteFile = false;
  final single = count == 1;
  return showDialog<DeleteDownloadDecision>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => PdmDialog(
        title: single ? 'Delete download' : 'Delete $count downloads',
        actions: [
          PdmDialogButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          PdmDialogButton.primary(
            label: 'Delete',
            onPressed: () => Navigator.of(context).pop(
              DeleteDownloadDecision(deleteFile: deleteFile),
            ),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              single && fileName != null
                  ? 'Delete "$fileName"?'
                  : 'Delete $count downloads?',
              style: AppTextSize.xs.textStyle(),
            ),
            CheckboxListTile(
              title: Text(
                single
                    ? 'Also delete the file from disk'
                    : 'Also delete the files from disk',
                style: AppTextSize.xs.textStyle(),
              ),
              value: deleteFile,
              onChanged: (value) =>
                  setState(() => deleteFile = value ?? false),
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
