import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/sign_models.dart';

class FileImportService {
  static const _extensions=['ipa','p12','mobileprovision','zip'];

  Future<List<ImportedFile>> pickFiles({List<String>? extensions}) async {
    final result=await FilePicker.platform.pickFiles(allowMultiple:true,type:FileType.custom,allowedExtensions:extensions??_extensions);
    if(result==null) return const [];
    final dir=await _importsDir();
    final out=<ImportedFile>[];
    for(final selected in result.files){
      final source=selected.path;
      if(source==null) continue;
      final ext=(selected.extension??'').toLowerCase();
      final id='${DateTime.now().microsecondsSinceEpoch}_${out.length}';
      final safe='${id}_${selected.name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'),'_')}';
      final dest=p.join(dir.path,safe);
      await File(source).copy(dest);
      out.add(ImportedFile(id:id,name:selected.name,path:dest,kind:_kind(ext),size:await File(dest).length(),importedAt:DateTime.now()));
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

  String _kind(String ext)=>switch(ext){'ipa'=>'IPA','p12'=>'Certificate','mobileprovision'=>'Provision','zip'=>'Archive',_=>'File'};
}
