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
  final String stage;

  const AppDownloadSnapshot({
    this.downloading = false,
    this.paused = false,
    this.progress,
    this.file,
    this.error,
    this.stage = '',
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
  final Map<String, RemoteApp> _apps = {};

  List<MapEntry<RemoteApp, AppDownloadSnapshot>> get activeDownloads => _states.entries
      .where((e) => (e.value.downloading || e.value.stage == 'signing' || e.value.stage == 'installing') && _apps.containsKey(e.key))
      .map((e) => MapEntry(_apps[e.key]!, e.value))
      .toList();

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
    _apps[app.id] = app;
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

      if (_store.autoSignAfterDownload) {
        final runtime = await _signer.automaticSigningState();
        final automatic = runtime['ready'] == true;
        if (!automatic && _store.identities.isEmpty) {
          _states[app.id] = AppDownloadSnapshot(file: file, error: StateError('Signing data is unavailable'));
          notifyListeners();
          return file;
        }
        _states[app.id] = AppDownloadSnapshot(file: file, stage: 'signing');
        notifyListeners();
        final options = SignOptions(
          bundleId: file.bundleId ?? '',
          displayName: file.name,
          version: file.version ?? '',
          build: '',
          removeSupportedDevices: false,
          iconPath: '',
        );
        final signedPath = automatic
            ? await _signer.signAutomatic(ipaPath: file.path, options: options)
            : await _signer.sign(
                ipaPath: file.path,
                p12Path: _store.identities.first.p12Path,
                p12Password: await _signer.loadPassword(_store.identities.first.id),
                provisionPath: _store.identities.first.provisionPath,
                options: options,
              );
        final signedInfo = await _signer.inspectIpa(signedPath);
        final signedFile = ImportedFile(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          name: (signedInfo['displayName'] ?? file.name).toString(),
          path: signedPath,
          kind: 'Signed IPA',
          size: await File(signedPath).length(),
          importedAt: DateTime.now(),
          bundleId: (signedInfo['bundleId'] ?? file.bundleId ?? '').toString(),
          version: (signedInfo['version'] ?? file.version ?? '').toString(),
          iconPath: (signedInfo['iconPath'] ?? file.iconPath ?? '').toString(),
        );
        await _store.addSignedOutput(signedFile);
        _states[app.id] = AppDownloadSnapshot(file: file, stage: 'installing');
        notifyListeners();
        await _signer.install(signedPath);
      }

      _states[app.id] = AppDownloadSnapshot(file: file);
      notifyListeners();
      return file;
    } catch (e) {
      if (control.isCancelled) {
        _states.remove(app.id);
        notifyListeners();
        return null;
      }
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

  Future<void> cancel(RemoteApp app) async {
    final control = _controls[app.id];
    if (control != null) {
      await control.cancel();
    }
    _states.remove(app.id);
    _apps.remove(app.id);
    notifyListeners();
  }
}
