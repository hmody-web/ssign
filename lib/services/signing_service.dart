import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/sign_models.dart';

class SigningService {
  static const _channel = MethodChannel('sign/native');

  Future<String> _resolveExistingPath(String original) async {
    if (original.isEmpty) return original;
    final direct = File(original);
    if (await direct.exists()) return direct.path;

    final docs = await getApplicationDocumentsDirectory();
    final basename = p.basename(original);
    final candidates = <String>[
      p.join(docs.path, 'Imports', basename),
      p.join(docs.path, 'Signed', basename),
      p.join(docs.path, 'AppIcons', basename),
      p.join(docs.path, basename),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }

    // iOS can change the absolute sandbox container path between installs/updates.
    // As a final recovery step, locate the same file name anywhere under Documents.
    try {
      await for (final entity in docs.list(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path) == basename) {
          return entity.path;
        }
      }
    } catch (_) {}
    return original;
  }

  Future<Map<String, dynamic>> inspectIpa(String ipaPath) async {
    final fixedIpa = await _resolveExistingPath(ipaPath);
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'inspectIpa',
      {'ipaPath': fixedIpa},
    );
    return raw ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> inspectIdentity({
    required String p12Path,
    required String password,
    required String provisionPath,
  }) async {
    final fixedP12 = await _resolveExistingPath(p12Path);
    final fixedProvision = await _resolveExistingPath(provisionPath);
    final raw = await _channel.invokeMapMethod<String, dynamic>('inspectIdentity', {
      'p12Path': fixedP12,
      'password': password,
      'provisionPath': fixedProvision,
    });
    return raw ?? <String, dynamic>{};
  }

  Future<String> sign({
    required String ipaPath,
    required String p12Path,
    required String p12Password,
    required String provisionPath,
    required SignOptions options,
  }) async {
    final fixedIpa = await _resolveExistingPath(ipaPath);
    final fixedP12 = await _resolveExistingPath(p12Path);
    final fixedProvision = await _resolveExistingPath(provisionPath);
    final fixedIcon = options.iconPath.isEmpty
        ? ''
        : await _resolveExistingPath(options.iconPath);

    if (!await File(fixedIpa).exists()) {
      throw StateError('IPA file is missing');
    }
    if (!await File(fixedP12).exists()) {
      throw StateError('P12 certificate file is missing');
    }
    if (!await File(fixedProvision).exists()) {
      throw StateError('Provisioning profile file is missing');
    }

    final result = await _channel.invokeMethod<String>('signIpa', {
      'ipaPath': fixedIpa,
      'p12Path': fixedP12,
      'p12Password': p12Password,
      'provisionPath': fixedProvision,
      'bundleId': options.bundleId,
      'displayName': options.displayName,
      'version': options.version,
      'build': options.build,
      'removeSupportedDevices': options.removeSupportedDevices,
      'iconPath': fixedIcon,
    });
    if (result == null || result.isEmpty) {
      throw StateError('Signing engine returned no output path');
    }
    return result;
  }

  Future<void> savePassword(String id, String password) async =>
      _channel.invokeMethod<void>('savePassword', {'id': id, 'password': password});

  Future<String> loadPassword(String id) async =>
      (await _channel.invokeMethod<String>('loadPassword', {'id': id})) ?? '';

  Future<void> deletePassword(String id) async =>
      _channel.invokeMethod<void>('deletePassword', {'id': id});

  Future<void> share(String path) async {
    final fixed = await _resolveExistingPath(path);
    await _channel.invokeMethod<void>('shareFile', {'path': fixed});
  }

  Future<bool> install(String path) async {
    try {
      final fixed = await _resolveExistingPath(path);
      return (await _channel.invokeMethod<bool>('installIpa', {'path': fixed})) ?? false;
    } on PlatformException {
      return false;
    }
  }
}
