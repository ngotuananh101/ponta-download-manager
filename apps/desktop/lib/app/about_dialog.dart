import 'package:material_ui/material_ui.dart';
import 'package:pdm/app/app_info.dart';
import 'package:pdm/app/build_info.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

/// Project, developer and provenance of the running binary.
Future<void> showPdmAboutDialog({
  required BuildContext context,
  BuildInfo buildInfo = const BuildInfo(),
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => PdmDialog(
      title: 'About',
      width: 560,
      actions: [
        PdmDialogButton.primary(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Flexible(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset('assets/images/icon.png', width: 48, height: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kAppName, style: AppTextSize.xs.textStyle(
                          weight: AppFontWeight.semibold,
                        )),
                        const SizedBox(height: 4),
                        Text('Version $kAppVersion',
                          style: AppTextSize.xs.textStyle()),
                      ],
                    ),
                  ),
                ],
              ),
              const _AboutSection('Project'),
              Text(
                'A desktop download manager inspired by IDM, with '
                'parallel downloads, pause/resume and browser integration.',
                style: AppTextSize.xs.textStyle(),
              ),
              const SizedBox(height: 10),
              const _AboutField('Platforms', 'Windows and Linux'),
              const _AboutField('Built with', 'Flutter / Dart / SQLite'),
              const _AboutField('Repository', kProjectUrl),
              const _AboutSection('Developer'),
              const _AboutField('Name', kDeveloperName),
              const _AboutField('GitHub username', kDeveloperUsername),
              const _AboutField('GitHub profile', kDeveloperUrl),
              const _AboutSection('Build'),
              _AboutField('Commit', buildInfo.commitText),
              _AboutField('Build time', buildInfo.buildTimeText),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AboutSection extends StatelessWidget {
  const _AboutSection(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(title, style: AppTextSize.xs.textStyle(
      weight: AppFontWeight.semibold,
    )),
  );
}

class _AboutField extends StatelessWidget {
  const _AboutField(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: LayoutBuilder(builder: (context, constraints) {
      final labelWidget = Text(label, style: AppTextSize.xs.textStyle().copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ));
      final valueWidget = SelectableText(value, style: AppTextSize.xs.textStyle());
      if (constraints.maxWidth < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [labelWidget, const SizedBox(height: 2), valueWidget],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: labelWidget),
          const SizedBox(width: 12),
          Expanded(child: valueWidget),
        ],
      );
    }),
  );
}
