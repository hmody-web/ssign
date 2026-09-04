import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LibrarySourceConfig {
  final String id;
  final String name;
  final String url;
  final String kind;
  final bool builtIn;
  final bool enabled;

  const LibrarySourceConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.kind,
    required this.builtIn,
    required this.enabled,
  });

  LibrarySourceConfig copyWith({String? name, String? url, bool? enabled}) =>
      LibrarySourceConfig(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        kind: kind,
        builtIn: builtIn,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'kind': kind,
        'builtIn': builtIn,
        'enabled': enabled,
      };

  factory LibrarySourceConfig.fromJson(Map<String, dynamic> json) =>
      LibrarySourceConfig(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        kind: (json['kind'] ?? 'custom').toString(),
        builtIn: json['builtIn'] == true,
        enabled: json['enabled'] != false,
      );
}

class LibrarySourcesStore extends ChangeNotifier {
  LibrarySourcesStore._();
  static final instance = LibrarySourcesStore._();

  static const _prefsKey = 'booma.library.sources.v1';
  SharedPreferences? _prefs;
  final List<LibrarySourceConfig> _sources = [];

  static const List<LibrarySourceConfig> defaults = [
    LibrarySourceConfig(
      id: 'alsaray',
      name: 'Booma',
      url: 'https://scrptaty.com/apps/alsaray/api.php',
      kind: 'alsaray',
      builtIn: true,
      enabled: true,
    ),
    LibrarySourceConfig(
      id: 'zsign',
      name: 'Zsign',
      url: 'https://appiraq.com/han.json',
      kind: 'zsign',
      builtIn: true,
      enabled: true,
    ),
    LibrarySourceConfig(
      id: 'appstar',
      name: 'Appstar',
      url: 'https://appstar.app/my/get-7md/Api.php',
      kind: 'appstar',
      builtIn: true,
      enabled: true,
    ),
    LibrarySourceConfig(
      id: 'iosboom',
      name: 'iOSBoom',
      url: 'https://scrptaty.com/apps/ipa/library.php',
      kind: 'iosboom',
      builtIn: true,
      enabled: true,
    ),
    LibrarySourceConfig(
      id: 'nsign',
      name: 'NSign',
      url: 'https://night-script.top/my/get-7md/Api.php',
      kind: 'nsign',
      builtIn: true,
      enabled: true,
    ),
  ];

  List<LibrarySourceConfig> get sources => List.unmodifiable(_sources);
  List<LibrarySourceConfig> get enabledSources =>
      _sources.where((source) => source.enabled).toList(growable: false);
  List<LibrarySourceConfig> get customSources =>
      _sources.where((source) => !source.builtIn).toList(growable: false);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_prefsKey);
    final persisted = <String, LibrarySourceConfig>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final source = LibrarySourceConfig.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (source.id.isNotEmpty) persisted[source.id] = source;
          }
        }
      } catch (_) {}
    }

    _sources.clear();
    for (final defaultSource in defaults) {
      final saved = persisted.remove(defaultSource.id);
      _sources.add(
        saved == null
            ? defaultSource
            : defaultSource.copyWith(enabled: saved.enabled),
      );
    }
    for (final source in persisted.values) {
      if (!source.builtIn && source.url.trim().isNotEmpty) _sources.add(source);
    }
    await _save();
  }

  bool isEnabled(String id) {
    for (final source in _sources) {
      if (source.id == id) return source.enabled;
    }
    return true;
  }

  LibrarySourceConfig? byId(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  Future<void> setEnabled(String id, bool value) async {
    final index = _sources.indexWhere((source) => source.id == id);
    if (index < 0 || _sources[index].enabled == value) return;
    _sources[index] = _sources[index].copyWith(enabled: value);
    await _save();
    notifyListeners();
  }

  Future<LibrarySourceConfig> addCustomSource({
    required String url,
    String? name,
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('رابط المصدر غير صالح');
    }
    final duplicate = _sources.where((s) => s.url.trim() == normalized).toList();
    if (duplicate.isNotEmpty) {
      final existing = duplicate.first;
      if (!existing.enabled) await setEnabled(existing.id, true);
      return byId(existing.id) ?? existing;
    }

    final hostName = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    final source = LibrarySourceConfig(
      id: 'custom:${DateTime.now().microsecondsSinceEpoch}',
      name: (name ?? '').trim().isEmpty ? hostName : name!.trim(),
      url: normalized,
      kind: 'custom',
      builtIn: false,
      enabled: true,
    );
    _sources.add(source);
    await _save();
    notifyListeners();
    return source;
  }

  Future<void> removeCustomSource(String id) async {
    _sources.removeWhere((source) => source.id == id && !source.builtIn);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setString(
      _prefsKey,
      jsonEncode(_sources.map((source) => source.toJson()).toList()),
    );
  }

  static String sourceIdForStorage(String storageType, String appId) {
    final storage = storageType.trim().toLowerCase();
    if (storage.startsWith('custom:')) return storageType;
    if (storage == 'alsaray' || appId.startsWith('alsaray:')) return 'alsaray';
    if (storage == 'zsign' || appId.startsWith('zsign:')) return 'zsign';
    if (storage == 'appstar' || appId.startsWith('appstar:')) return 'appstar';
    if (storage == 'nsign' || appId.startsWith('nsign:')) return 'nsign';
    if (storage == 'iosboom' || appId.startsWith('iosboom:')) return 'iosboom';
    return 'iosboom';
  }
}
