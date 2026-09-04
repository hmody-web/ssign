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
  final String description;
  final String imageUrl;
  final String catalogId;

  const LibrarySourceConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.kind,
    required this.builtIn,
    required this.enabled,
    this.description = '',
    this.imageUrl = '',
    this.catalogId = '',
  });

  LibrarySourceConfig copyWith({
    String? name,
    String? url,
    bool? enabled,
    String? description,
    String? imageUrl,
    String? catalogId,
  }) =>
      LibrarySourceConfig(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        kind: kind,
        builtIn: builtIn,
        enabled: enabled ?? this.enabled,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        catalogId: catalogId ?? this.catalogId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'kind': kind,
        'builtIn': builtIn,
        'enabled': enabled,
        'description': description,
        'imageUrl': imageUrl,
        'catalogId': catalogId,
      };

  factory LibrarySourceConfig.fromJson(Map<String, dynamic> json) =>
      LibrarySourceConfig(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        kind: (json['kind'] ?? 'custom').toString(),
        builtIn: json['builtIn'] == true,
        enabled: json['enabled'] != false,
        description: (json['description'] ?? '').toString(),
        imageUrl: (json['imageUrl'] ?? json['image_url'] ?? '').toString(),
        catalogId: (json['catalogId'] ?? json['catalog_id'] ?? '').toString(),
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
      id: 'nsign',
      name: 'NSign',
      url: 'https://ipasoon.icu/apps.php',
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
    if (id == 'iosboom') return false;
    return true;
  }

  LibrarySourceConfig? byId(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  LibrarySourceConfig? byUrl(String url) {
    final normalized = url.trim();
    for (final source in _sources) {
      if (source.url.trim() == normalized) return source;
    }
    return null;
  }

  LibrarySourceConfig? byCatalogId(String catalogId) {
    final normalized = catalogId.trim();
    if (normalized.isEmpty) return null;
    for (final source in _sources) {
      if (source.catalogId.trim() == normalized) return source;
    }
    return null;
  }

  bool containsUrl(String url) => byUrl(url) != null;
  bool containsCatalog(String catalogId, {String url = ''}) =>
      byCatalogId(catalogId) != null || (url.trim().isNotEmpty && containsUrl(url));

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
    String description = '',
    String imageUrl = '',
    String catalogId = '',
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('رابط المصدر غير صالح');
    }

    final safeCatalog = catalogId.trim();
    final duplicateIndex = _sources.indexWhere((s) =>
        (safeCatalog.isNotEmpty && s.catalogId.trim() == safeCatalog) ||
        s.url.trim() == normalized);
    if (duplicateIndex >= 0) {
      final existing = _sources[duplicateIndex];
      final updated = existing.copyWith(
        enabled: true,
        name: (name ?? '').trim().isEmpty ? existing.name : name!.trim(),
        url: normalized,
        description: description.trim().isEmpty ? existing.description : description.trim(),
        imageUrl: imageUrl.trim().isEmpty ? existing.imageUrl : imageUrl.trim(),
        catalogId: safeCatalog.isEmpty ? existing.catalogId : safeCatalog,
      );
      _sources[duplicateIndex] = updated;
      await _save();
      notifyListeners();
      return updated;
    }

    final hostName = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    final source = LibrarySourceConfig(
      id: safeCatalog.isNotEmpty
          ? 'catalog:$safeCatalog'
          : 'custom:${DateTime.now().microsecondsSinceEpoch}',
      name: (name ?? '').trim().isEmpty ? hostName : name!.trim(),
      url: normalized,
      kind: 'custom',
      builtIn: false,
      enabled: true,
      description: description.trim(),
      imageUrl: imageUrl.trim(),
      catalogId: safeCatalog,
    );
    _sources.add(source);
    await _save();
    notifyListeners();
    return source;
  }

  Future<LibrarySourceConfig> addCatalogSource({
    required String catalogId,
    required String name,
    required String url,
    String description = '',
    String imageUrl = '',
  }) =>
      addCustomSource(
        url: url,
        name: name,
        description: description,
        imageUrl: imageUrl,
        catalogId: catalogId,
      );

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
    if (storage.startsWith('custom:') || storage.startsWith('catalog:')) {
      return storageType;
    }
    if (storage == 'alsaray' || appId.startsWith('alsaray:')) return 'alsaray';
    if (storage == 'zsign' || appId.startsWith('zsign:')) return 'zsign';
    if (storage == 'appstar' || appId.startsWith('appstar:')) return 'appstar';
    if (storage == 'nsign' || appId.startsWith('nsign:')) return 'nsign';
    if (storage == 'iosboom' || appId.startsWith('iosboom:')) return 'iosboom';
    return storage.isEmpty ? 'unknown' : storageType;
  }
}
