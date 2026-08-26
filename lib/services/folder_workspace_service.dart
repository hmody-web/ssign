import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FolderWorkspaceService {
  FolderWorkspaceService._();
  static final instance = FolderWorkspaceService._();

  Future<Directory> root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'BoomaFolders'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> directoryFor(String relative) async {
    final r = await root();
    final safe = _safeRelative(relative);
    final dir = Directory(p.join(r.path, safe));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<FileSystemEntity>> list(String relative) async {
    final dir = await directoryFor(relative);
    final items = await dir.list(followLinks: false).toList();
    items.sort((a, b) {
      if (a is Directory && b is! Directory) return -1;
      if (a is! Directory && b is Directory) return 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return items;
  }

  Future<void> createFolder(String relative, String name) async {
    final clean = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (clean.isEmpty) return;
    final dir = await directoryFor(relative);
    await Directory(p.join(dir.path, clean)).create(recursive: true);
  }

  Future<void> deleteEntity(FileSystemEntity entity) async {
    if (await entity.exists()) await entity.delete(recursive: true);
  }

  Future<List<File>> pickAndAddFiles(String relative) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
    if (result == null) return const [];
    final dir = await directoryFor(relative);
    final out = <File>[];
    for (final item in result.files) {
      if (item.path == null) continue;
      final ext = p.extension(item.name).toLowerCase();
      if (_blocked(ext)) continue;
      final dest = await _uniquePath(dir.path, item.name);
      out.add(await File(item.path!).copy(dest));
    }
    return out;
  }

  Future<File> copyInto({required String sourcePath, required String relative, String? name}) async {
    final dir = await directoryFor(relative);
    final dest = await _uniquePath(dir.path, name ?? p.basename(sourcePath));
    return File(sourcePath).copy(dest);
  }

  Future<File> moveInto({required String sourcePath, required String relative, String? name}) async {
    final copied = await copyInto(sourcePath: sourcePath, relative: relative, name: name);
    try { await File(sourcePath).delete(); } catch (_) {}
    return copied;
  }

  Future<void> extractZip({required String zipPath, required String relative}) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final dest = await directoryFor(relative);
    for (final entry in archive) {
      final rel = _safeRelative(entry.name);
      if (rel.isEmpty) continue;
      final outPath = p.normalize(p.join(dest.path, rel));
      if (!p.isWithin(dest.path, outPath) && outPath != dest.path) continue;
      if (entry.isFile) {
        final file = File(outPath);
        await file.parent.create(recursive: true);
        final data = entry.content;
        if (data is List<int>) {
          await file.writeAsBytes(data, flush: true);
        } else if (data is Uint8List) {
          await file.writeAsBytes(data, flush: true);
        }
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  Future<void> copyEntity(FileSystemEntity entity, String destinationRelative) async {
    if (entity is File) {
      await copyInto(sourcePath: entity.path, relative: destinationRelative);
      return;
    }
    if (entity is Directory) {
      final destination = await directoryFor(destinationRelative);
      final sourceNormalized = p.normalize(entity.absolute.path);
      final destinationNormalized = p.normalize(destination.absolute.path);
      if (destinationNormalized == sourceNormalized || p.isWithin(sourceNormalized, destinationNormalized)) {
        throw FileSystemException('Cannot copy a folder into itself', entity.path);
      }
      final name = p.basename(entity.path);
      final target = Directory(await _uniqueDirectoryPath(destination.path, name));
      await target.create(recursive: true);
      await for (final child in entity.list(recursive: false, followLinks: false)) {
        await _copyTree(child, target.path);
      }
    }
  }

  Future<void> moveEntity(FileSystemEntity entity, String destinationRelative) async {
    await copyEntity(entity, destinationRelative);
    await deleteEntity(entity);
  }

  Future<void> _copyTree(FileSystemEntity entity, String parent) async {
    if (entity is File) {
      await entity.copy(p.join(parent, p.basename(entity.path)));
    } else if (entity is Directory) {
      final next = Directory(p.join(parent, p.basename(entity.path)));
      await next.create(recursive: true);
      await for (final child in entity.list(followLinks: false)) {
        await _copyTree(child, next.path);
      }
    }
  }

  bool _blocked(String ext) => const {
    '.jpg','.jpeg','.png','.gif','.webp','.heic','.bmp','.tif','.tiff',
    '.mp4','.mov','.m4v','.avi','.mkv','.webm','.3gp','.pdf'
  }.contains(ext);

  String _safeRelative(String value) {
    final parts = p.posix.normalize(value.replaceAll('\\', '/')).split('/');
    return parts.where((e) => e.isNotEmpty && e != '.' && e != '..').join(p.separator);
  }

  Future<String> _uniquePath(String parent, String name) async {
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var candidate = p.join(parent, safeName);
    if (!await File(candidate).exists() && !await Directory(candidate).exists()) return candidate;
    final stem = p.basenameWithoutExtension(safeName);
    final ext = p.extension(safeName);
    var i = 2;
    while (true) {
      candidate = p.join(parent, '$stem ($i)$ext');
      if (!await File(candidate).exists() && !await Directory(candidate).exists()) return candidate;
      i++;
    }
  }

  Future<String> _uniqueDirectoryPath(String parent, String name) async => _uniquePath(parent, name);
}
