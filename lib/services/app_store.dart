import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sign_models.dart';

class AppStore extends ChangeNotifier {
  AppStore._();
  static final instance = AppStore._();
  static const _filesKey='sign.files.v2';
  static const _idsKey='sign.identities.v2';
  SharedPreferences? _prefs;
  final List<ImportedFile> files=[];
  final List<SigningIdentity> identities=[];

  Future<void> initialize() async {
    _prefs=await SharedPreferences.getInstance();
    try {
      final raw=_prefs!.getString(_filesKey);
      if(raw!=null) files.addAll((jsonDecode(raw) as List).map((e)=>ImportedFile.fromJson(Map<String,dynamic>.from(e as Map))));
      final ids=_prefs!.getString(_idsKey);
      if(ids!=null) identities.addAll((jsonDecode(ids) as List).map((e)=>SigningIdentity.fromJson(Map<String,dynamic>.from(e as Map))));
    } catch (_) {}
  }

  Future<void> addFiles(Iterable<ImportedFile> items) async { files.addAll(items); await _save(); notifyListeners(); }
  Future<void> removeFile(String id) async { files.removeWhere((e)=>e.id==id); await _save(); notifyListeners(); }
  Future<void> addIdentity(SigningIdentity v) async { identities.add(v); await _save(); notifyListeners(); }
  Future<void> removeIdentity(String id) async { identities.removeWhere((e)=>e.id==id); await _save(); notifyListeners(); }
  Future<void> addSignedOutput(ImportedFile f) => addFiles([f]);

  Future<void> _save() async {
    await _prefs?.setString(_filesKey,jsonEncode(files.map((e)=>e.toJson()).toList()));
    await _prefs?.setString(_idsKey,jsonEncode(identities.map((e)=>e.toJson()).toList()));
  }
}
