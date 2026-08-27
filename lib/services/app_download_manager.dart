import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/remote_app.dart';
import '../models/sign_models.dart';
import 'app_store.dart';
import 'ipa_library_service.dart';
import 'native_background_download_service.dart';
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
  AppDownloadManager._() {
    if (Platform.isIOS) {
      _native.events.listen(_handleNativeEvent, onError: (_) {});
      unawaited(_restoreNativeRecords());
    }
  }
  static final instance = AppDownloadManager._();

  final IpaLibraryService _service = IpaLibraryService();
  final NativeBackgroundDownloadService _native = NativeBackgroundDownloadService.instance;
  final SigningService _signer = SigningService();
  final AppStore _store = AppStore.instance;
  final Map<String, AppDownloadSnapshot> _states = {};
  final Map<String, IpaDownloadControl> _controls = {};
  final Map<String, RemoteApp> _apps = {};
  final Map<String, Completer<ImportedFile?>> _nativeCompleters = {};
  final Set<String> _finalizedNativeDownloads = {};

  List<MapEntry<RemoteApp, AppDownloadSnapshot>> get activeDownloads => _states.entries
      .where((e) => (e.value.downloading || e.value.stage == 'signing' || e.value.stage == 'installing') && _apps.containsKey(e.key))
      .map((e) => MapEntry(_apps[e.key]!, e.value))
      .toList();

  AppDownloadSnapshot stateFor(RemoteApp app) {
    _apps[app.id] = app;
    final current = _states[app.id];
    if (current != null) {
      if (current.file != null || current.downloading || current.error != null) return current;
    }
    return AppDownloadSnapshot(file: downloadedFile(app));
  }

  ImportedFile? downloadedFile(RemoteApp app) {
    for (final f in _store.files.reversed) {
      if (!f.path.toLowerCase().endsWith('.ipa')) continue;
      if ((f.bundleId ?? '').isNotEmpty && (f.bundleId ?? '') == app.bundleId) return f;
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

    if (Platform.isIOS) return _startNative(app);
    return _startDart(app);
  }

  Future<ImportedFile?> _startNative(RemoteApp app) async {
    _states[app.id] = const AppDownloadSnapshot(downloading: true);
    notifyListeners();

    final completer = Completer<ImportedFile?>();
    _nativeCompleters[app.id] = completer;
    try {
      final resolved = await _service.resolveDownload(app);
      final base = _safeName(app.name.isEmpty ? app.slug : app.name);
      final version = _safeName(app.version);
      final fileName = '${base.isEmpty ? 'Application' : base}${version.isEmpty ? '' : '-$version'}-${DateTime.now().millisecondsSinceEpoch}.ipa';
      await _native.start(
        downloadId: app.id,
        appName: app.displayName(_store.isArabic),
        appIcon: app.iconUrl,
        downloadURL: resolved.toString(),
        fileName: fileName,
        totalBytes: app.size,
      );
      return completer.future;
    } catch (e) {
      _nativeCompleters.remove(app.id);
      _states[app.id] = AppDownloadSnapshot(error: e);
      notifyListeners();
      rethrow;
    }
  }

  Future<ImportedFile?> _startDart(RemoteApp app) async {
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
      return await _finalizeDownloaded(app.id, path, app: app);
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

  Future<void> _handleNativeEvent(NativeDownloadEvent event) async {
    final id = event.downloadId;
    switch (event.status) {
      case 'downloading':
      case 'paused':
        _states[id] = AppDownloadSnapshot(
          downloading: true,
          paused: event.status == 'paused' || event.paused,
          progress: event.totalBytes > 0 ? event.progress : null,
        );
        notifyListeners();
        break;
      case 'completed':
        if (event.localPath.isEmpty) return;
        try {
          final file = await _finalizeDownloaded(id, event.localPath, app: _apps[id]);
          final completer = _nativeCompleters.remove(id);
          if (completer != null && !completer.isCompleted) completer.complete(file);
        } catch (e, st) {
          final completer = _nativeCompleters.remove(id);
          if (completer != null && !completer.isCompleted) completer.completeError(e, st);
        }
        break;
      case 'cancelled':
        _states.remove(id);
        _apps.remove(id);
        final cancelled = _nativeCompleters.remove(id);
        if (cancelled != null && !cancelled.isCompleted) cancelled.complete(null);
        notifyListeners();
        break;
      case 'failed':
        final error = Exception(event.error ?? 'Background download failed');
        _states[id] = AppDownloadSnapshot(error: error);
        final failed = _nativeCompleters.remove(id);
        if (failed != null && !failed.isCompleted) failed.completeError(error);
        notifyListeners();
        break;
    }
  }

  Future<void> _restoreNativeRecords() async {
    try {
      final records = await _native.list();
      for (final event in records) {
        if (event.status == 'completed' && event.localPath.isNotEmpty) {
          await _finalizeDownloaded(event.downloadId, event.localPath, app: _apps[event.downloadId]);
        } else if (event.status == 'downloading' || event.status == 'paused') {
          _states[event.downloadId] = AppDownloadSnapshot(
            downloading: true,
            paused: event.status == 'paused',
            progress: event.totalBytes > 0 ? event.progress : null,
          );
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<ImportedFile> _finalizeDownloaded(String id, String path, {RemoteApp? app}) async {
    if (_finalizedNativeDownloads.contains('$id|$path')) {
      final current = _states[id]?.file;
      if (current != null) return current;
      for (final existing in _store.files) {
        if (existing.path == path) return existing;
      }
    }

    for (final existing in _store.files) {
      if (existing.path == path) {
        _finalizedNativeDownloads.add('$id|$path');
        _states[id] = AppDownloadSnapshot(file: existing);
        notifyListeners();
        return existing;
      }
    }

    var file = ImportedFile(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: app?.displayName(_store.isArabic) ?? _fileStem(path),
      path: path,
      kind: 'IPA',
      size: await File(path).length(),
      importedAt: DateTime.now(),
      bundleId: app?.bundleId,
      version: app?.version,
    );

    try {
      final info = await _signer.inspectIpa(path);
      final displayName = (info['displayName'] ?? '').toString().trim();
      file = file.copyWith(
        name: displayName.isEmpty ? file.name : displayName,
        bundleId: (info['bundleId'] ?? app?.bundleId ?? '').toString(),
        version: (info['version'] ?? app?.version ?? '').toString(),
        iconPath: (info['iconPath'] ?? '').toString(),
      );
    } catch (_) {}

    await _store.addFiles([file]);
    _finalizedNativeDownloads.add('$id|$path');

    if (_store.autoSignAfterDownload && _store.identities.isNotEmpty) {
      final identity = _store.identities.first;
      _states[id] = AppDownloadSnapshot(file: file, stage: 'signing');
      notifyListeners();
      final password = await _signer.loadPassword(identity.id);
      final signedPath = await _signer.sign(
        ipaPath: file.path,
        p12Path: identity.p12Path,
        p12Password: password,
        provisionPath: identity.provisionPath,
        options: SignOptions(
          bundleId: file.bundleId ?? '',
          displayName: file.name,
          version: file.version ?? '',
          build: '',
          removeSupportedDevices: false,
          iconPath: '',
        ),
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
      _states[id] = AppDownloadSnapshot(file: file, stage: 'installing');
      notifyListeners();
      await _signer.install(signedPath);
    }

    _states[id] = AppDownloadSnapshot(file: file);
    notifyListeners();
    return file;
  }

  void togglePause(RemoteApp app) {
    if (Platform.isIOS) {
      final current = _states[app.id];
      if (current == null || !current.downloading) return;
      if (current.paused) {
        unawaited(_native.resume(app.id));
      } else {
        unawaited(_native.pause(app.id));
      }
      _states[app.id] = AppDownloadSnapshot(
        downloading: true,
        paused: !current.paused,
        progress: current.progress,
      );
      notifyListeners();
      return;
    }

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
    if (Platform.isIOS) {
      await _native.cancel(app.id);
    } else {
      final control = _controls[app.id];
      if (control != null) await control.cancel();
    }
    _states.remove(app.id);
    _apps.remove(app.id);
    final completer = _nativeCompleters.remove(app.id);
    if (completer != null && !completer.isCompleted) completer.complete(null);
    notifyListeners();
  }

  String _safeName(String value) => value
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _fileStem(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    return name.toLowerCase().endsWith('.ipa') ? name.substring(0, name.length - 4) : name;
  }
}

