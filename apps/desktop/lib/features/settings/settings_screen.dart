import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/app/app_header.dart';
import 'package:pdm/core/services/autostart_service.dart';
import 'package:pdm/core/services/window_service.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';
import 'app_settings.dart';
import 'browser_integration.dart';
import 'package:pdm/shared/widgets/update_dot.dart';
import 'external_tools_providers.dart';
import 'external_tools_section.dart';
import 'settings_providers.dart';

/// The Settings window: a section list on the left, the selected section on
/// the right. Edits stay in a draft; Save persists them, Cancel or Back
/// discards them.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

/// The sections in the sidebar, in display order.
enum _Section {
  downloads('Downloads', Icons.download_outlined),
  system('System', Icons.desktop_windows_outlined),
  browser('Browser integration', Icons.public),
  tools('External tools', Icons.build_outlined);

  const _Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _folder;
  late final TextEditingController _concurrent;
  late final TextEditingController _connections;
  late FileConflictPolicy? _conflict;
  late bool _launchAtStartup;
  late WindowAction _windowAction;
  late StartupState _startupState;
  late DeleteAction _deleteAction;
  late bool _systemFolder;
  _Section _section = _Section.downloads;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The conflict dialog can update storage outside the settings notifier.
    final settings = ref.read(fileConflictSettingsProvider).loadSettings();
    _systemFolder = settings.downloadDirectory == null;
    _folder = TextEditingController(text: settings.downloadDirectory ??
      ref.read(downloadDirectoryResolverProvider)());
    _concurrent = TextEditingController(text: '${settings.maxConcurrentDownloads}');
    _connections = TextEditingController(text: '${settings.maxConnectionsPerDownload}');
    _conflict = settings.fileConflictPolicy;
    _launchAtStartup = settings.launchAtStartup;
    _windowAction = settings.windowAction;
    _startupState = settings.startupState;
    _deleteAction = settings.deleteAction;
  }

  @override
  void dispose() {
    _folder.dispose();
    _concurrent.dispose();
    _connections.dispose();
    super.dispose();
  }

  String? _validateCount(String? text) {
    final value = int.tryParse(text ?? '');
    return value == null || value < 1 || value > 32
        ? 'Enter an integer from 1 to 32' : null;
  }

  bool get _downloadsValid =>
      _validateCount(_concurrent.text) == null &&
      _validateCount(_connections.text) == null &&
      (_systemFolder || (_folder.text.trim().isNotEmpty && p.isAbsolute(_folder.text)));

  void _save() {
    if (_saving) return;
    // Only the mounted section is validated by the Form. A draft with an
    // invalid download field can still be saved from another section, so
    // switch back there first and let its validators report the error.
    if (_section != _Section.downloads && !_downloadsValid) {
      setState(() { _section = _Section.downloads; _error = null; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _form.currentState?.validate();
      });
      return;
    }
    if (!_form.currentState!.validate()) return;
    unawaited(_persist());
  }

  Future<void> _persist() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(appSettingsProvider.notifier).save(AppSettings(
        downloadDirectory: _systemFolder ? null : _folder.text,
        maxConcurrentDownloads: int.parse(_concurrent.text),
        maxConnectionsPerDownload: int.parse(_connections.text),
        fileConflictPolicy: _conflict,
        launchAtStartup: _launchAtStartup,
        windowAction: _windowAction,
        startupState: _startupState,
        deleteAction: _deleteAction,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save settings: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _browse() async {
    try {
      final path = await ref.read(directoryPickerProvider)();
      if (path == null || !mounted) return;
      setState(() { _folder.text = path; _systemFolder = false; });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not select folder: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(body: Column(children: [
        AppHeader(onMinimize: () => unawaited(ref.read(minimizeAppProvider)())),
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildSidebar(),
          Expanded(child: Column(children: [
            _buildTitleBar(),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s6, AppSpacing.s2,
                AppSpacing.s6, AppSpacing.s6),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Form(key: _form, child: _buildSection()),
              )),
            )),
            _buildActions(),
          ])),
        ])),
      ])),
    );
  }

  Widget _buildSidebar() {
    final colorScheme = Theme.of(context).colorScheme;
    // The window minimum is 950px wide, but a test (and a tiled window on a
    // small screen) can be narrower. A 200px list would then leave too little
    // room for the fields, so the sidebar collapses to an icon rail.
    final expanded = MediaQuery.sizeOf(context).width >= 640;
    return Container(
      width: expanded ? 200 : 56,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: ListView(padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        children: [
          for (final section in _Section.values)
            _SidebarItem(section: section, selected: section == _section,
              expanded: expanded, enabled: !_saving,
              hasUpdates: section == _Section.tools && ref.watch(externalToolsControllerProvider).hasUpdates,
              onTap: () => setState(() => _section = section)),
        ]),
    );
  }

  Widget _buildTitleBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s2, AppSpacing.s2,
        AppSpacing.s6, 0),
      child: Row(children: [
        IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : () => Navigator.of(context).pop()),
        const SizedBox(width: AppSpacing.s2),
        Text(_section.label, style: Theme.of(context).textTheme.titleLarge),
      ]),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s6, AppSpacing.s2,
        AppSpacing.s6, AppSpacing.s4),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The error belongs to the whole screen, not one section: a failed
        // save from System must still be visible after switching sections.
        if (_error != null) ...[
          Text(_error!, style: AppTextSize.xs.textStyle(
            color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: AppSpacing.s2),
        ],
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          PdmDialogButton.secondary(label: 'Cancel', onPressed: _saving ? null
            : () => Navigator.of(context).pop()),
          const SizedBox(width: AppSpacing.s2),
          PdmDialogButton.primary(label: _saving ? 'Saving…' : 'Save',
            onPressed: _saving ? null : _save),
        ]),
      ]),
    );
  }

  Widget _buildSection() {
    return switch (_section) {
      _Section.downloads => _buildDownloads(),
      _Section.system => _buildSystem(),
      _Section.browser => const BrowserIntegrationSection(),
      _Section.tools => const ExternalToolsSection(),
    };
  }

  Widget _buildDownloads() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _fieldLabel('Default download folder'),
      TextFormField(key: const Key('download-folder'), controller: _folder,
        enabled: !_saving,
        style: AppTextSize.xs.textStyle(),
        onChanged: (_) => _systemFolder = false,
        validator: (value) => !_systemFolder &&
            (value == null || value.trim().isEmpty || !p.isAbsolute(value))
            ? 'Select an absolute folder path' : null),
      const SizedBox(height: AppSpacing.s2),
      Wrap(spacing: AppSpacing.s2, children: [
        TextButton(onPressed: _saving ? null : _browse, child: const Text('Browse')),
        TextButton(onPressed: _saving ? null : () => setState(() {
          _systemFolder = true;
          _folder.text = ref.read(downloadDirectoryResolverProvider)();
        }), child: const Text('Use system Downloads folder')),
      ]),
      const SizedBox(height: AppSpacing.s5),
      _numberField(key: const Key('concurrent-downloads'), controller: _concurrent,
        label: 'Concurrent downloads',
        helper: '1–32. Running downloads are not interrupted when lowering this limit.'),
      const SizedBox(height: AppSpacing.s5),
      _numberField(key: const Key('connections-per-download'), controller: _connections,
        label: 'Connections per download',
        helper: '1–32. Applies to new downloads; existing downloads keep their settings.'),
      const SizedBox(height: AppSpacing.s5),
      _fieldLabel('When a file already exists'),
      DropdownButtonFormField<String>(initialValue: _conflict?.name ?? 'ask',
        isExpanded: true,
        style: AppTextSize.xs.textStyle(),
        items: const [
          DropdownMenuItem(value: 'ask', child: Text('Ask every time')),
          DropdownMenuItem(value: 'rename', child: Text('Rename automatically')),
          DropdownMenuItem(value: 'overwrite', child: Text('Overwrite')),
        ], onChanged: _saving ? null : (value) => setState(() {
          _conflict = switch (value) {
            'rename' => FileConflictPolicy.rename,
            'overwrite' => FileConflictPolicy.overwrite,
            _ => null,
          };
        })),
      const SizedBox(height: AppSpacing.s5),
      _fieldLabel('When deleting a download'),
      DropdownButtonFormField<DeleteAction>(initialValue: _deleteAction,
        isExpanded: true,
        style: AppTextSize.xs.textStyle(),
        items: const [
          DropdownMenuItem(value: DeleteAction.ask,
            child: Text('Always ask')),
          DropdownMenuItem(value: DeleteAction.removeOnly,
            child: Text('Remove the row only')),
          DropdownMenuItem(value: DeleteAction.deleteFile,
            child: Text('Delete the file on disk too')),
        ], onChanged: _saving ? null
          : (value) => setState(() => _deleteAction = value!)),
      const SizedBox(height: AppSpacing.s1),
      Text('"Always ask" also covers a whole selection; the answer then applies '
        'to every download in it.',
        style: AppTextSize.xs.textStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }

  Widget _buildSystem() {
    final canEnableAutostart = ref.watch(autostartServiceProvider).canEnable;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('Launch at system startup'),
        subtitle: canEnableAutostart ? const Text('Start PDM when you sign in.')
          : const Text('Enabling requires a packaged Linux or Windows release.'),
        value: _launchAtStartup,
        onChanged: _saving || (!canEnableAutostart && !_launchAtStartup) ? null
          : (value) => setState(() => _launchAtStartup = value)),
      const SizedBox(height: AppSpacing.s4),
      _fieldLabel('When minimizing or closing'),
      DropdownButtonFormField<WindowAction>(initialValue: _windowAction,
        isExpanded: true,
        style: AppTextSize.xs.textStyle(),
        items: const [
          DropdownMenuItem(value: WindowAction.tray, child: Text('Minimize to tray')),
          DropdownMenuItem(value: WindowAction.quit, child: Text('Quit application')),
        ], onChanged: _saving ? null : (value) => setState(() => _windowAction = value!)),
      const SizedBox(height: AppSpacing.s5),
      _fieldLabel('Initial window state'),
      DropdownButtonFormField<StartupState>(initialValue: _startupState,
        isExpanded: true,
        style: AppTextSize.xs.textStyle(),
        items: const [
          DropdownMenuItem(value: StartupState.normal, child: Text('Normal')),
          DropdownMenuItem(value: StartupState.tray, child: Text('Minimized to tray')),
        ], onChanged: _saving ? null : (value) => setState(() => _startupState = value!)),
    ]);
  }

  // A label above the field instead of the field's floating label: at the
  // app's xs font the floating form sits on the border and is hard to read.
  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s2),
    child: Text(text, style: AppTextSize.xs.textStyle(
      weight: AppFontWeight.medium)));

  Widget _numberField({required Key key, required TextEditingController controller,
      required String label, required String helper}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _fieldLabel(label),
      TextFormField(key: key, controller: controller, enabled: !_saving,
        keyboardType: TextInputType.number, validator: _validateCount,
        style: AppTextSize.xs.textStyle()),
      const SizedBox(height: AppSpacing.s1),
      Text(helper, style: AppTextSize.xs.textStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.section, required this.selected,
      required this.expanded, required this.enabled, required this.onTap,
      this.hasUpdates = false});

  final bool hasUpdates;

  final _Section section;
  final bool selected;
  final bool expanded;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.primary : colorScheme.onSurface;
    return Tooltip(message: expanded ? '' : section.label,
      child: Material(color: selected
          ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
        child: InkWell(onTap: enabled ? onTap : null,
          child: Container(height: 40,
            padding: EdgeInsets.symmetric(horizontal: expanded ? AppSpacing.s4 : 0),
            alignment: expanded ? Alignment.centerLeft : Alignment.center,
            child: expanded
              ? Row(children: [
                  Icon(section.icon, size: 16, color: foreground),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(child: Text(section.label, overflow: TextOverflow.ellipsis,
                    style: AppTextSize.xs.textStyle(weight: AppFontWeight.medium,
                      color: foreground))),
                  if (hasUpdates) const UpdateDot(),
                ])
              : Stack(clipBehavior: Clip.none, children: [
                  Icon(section.icon, size: 16, color: foreground),
                  if (hasUpdates) const Positioned(right: -5, top: -3, child: UpdateDot()),
                ])))));
  }
}
