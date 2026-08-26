import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Repairs absolute paths stored by older app builds.
/// iOS may assign a different application-container prefix after an update,
/// while the files themselves remain inside Documents.
class PersistentPathService {
  PersistentPathService._();
  static final instance = PersistentPathService._();

  Future<Directory> _documents() => getApplicationDocumentsDirectory();

  Future<String?> resolveDataFile(String? storedPath) async {
    if (storedPath == null || storedPath.trim().isEmpty) return null;
    if (await File(storedPath).exists()) return storedPath;

    final docs = await _documents();
    final name = p.basename(storedPath);
    if (name.isEmpty) return null;

    for (final folder in const ['Imports', 'Signed']) {
      final candidate = File(p.join(docs.path, folder, name));
      if (await candidate.exists()) return candidate.path;
    }

    return null;
  }

  Future<String?> resolveIcon({String? storedPath, String? bundleId}) async {
    if (storedPath != null && storedPath.trim().isNotEmpty) {
      if (await File(storedPath).exists()) return storedPath;
    }

    final docs = await _documents();
    final iconsDir = Directory(p.join(docs.path, 'AppIcons'));
    if (!await iconsDir.exists()) return null;

    // First recover the exact old icon filename under the current container.
    if (storedPath != null && storedPath.trim().isNotEmpty) {
      final oldName = p.basename(storedPath);
      if (oldName.isNotEmpty) {
        final exact = File(p.join(iconsDir.path, oldName));
        if (await exact.exists()) return exact.path;
      }
    }

    // Older builds saved icons as: <bundleId>-<timestamp>.png.
    // Pick the newest matching icon if the absolute path was lost.
    final rawBundle = (bundleId ?? '').trim();
    if (rawBundle.isEmpty) return null;
    final safeBundle = rawBundle.replaceAll('/', '_').toLowerCase();

    File? best;
    DateTime? bestModified;
    await for (final entity in iconsDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.png')) continue;
      if (!(name == '$safeBundle.png' || name.startsWith('$safeBundle-'))) continue;
      try {
        final modified = await entity.lastModified();
        if (best == null || bestModified == null || modified.isAfter(bestModified)) {
          best = entity;
          bestModified = modified;
        }
      } catch (_) {
        best ??= entity;
      }
    }
    return best?.path;
  }
}
