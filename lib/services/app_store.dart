import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sign_models.dart';

class AppStore extends ChangeNotifier {
  AppStore._();
  static final instance = AppStore._();

  static const _filesKey = 'sign.files.v3';
  static const _idsKey = 'sign.identities.v3';
  static const _languageKey = 'sign.language';
  static const _themeKey = 'sign.theme';
  static const _accentKey = 'sign.accent';
  static const _signDraftKey = 'sign.currentDraft.v1';

  SharedPreferences? _prefs;
  final List<ImportedFile> files = [];
  final List<SigningIdentity> identities = [];

  String languageCode = 'ar';
  String theme = 'dark';
  int accent = 0;
  Map<String, dynamic>? signDraft;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    languageCode = _prefs?.getString(_languageKey) ?? 'ar';
    theme = _prefs?.getString(_themeKey) ?? 'dark';
    accent = _prefs?.getInt(_accentKey) ?? 0;
    try {
      final raw = _prefs!.getString(_filesKey) ?? _prefs!.getString('sign.files.v2');
      if (raw != null) {
        files.addAll((jsonDecode(raw) as List).map((e) => ImportedFile.fromJson(Map<String, dynamic>.from(e as Map))));
      }
      final ids = _prefs!.getString(_idsKey) ?? _prefs!.getString('sign.identities.v2');
      if (ids != null) {
        identities.addAll((jsonDecode(ids) as List).map((e) => SigningIdentity.fromJson(Map<String, dynamic>.from(e as Map))));
      }
      final draft = _prefs!.getString(_signDraftKey);
      if (draft != null) signDraft = Map<String, dynamic>.from(jsonDecode(draft) as Map);
    } catch (_) {}
  }

  bool get isArabic => languageCode == 'ar';
  List<ImportedFile> get signedFiles => files.where((e) => e.kind == 'Signed IPA').toList();

  Future<void> setLanguage(String value) async {
    languageCode = value;
    await _prefs?.setString(_languageKey, value);
    notifyListeners();
  }

  Future<void> setTheme(String value) async {
    theme = value;
    await _prefs?.setString(_themeKey, value);
    notifyListeners();
  }

  Future<void> setAccent(int value) async {
    accent = value;
    await _prefs?.setInt(_accentKey, value);
    notifyListeners();
  }

  Future<void> saveSignDraft(Map<String, dynamic> value) async {
    signDraft = Map<String, dynamic>.from(value);
    await _prefs?.setString(_signDraftKey, jsonEncode(signDraft));
  }

  Future<void> clearSignDraft() async {
    signDraft = null;
    await _prefs?.remove(_signDraftKey);
    notifyListeners();
  }

  ImportedFile? fileByPath(String? path) {
    if (path == null || path.isEmpty) return null;
    for (final file in files) {
      if (file.path == path) return file;
    }
    return null;
  }

  Future<void> addFiles(Iterable<ImportedFile> items) async {
    for (final item in items) {
      final i = files.indexWhere((e) => e.path == item.path);
      if (i >= 0) {
        files[i] = item;
      } else {
        files.add(item);
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> replaceFile(ImportedFile item) async {
    final i = files.indexWhere((e) => e.id == item.id);
    if (i >= 0) files[i] = item;
    await _save();
    notifyListeners();
  }

  Future<void> removeFile(String id) async {
    files.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> removeFiles(Iterable<String> ids) async {
    final set = ids.toSet();
    files.removeWhere((e) => set.contains(e.id));
    await _save();
    notifyListeners();
  }

  Future<void> addIdentity(SigningIdentity v) async {
    identities.add(v);
    await _save();
    notifyListeners();
  }

  Future<void> removeIdentity(String id) async {
    identities.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> addSignedOutput(ImportedFile f) => addFiles([f]);

  Future<void> _save() async {
    await _prefs?.setString(_filesKey, jsonEncode(files.map((e) => e.toJson()).toList()));
    await _prefs?.setString(_idsKey, jsonEncode(identities.map((e) => e.toJson()).toList()));
  }
}
