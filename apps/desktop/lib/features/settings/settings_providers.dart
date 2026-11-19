import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdm/core/services/autostart_service.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'app_settings.dart';

final appSettingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Persistence is committed before observers (engine, directory, UI) update.
class SettingsController extends Notifier<AppSettings> {
  bool _saving = false;

  @override
  AppSettings build() => ref.read(fileConflictSettingsProvider).loadSettings();

  Future<void> save(AppSettings settings, {List<String>? recentDirectories}) async {
    settings.validate();
    if (_saving) throw StateError('A settings save is already in progress');
    _saving = true;
    final store = ref.read(fileConflictSettingsProvider);
    final previous = store.loadSettings();
    final autostartChanged = previous.launchAtStartup != settings.launchAtStartup;
    final autostart = ref.read(autostartServiceProvider);
    try {
      if (autostartChanged) await autostart.setEnabled(settings.launchAtStartup);
      try {
        store.saveSettings(settings, recentDirectories: recentDirectories);
      } catch (error) {
        if (autostartChanged) {
          try {
            await autostart.setEnabled(previous.launchAtStartup);
          } catch (rollback) {
            throw StateError('Settings could not be saved: $error. '
                'Startup registration could not be restored: $rollback');
          }
        }
        rethrow;
      }
      state = settings;
    } finally {
      _saving = false;
    }
  }

  Future<bool> importJson(String text) async {
    final json = FileConflictSettings.decodeSettings(text);
    if (json == null) return false;
    final directories = json['recentSaveDirectories'];
    await save(AppSettings.fromJson(json), recentDirectories:
      directories is List ? directories.whereType<String>().toList() : const []);
    return true;
  }
}
