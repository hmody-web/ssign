import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/remote_app.dart';
import '../models/sign_models.dart';
import 'app_store.dart';
import 'ipa_library_service.dart';
import 'signing_service.dart';

class AppDownloadSnapshot {
  final bool downloading;
  final bool paused;
  final double? progress;
  final ImportedFile? file;
  final Object? error;

  const AppDownloadSnapshot({
    this.downloading = false,
    this.paused = false,
    this.progress,
    this.file,
    this.error,
  });
}

class AppDownloadManager extends ChangeNotifier {
  AppDownloadManager._();
  static final instance = AppDownloadManager._();

  final IpaLibraryService _service = IpaLibraryService();
  final SigningService _signer = SigningService();
  final AppStore _store = AppStore.instance;
  final Map<String, AppDownloadSnapshot> _states = {};
  final Map<String, IpaDownloadControl> _controls = {};

  AppDownloadSnapshot stateFor(RemoteApp app) {
    final current = _states[app.id];
    if (current != null) {
      if (current.file != null || current.downloading) return current;
    }
    return AppDownloadSnapshot(file: downloadedFile(app));
  }

  ImportedFile? downloadedFile(RemoteApp app) {
    for (final f in _store.files.reversed) {
      if (!f.path.toLowerCase().endsWith('.ipa')) continue;
      if ((f.bundleId ?? '').isNotEmpty && (f.bundleId ?? '') == app.bundleId) {
        return f;
      }
    }
    return null;
  }

  Future<ImportedFile?> start(RemoteApp app) async {
    final existing = downloadedFile(app);
    if (existing != null) {
      _states[app.id] = AppDownloadSnapshot(file: existing);
      notifyListeners();
      return existing;
    }
    if (_states[app.id]?.downloading == true) return null;

    final control = IpaDownloadControl();
    _controls[app.id] = control;
    _states[app.id] = const AppDownloadSnapshot(downloading: true);
    notifyListeners();

    try {
      final path = await _service.downloadIpa(
        app,
        control: control,
        onProgress: (received, total) {
          final old = _states[app.id];
          if (old?.downloading != true) return;
          _states[app.id] = AppDownloadSnapshot(
            downloading: true,
            paused: control.isPaused,
            progress: total > 0 ? (received / total).clamp(0, 1) : null,
          );
          notifyListeners();
        },
      );

      var file = ImportedFile(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: app.displayName(_store.isArabic),
        path: path,
        kind: 'IPA',
        size: await File(path).length(),
        importedAt: DateTime.now(),
        bundleId: app.bundleId,
        version: app.version,
      );

      try {
        final info = await _signer.inspectIpa(path);
        final displayName = (info['displayName'] ?? '').toString().trim();
        file = file.copyWith(
          name: displayName.isEmpty ? file.name : displayName,
          bundleId: (info['bundleId'] ?? app.bundleId).toString(),
          version: (info['version'] ?? app.version).toString(),
          iconPath: (info['iconPath'] ?? '').toString(),
        );
      } catch (_) {}

      await _store.addFiles([file]);
      _states[app.id] = AppDownloadSnapshot(file: file);
      notifyListeners();
      return file;
    } catch (e) {
      _states[app.id] = AppDownloadSnapshot(error: e);
      notifyListeners();
      rethrow;
    } finally {
      _controls.remove(app.id);
    }
  }

  void togglePause(RemoteApp app) {
    final control = _controls[app.id];
    if (control == null) return;
    control.toggle();
    final current = _states[app.id];
    if (current == null || !current.downloading) return;
    _states[app.id] = AppDownloadSnapshot(
      downloading: true,
      paused: control.isPaused,
      progress: current.progress,
    );
    notifyListeners();
  }
}
