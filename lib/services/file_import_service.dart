import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/sign_models.dart';

class FileImportService {
  static const _extensions=['ipa','app','p12','mobileprovision','zip'];
  static const _blocked = {'jpg','jpeg','png','gif','webp','heic','bmp','tif','tiff','mp4','mov','m4v','avi','mkv','webm','3gp','pdf'};

  Future<List<ImportedFile>> pickFiles({List<String>? extensions}) async {
    final result = extensions == null
        ? await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any)
        : await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: extensions);
    if (result == null) return const [];
    final dir = await _importsDir();
    final out = <ImportedFile>[];
    for (final selected in result.files) {
      final source = selected.path;
      if (source == null) continue;
      final ext = (selected.extension ?? p.extension(selected.name).replaceFirst('.', '')).toLowerCase();
      if (extensions == null && _blocked.contains(ext)) continue;
      if (extensions != null && !extensions.map((e) => e.toLowerCase()).contains(ext)) continue;

      final type = await FileSystemEntity.type(source, followLinks: false);
      final isAppBundle = type == FileSystemEntityType.directory && ext == 'app';
      if (type == FileSystemEntityType.directory && !isAppBundle) continue;
      if (type != FileSystemEntityType.file && !isAppBundle) continue;

      final id = '${DateTime.now().microsecondsSinceEpoch}_${out.length}';
      final safe = '${id}_${selected.name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')}';
      final dest = p.join(dir.path, safe);
      int size;
      if (isAppBundle) {
        await _copyDirectory(Directory(source), Directory(dest));
        size = await _directorySize(Directory(dest));
      } else {
        await File(source).copy(dest);
        size = await File(dest).length();
      }
      out.add(ImportedFile(id: id, name: selected.name, path: dest, kind: _kind(ext), size: size, importedAt: DateTime.now()));
    }
    return out;
  }

  Future<String?> pickAndPersistOne(String ext) async {
    final items=await pickFiles(extensions:[ext]);
    return items.isEmpty?null:items.first.path;
  }

  Future<Directory> _importsDir() async {
    final docs=await getApplicationDocumentsDirectory();
    final dir=Directory(p.join(docs.path,'Imports'));
    if(!await dir.exists()) await dir.create(recursive:true);
    return dir;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      } else if (entity is Link) {
        // App bundles can contain framework symlinks. Preserve them when possible.
        try {
          final linkTarget = await entity.target();
          await Link(target).create(linkTarget, recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<int> _directorySize(Directory directory) async {
    var total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try { total += await entity.length(); } catch (_) {}
      }
    }
    return total;
  }

  String _kind(String ext)=>switch(ext){'ipa'=>'IPA','app'=>'APP','p12'=>'Certificate','mobileprovision'=>'Provision','zip'=>'Archive',_=>'File'};
}
