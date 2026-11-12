import 'package:flutter/material.dart';
import 'package:pdm/app/app_info.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

/// Shows the About dialog: the app name and the version from
/// [kAppVersion].
Future<void> showPdmAboutDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    builder: (context) => PdmDialog(
      title: 'About',
      actions: [
        PdmDialogButton.primary(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ponta Download Manager',
            style: AppTextSize.xs.textStyle(weight: AppFontWeight.semibold),
          ),
          const SizedBox(height: 4),
          Text('Version $kAppVersion', style: AppTextSize.xs.textStyle()),
        ],
      ),
    ),
  );
}
