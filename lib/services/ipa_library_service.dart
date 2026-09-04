import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/remote_app.dart';
import 'library_sources_store.dart';

class IpaLibraryService {
  static const String _proxyBase = 'https://scrptaty.com/apps/ipa';
  static const String _alsarayApi = 'https://scrptaty.com/apps/alsaray/api.php';
  static const String _zsignSource = 'https://appiraq.com/han.json';
  static const String _appstarApi = 'https://appstar.app/my/get-7md/Api.php';
  static const String _nsignApi = 'https://ipasoon.icu/apps.php';
  static const String _nsignDownloadApi = 'https://night-script.top/my/get-7md/Apichid.php';

  List<RemoteApp>? _zsignCache;
  DateTime? _zsignCacheAt;
  static const Duration _zsignCacheDuration = Duration(minutes: 5);

  final Map<int, List<RemoteApp>> _appstarPageCache = <int, List<RemoteApp>>{};
  DateTime? _appstarCacheAt;
  int? _appstarTotalApps;
  int? _appstarPageSize;
  static const Duration _appstarCacheDuration = Duration(minutes: 5);

  final Map<int, List<RemoteApp>> _nsignPageCache = <int, List<RemoteApp>>{};
  DateTime? _nsignCacheAt;
  int? _nsignTotalApps;
  int? _nsignPageSize;
  static const Duration _nsignCacheDuration = Duration(minutes: 5);

  final Map<String, List<RemoteApp>> _customSourceCache = <String, List<RemoteApp>>{};
  final Map<String, DateTime> _customSourceCacheAt = <String, DateTime>{};
  static const Duration _customSourceCacheDuration = Duration(minutes: 5);

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  Future<List<RemoteApp>> fetchApps({
    int offset = 0,
    int limit = 60,
    String search = '',
    String? sourceId,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit <= 0 ? 60 : limit;
    final term = search.trim();
    final selectedSource = sourceId?.trim() ?? '';

    if (selectedSource.isNotEmpty) {
      return _fetchSingleSource(
        selectedSource,
        offset: safeOffset,
        limit: safeLimit,
        search: term,
      );
    }

    final sources = LibrarySourcesStore.instance;
    final customSources = sources.enabledSources.where((item) => item.kind == 'custom').toList();

    Future<List<RemoteApp>> safeApps(Future<List<RemoteApp>> future) async {
      try { return await future; } catch (_) { return const <RemoteApp>[]; }
    }
    Future<int> safeCount(Future<int> future) async {
      try { return await future; } catch (_) { return 0; }
    }
    Future<List<RemoteApp>> loadCustom() async {
      if (customSources.isEmpty) return const <RemoteApp>[];
      final groups = await Future.wait(
        customSources.map((source) => safeApps(_fetchCustomSource(source, search: term))),
      );
      return groups.expand((items) => items).toList();
    }

    if (term.isNotEmpty) {
      final all = await Future.wait<dynamic>(<Future<dynamic>>[
        sources.isEnabled('alsaray') ? safeApps(_fetchAlsarayApps(search: term)) : Future<List<RemoteApp>>.value(const <RemoteApp>[]),
        sources.isEnabled('zsign') ? safeApps(_fetchZsignApps(search: term)) : Future<List<RemoteApp>>.value(const <RemoteApp>[]),
        loadCustom(),
        sources.isEnabled('nsign') ? safeApps(_fetchNsignSearch(term)) : Future<List<RemoteApp>>.value(const <RemoteApp>[]),
        sources.isEnabled('appstar') ? safeApps(_fetchAppstarSearch(term)) : Future<List<RemoteApp>>.value(const <RemoteApp>[]),
      ]);
      final merged = _dedupeApps(<RemoteApp>[
        ...(all[0] as List<RemoteApp>),
        ...(all[1] as List<RemoteApp>),
        ...(all[2] as List<RemoteApp>),
        ...(all[3] as List<RemoteApp>),
        ...(all[4] as List<RemoteApp>),
      ]);
      if (safeOffset >= merged.length) return const <RemoteApp>[];
      return merged.skip(safeOffset).take(safeLimit).toList();
    }

    final loaded = await Future.wait<dynamic>(<Future<dynamic>>[
      sources.isEnabled('alsaray') ? safeApps(_fetchAlsarayApps()) : Future<List<RemoteApp>>.value(const <RemoteApp>[]),
      sources.isEnabled('zsign') ? safeApps(_fetchZsignApps()) : Future<List<RemoteApp>>.value(const <RemoteApp>[]),
      loadCustom(),
      sources.isEnabled('nsign') ? safeCount(_ensureNsignMetadata()) : Future<int>.value(0),
      sources.isEnabled('appstar') ? safeCount(_ensureAppstarMetadata()) : Future<int>.value(0),
    ]);
    final alsarayApps = loaded[0] as List<RemoteApp>;
    final zsignApps = loaded[1] as List<RemoteApp>;
    final customApps = loaded[2] as List<RemoteApp>;
    final nsignCount = loaded[3] as int;
    final appstarCount = loaded[4] as int;

    final prefixApps = _dedupeApps(<RemoteApp>[...alsarayApps, ...zsignApps, ...customApps]);
    final prefixCount = prefixApps.length;
    final nsignStart = prefixCount;
    final appstarStart = nsignStart + nsignCount;
    final libraryEnd = appstarStart + appstarCount;
    final result = <RemoteApp>[];
    var cursor = safeOffset;

    if (cursor < prefixCount && result.length < safeLimit) {
      final take = (safeLimit - result.length).clamp(0, prefixCount - cursor).toInt();
      result.addAll(prefixApps.skip(cursor).take(take));
      cursor += take;
    }

    if (cursor < appstarStart && result.length < safeLimit && nsignCount > 0) {
      final nsignOffset = (cursor - nsignStart).clamp(0, nsignCount).toInt();
      final take = (safeLimit - result.length).clamp(0, nsignCount - nsignOffset).toInt();
      try {
        final rows = await _fetchNsignSlice(offset: nsignOffset, limit: take);
        result.addAll(rows);
        cursor += rows.length;
        if (rows.length < take) cursor = appstarStart;
      } catch (_) {
        cursor = appstarStart;
      }
    }

    if (cursor < libraryEnd && result.length < safeLimit && appstarCount > 0) {
      final appstarOffset = (cursor - appstarStart).clamp(0, appstarCount).toInt();
      final take = (safeLimit - result.length).clamp(0, appstarCount - appstarOffset).toInt();
      try {
        final rows = await _fetchAppstarSlice(offset: appstarOffset, limit: take);
        result.addAll(rows);
        cursor += rows.length;
        if (rows.length < take) cursor = libraryEnd;
      } catch (_) {
        cursor = libraryEnd;
      }
    }

    return _dedupeApps(result);
  }

  Future<List<RemoteApp>> _fetchSingleSource(
    String sourceId, {
    required int offset,
    required int limit,
    required String search,
  }) async {
    final store = LibrarySourcesStore.instance;
    final source = store.byId(sourceId);
    if (source == null || !source.enabled || limit <= 0) return const <RemoteApp>[];

    switch (source.kind) {
      case 'alsaray':
        final all = await _fetchAlsarayApps(search: search);
        return all.skip(offset).take(limit).toList();
      case 'zsign':
        final all = await _fetchZsignApps(search: search);
        return all.skip(offset).take(limit).toList();
      case 'nsign':
        if (search.isNotEmpty) {
          final all = await _fetchNsignSearch(search);
          return all.skip(offset).take(limit).toList();
        }
        return _fetchNsignSlice(offset: offset, limit: limit);
      case 'appstar':
        if (search.isNotEmpty) {
          final all = await _fetchAppstarSearch(search);
          return all.skip(offset).take(limit).toList();
        }
        return _fetchAppstarSlice(offset: offset, limit: limit);
      case 'custom':
        final all = await _fetchCustomSource(source, search: search);
        return all.skip(offset).take(limit).toList();
      default:
        return const <RemoteApp>[];
    }
  }

  List<RemoteApp> _dedupeApps(Iterable<RemoteApp> apps) {
    final map = <String, RemoteApp>{};
    for (final app in apps) {
      final key = app.id.isNotEmpty
          ? app.id
          : '${app.bundleId.toLowerCase()}|${app.version}|${app.name.toLowerCase()}';
      map.putIfAbsent(key, () => app);
    }
    return map.values.toList();
  }

  Future<List<RemoteApp>> _fetchAlsarayApps({String search = ''}) async {
    final uri = Uri.parse(_alsarayApi);
    final response = await _jsonGet(uri);
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        _extractError(
          body,
          fallback: 'تعذر تحميل مكتبة السراي (${response.statusCode})',
        ),
        uri: uri,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const FormatException('استجابة مكتبة السراي غير صالحة');
    }

    if (decoded is! Map || decoded['ok'] != true || decoded['apps'] is! List) {
      throw const FormatException('استجابة مكتبة السراي غير صالحة');
    }

    final term = search.trim().toLowerCase();
    final apps = <RemoteApp>[];

    for (final raw in (decoded['apps'] as List)) {
      if (raw is! Map) continue;
      final source = Map<String, dynamic>.from(raw);

      if (term.isNotEmpty) {
        final haystack = [
          source['name'],
          source['developer'],
          source['description'],
          source['bundle_id'],
          source['category'],
        ].map((e) => (e ?? '').toString()).join(' ').toLowerCase();
        if (!haystack.contains(term)) continue;
      }

      final originalId = (source['id'] ?? '').toString();
      final name = (source['name'] ?? '').toString();
      final mapped = <String, dynamic>{
        'id': 'alsaray:$originalId',
        'slug': originalId.isEmpty ? name : originalId,
        'name': name,
        'name_ar': name,
        'subtitle': (source['description'] ?? '').toString(),
        'subtitle_ar': (source['description'] ?? '').toString(),
        'developer_name': (source['developer'] ?? '').toString(),
        'bundle_id': (source['bundle_id'] ?? '').toString(),
        'version': (source['version'] ?? '').toString(),
        'category': (source['category'] ?? '').toString(),
        'size': source['size'] ?? 0,
        'icon_url': (source['icon_url'] ?? '').toString(),
        'download_url': (source['ipa_url'] ?? '').toString(),
        'storage_type': 'alsaray',
        'screenshots': source['screenshots'] ?? const <String>[],
        'created_at': (source['created_at'] ?? source['updated_at'] ?? '').toString(),
        'download_count': 0,
      };
      apps.add(RemoteApp.fromJson(mapped));
    }

    apps.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return apps;
  }

  Future<List<RemoteApp>> _fetchZsignApps({String search = ''}) async {
    final now = DateTime.now();
    var apps = _zsignCache;
    if (apps == null ||
        _zsignCacheAt == null ||
        now.difference(_zsignCacheAt!) >= _zsignCacheDuration) {
      final uri = Uri.parse(_zsignSource);
      final response = await _jsonGet(uri);
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          _extractError(
            body,
            fallback: 'تعذر تحميل مكتبة Zsign (${response.statusCode})',
          ),
          uri: uri,
        );
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        throw const FormatException('استجابة مكتبة Zsign غير صالحة');
      }

      dynamic rawApps;
      if (decoded is Map) {
        rawApps = decoded['apps'];
      } else if (decoded is List) {
        rawApps = decoded;
      }
      if (rawApps is! List) {
        throw const FormatException('استجابة مكتبة Zsign غير صالحة');
      }

      final parsed = <RemoteApp>[];
      for (var index = 0; index < rawApps.length; index++) {
        final raw = rawApps[index];
        if (raw is! Map) continue;
        final source = Map<String, dynamic>.from(raw);

        Map<String, dynamic> version = const <String, dynamic>{};
        final versions = source['versions'];
        if (versions is List) {
          for (final candidate in versions) {
            if (candidate is Map) {
              version = Map<String, dynamic>.from(candidate);
              break;
            }
          }
        }

        final name = _firstText(source, const ['name', 'title', 'displayName', 'appName']);
        final bundleId = _firstText(
          source,
          const ['bundleIdentifier', 'bundleID', 'bundle_id', 'bundleId', 'identifier'],
        );
        final appVersion = _firstText(
          version,
          const ['version', 'versionString', 'shortVersion', 'bundleVersion'],
          fallback: _firstText(source, const ['version', 'versionString']),
        );
        final developer = _firstText(
          source,
          const ['developerName', 'developer_name', 'developer'],
        );
        final subtitle = _firstText(
          source,
          const [
            'localizedDescription',
            'description',
            'subtitle',
          ],
        );
        final category = _firstText(
          source,
          const ['category', 'categoryName', 'genre'],
        );
        final icon = _absoluteUrl(
          _firstText(source, const ['iconURL', 'iconUrl', 'icon_url', 'icon', 'image', 'imageURL', 'artworkURL']),
          base: uri,
        );
        final download = _absoluteUrl(
          _firstText(
            version,
            const ['downloadURL', 'downloadUrl', 'download_url', 'url'],
            fallback: _firstText(
              source,
              const ['downloadURL', 'downloadUrl', 'download_url', 'ipa_url'],
            ),
          ),
          base: uri,
        );
        final size = _firstInt(
          version,
          const ['size', 'fileSize', 'file_size'],
          fallback: _firstInt(source, const ['size', 'fileSize', 'file_size']),
        );
        final screenshots = _zsignScreenshots(source, version, uri);
        final createdAt = _firstDate(
          version,
          const ['date', 'created_at', 'updated_at', 'releaseDate'],
          fallback: _firstDate(
            source,
            const ['date', 'created_at', 'updated_at', 'releaseDate'],
          ),
        );
        final sourceId = _firstText(source, const ['id', 'identifier']);
        final stableId = bundleId.isNotEmpty
            ? bundleId
            : (sourceId.isNotEmpty
                ? sourceId
                : '${name.isEmpty ? 'app' : name}:$index');

        parsed.add(
          RemoteApp(
            id: 'zsign:$stableId',
            slug: sourceId.isNotEmpty ? sourceId : stableId,
            name: name,
            nameAr: name,
            subtitle: subtitle,
            subtitleAr: subtitle,
            developerName: developer,
            bundleId: bundleId,
            version: appVersion,
            category: category,
            size: size,
            iconUrl: icon,
            downloadUrl: download.isEmpty ? null : download,
            storageType: 'zsign',
            screenshots: screenshots,
            createdAt: createdAt,
            downloadCount: 0,
          ),
        );
      }

      apps = parsed;
      _zsignCache = parsed;
      _zsignCacheAt = now;
    }

    final loadedApps = apps ?? const <RemoteApp>[];
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return List<RemoteApp>.from(loadedApps);
    return loadedApps.where((app) {
      final haystack = [
        app.name,
        app.nameAr,
        app.subtitle,
        app.subtitleAr,
        app.developerName,
        app.bundleId,
        app.category,
      ].join(' ').toLowerCase();
      return haystack.contains(term);
    }).toList();
  }


  Future<int> _ensureNsignMetadata() async {
    _invalidateNsignCacheIfNeeded();
    if (_nsignTotalApps != null && _nsignPageSize != null) {
      return _nsignTotalApps!;
    }
    await _fetchNsignPage(1);
    return _nsignTotalApps ?? 0;
  }

  void _invalidateNsignCacheIfNeeded() {
    final now = DateTime.now();
    if (_nsignCacheAt == null ||
        now.difference(_nsignCacheAt!) >= _nsignCacheDuration) {
      _nsignPageCache.clear();
      _nsignTotalApps = null;
      _nsignPageSize = null;
      _nsignCacheAt = now;
    }
  }

  Future<List<RemoteApp>> _fetchNsignPage(int page) async {
    _invalidateNsignCacheIfNeeded();
    final safePage = page < 1 ? 1 : page;
    final cached = _nsignPageCache[safePage];
    if (cached != null) return cached;

    final uri = Uri.parse(_nsignApi).replace(
      queryParameters: <String, String>{'page': '$safePage'},
    );
    final decoded = await _nsignRequest(uri);
    final rawApps = _appstarAppsList(decoded);
    final parsed = _parseNsignApps(rawApps, uri);

    _nsignPageCache[safePage] = parsed;
    if (safePage == 1 && parsed.isNotEmpty) _nsignPageSize = parsed.length;
    _nsignTotalApps ??= _nsignTotal(decoded, fallback: parsed.length);
    return parsed;
  }

  int _nsignTotal(dynamic decoded, {required int fallback}) {
    if (decoded is Map) {
      for (final key in const ['total_all_apps', 'total', 'count', 'total_apps']) {
        final value = decoded[key];
        if (value is num && value.toInt() > 0) return value.toInt();
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null && parsed > 0) return parsed;
      }
      final nord = int.tryParse((decoded['nord_apps_count'] ?? '').toString()) ?? 0;
      final db = int.tryParse((decoded['db_apps_count'] ?? '').toString()) ?? 0;
      if (nord + db > 0) return nord + db;
      final data = decoded['data'];
      if (data is Map) return _nsignTotal(data, fallback: fallback);
    }
    return fallback;
  }

  Future<List<RemoteApp>> _fetchNsignSlice({
    required int offset,
    required int limit,
  }) async {
    if (limit <= 0) return const <RemoteApp>[];
    await _ensureNsignMetadata();
    final pageSize = _nsignPageSize ?? 0;
    if (pageSize <= 0) return const <RemoteApp>[];

    final firstPage = (offset ~/ pageSize) + 1;
    final firstIndex = offset % pageSize;
    final result = <RemoteApp>[];
    var page = firstPage;
    var index = firstIndex;

    while (result.length < limit) {
      final rows = await _fetchNsignPage(page);
      if (rows.isEmpty || index >= rows.length) break;
      final needed = limit - result.length;
      result.addAll(rows.skip(index).take(needed));
      if (rows.length < pageSize) break;
      page++;
      index = 0;
    }
    return result;
  }

  Future<List<RemoteApp>> _fetchNsignSearch(String search) async {
    final term = search.trim();
    if (term.isEmpty) return const <RemoteApp>[];
    final uri = Uri.parse(_nsignApi).replace(
      queryParameters: <String, String>{'page': '1', 'search': term},
    );
    final decoded = await _nsignRequest(uri);
    final results = _parseNsignApps(_appstarAppsList(decoded), uri);
    final lower = term.toLowerCase();
    return results.where((app) {
      final haystack = <String>[
        app.name,
        app.nameAr,
        app.subtitle,
        app.subtitleAr,
        app.developerName,
        app.bundleId,
        app.category,
      ].join(' ').toLowerCase();
      return haystack.contains(lower);
    }).toList();
  }

  Future<dynamic> _nsignRequest(Uri uri) async {
    final response = await _jsonGet(uri);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        _extractError(
          body,
          fallback: 'تعذر تحميل مكتبة NSign (${response.statusCode})',
        ),
        uri: uri,
      );
    }
    try {
      return jsonDecode(body);
    } catch (_) {
      throw const FormatException('استجابة مكتبة NSign غير صالحة');
    }
  }

  List<RemoteApp> _parseNsignApps(List<dynamic> rawApps, Uri base) {
    final apps = <RemoteApp>[];
    for (var index = 0; index < rawApps.length; index++) {
      final raw = rawApps[index];
      if (raw is! Map) continue;
      final source = Map<String, dynamic>.from(raw);

      final name = _firstText(source, const ['name', 'title', 'displayName', 'appName']);
      final sourceId = _firstText(source, const ['id', 'appID', 'identifier', 'slug']);
      final bundleId = _firstText(
        source,
        const ['bundleID', 'bundle_id', 'bundleIdentifier', 'bundleId'],
      );
      final version = _firstText(
        source,
        const ['version', 'bundle_version', 'bundleVersion'],
      );
      final descriptionAr = _firstText(
        source,
        const ['localizedDescription_ar', 'localizedDescription', 'description', 'subtitle'],
      );
      final descriptionEn = _firstText(
        source,
        const ['localizedDescription_en', 'localizedDescription', 'description', 'subtitle'],
        fallback: descriptionAr,
      );
      final category = _firstText(
        source,
        const ['category_ar', 'category_en', 'category', 'type'],
      );
      final developer = _firstText(
        source,
        const ['developerName', 'developer_name', 'developer'],
      );
      final icon = _absoluteUrl(
        _firstText(source, const ['iconURL', 'icon_url', 'iconUrl', 'imageURL', 'icon']),
        base: base,
      );
      final download = _absoluteUrl(
        _firstText(
          source,
          const ['downloadURL', 'download_url', 'downloadUrl', 'dohaveURL', 'ipa_url', 'url'],
        ),
        base: base,
      );
      final size = _firstInt(source, const ['size', 'fileSize', 'file_size']);
      final createdAt = _firstDate(
        source,
        const ['versionDate', 'date', 'created_at', 'updated_at'],
      );
      final screenshots = _zsignScreenshots(source, const <String, dynamic>{}, base);
      final stableId = sourceId.isNotEmpty
          ? sourceId
          : (bundleId.isNotEmpty ? bundleId : '${name.isEmpty ? 'app' : name}:$index');

      apps.add(RemoteApp(
        id: 'nsign:$stableId',
        slug: sourceId.isNotEmpty ? sourceId : stableId,
        name: name,
        nameAr: name,
        subtitle: descriptionEn,
        subtitleAr: descriptionAr.isEmpty ? descriptionEn : descriptionAr,
        developerName: developer,
        bundleId: bundleId,
        version: version,
        category: category,
        size: size,
        iconUrl: icon,
        downloadUrl: download.isEmpty ? null : download,
        storageType: 'nsign',
        screenshots: screenshots,
        createdAt: createdAt,
        downloadCount: 0,
      ));
    }
    return apps;
  }

  Future<List<RemoteApp>> _fetchCustomSource(
    LibrarySourceConfig source, {
    String search = '',
  }) async {
    final now = DateTime.now();
    final cachedAt = _customSourceCacheAt[source.id];
    var apps = _customSourceCache[source.id];
    if (apps == null || cachedAt == null ||
        now.difference(cachedAt) >= _customSourceCacheDuration) {
      final uri = Uri.parse(source.url);
      final response = await _jsonGet(uri);
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('تعذر تحميل المصدر ${source.name} (${response.statusCode})', uri: uri);
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        throw FormatException('رابط المصدر ${source.name} لا يعيد JSON صالحًا');
      }
      final rawApps = _customAppsList(decoded);
      apps = _parseCustomApps(source, rawApps, uri);
      _customSourceCache[source.id] = apps;
      _customSourceCacheAt[source.id] = now;
    }

    final loadedApps = apps ?? const <RemoteApp>[];
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return List<RemoteApp>.from(loadedApps);
    return loadedApps.where((app) {
      final haystack = <String>[
        app.name,
        app.nameAr,
        app.subtitle,
        app.subtitleAr,
        app.developerName,
        app.bundleId,
        app.category,
      ].join(' ').toLowerCase();
      return haystack.contains(term);
    }).toList();
  }

  List<dynamic> _customAppsList(dynamic decoded) {
    final direct = _findAppList(decoded);
    if (direct != null) return direct;
    throw const FormatException(
      'صيغة المصدر غير مدعومة. يدعم بومة JSON العادي وAltStore وFeather وقوائم apps/data/items/results/packages',
    );
  }

  List<dynamic>? _findAppList(dynamic value, {int depth = 0}) {
    if (depth > 5) return null;
    if (value is List) {
      if (value.isEmpty) return value;
      final maps = value.whereType<Map>().toList();
      if (maps.isNotEmpty && maps.any(_looksLikeAppMap)) return value;
      for (final item in value) {
        final found = _findAppList(item, depth: depth + 1);
        if (found != null && found.isNotEmpty) return found;
      }
      return maps.isNotEmpty ? value : null;
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      for (final key in const [
        'apps', 'applications', 'items', 'results', 'packages', 'releases',
        'data', 'catalog', 'library', 'repository', 'source',
      ]) {
        if (!map.containsKey(key)) continue;
        final found = _findAppList(map[key], depth: depth + 1);
        if (found != null) return found;
      }
      for (final nested in map.values) {
        final found = _findAppList(nested, depth: depth + 1);
        if (found != null && found.isNotEmpty) return found;
      }
    }
    return null;
  }

  bool _looksLikeAppMap(Map value) {
    final keys = value.keys.map((e) => e.toString().toLowerCase()).toSet();
    final hasName = keys.contains('name') || keys.contains('title');
    final hasBundle = keys.contains('bundleidentifier') || keys.contains('bundleid') || keys.contains('bundle_id');
    final hasDownload = keys.any((k) => k.contains('download') || k.contains('ipa') || k == 'url');
    final hasVersion = keys.contains('version') || keys.contains('versions');
    return hasName && (hasBundle || hasDownload || hasVersion);
  }

  List<RemoteApp> _parseCustomApps(
    LibrarySourceConfig config,
    List<dynamic> rawApps,
    Uri base,
  ) {
    final result = <RemoteApp>[];
    for (var index = 0; index < rawApps.length; index++) {
      final raw = rawApps[index];
      if (raw is! Map) continue;
      final source = Map<String, dynamic>.from(raw);
      Map<String, dynamic> versionData = const <String, dynamic>{};
      final versions = source['versions'];
      if (versions is List && versions.isNotEmpty && versions.first is Map) {
        versionData = Map<String, dynamic>.from(versions.first as Map);
      }

      final name = _firstText(source, const ['name', 'title', 'displayName', 'appName']);
      final bundleId = _firstText(source, const ['bundleIdentifier', 'bundleID', 'bundle_id', 'bundleId']);
      final sourceId = _firstText(source, const ['id', 'slug', 'identifier']);
      final appVersion = _firstText(
        versionData,
        const ['version', 'bundleVersion'],
        fallback: _firstText(source, const ['version', 'bundle_version', 'bundleVersion']),
      );
      final description = _firstText(
        source,
        const ['localizedDescription_ar', 'localizedDescription', 'description', 'subtitle'],
      );
      final descriptionEn = _firstText(
        source,
        const ['localizedDescription_en', 'localizedDescription', 'description', 'subtitle'],
        fallback: description,
      );
      final developer = _firstText(source, const ['developerName', 'developer_name', 'developer', 'author']);
      final category = _firstText(source, const ['category_ar', 'category_en', 'category', 'categoryName', 'genre']);
      final icon = _absoluteUrl(
        _firstText(source, const ['iconURL', 'iconUrl', 'icon_url', 'icon', 'image', 'imageURL', 'artworkURL']),
        base: base,
      );
      final download = _absoluteUrl(
        _firstText(
          versionData,
          const ['downloadURL', 'downloadUrl', 'download_url', 'url', 'ipa_url', 'ipaUrl', 'file', 'fileURL', 'link'],
          fallback: _firstText(source, const ['downloadURL', 'downloadUrl', 'download_url', 'dohaveURL', 'url', 'ipa_url']),
        ),
        base: base,
      );
      final size = _firstInt(
        versionData,
        const ['size', 'fileSize', 'file_size'],
        fallback: _firstInt(source, const ['size', 'fileSize', 'file_size']),
      );
      final createdAt = _firstDate(
        versionData,
        const ['date', 'versionDate', 'created_at', 'updated_at', 'releaseDate'],
        fallback: _firstDate(source, const ['date', 'versionDate', 'created_at', 'updated_at', 'releaseDate']),
      );
      final screenshots = _zsignScreenshots(source, versionData, base);
      final stableId = sourceId.isNotEmpty
          ? sourceId
          : (bundleId.isNotEmpty ? bundleId : '${name.isEmpty ? 'app' : name}:$index');

      result.add(RemoteApp(
        id: '${config.id}:$stableId',
        slug: sourceId.isNotEmpty ? sourceId : stableId,
        name: name,
        nameAr: name,
        subtitle: descriptionEn,
        subtitleAr: description,
        developerName: developer,
        bundleId: bundleId,
        version: appVersion,
        category: category,
        size: size,
        iconUrl: icon,
        downloadUrl: download.isEmpty ? null : download,
        storageType: config.id,
        screenshots: screenshots,
        createdAt: createdAt,
        downloadCount: 0,
      ));
    }
    return result;
  }


  Future<int> _ensureAppstarMetadata() async {
    _invalidateAppstarCacheIfNeeded();
    if (_appstarTotalApps != null && _appstarPageSize != null) {
      return _appstarTotalApps!;
    }
    await _fetchAppstarPage(1);
    return _appstarTotalApps ?? 0;
  }

  void _invalidateAppstarCacheIfNeeded() {
    final now = DateTime.now();
    if (_appstarCacheAt == null ||
        now.difference(_appstarCacheAt!) >= _appstarCacheDuration) {
      _appstarPageCache.clear();
      _appstarTotalApps = null;
      _appstarPageSize = null;
      _appstarCacheAt = now;
    }
  }

  Future<List<RemoteApp>> _fetchAppstarPage(int page) async {
    _invalidateAppstarCacheIfNeeded();
    final safePage = page < 1 ? 1 : page;
    final cached = _appstarPageCache[safePage];
    if (cached != null) return cached;

    final uri = Uri.parse(_appstarApi).replace(
      queryParameters: <String, String>{'page': '$safePage'},
    );
    print('[Appstar] Request page: $safePage -> $uri');
    final decoded = await _appstarRequest(uri);
    final rawApps = _appstarAppsList(decoded);
    final parsed = _parseAppstarApps(rawApps, uri);
    print('[Appstar] Page $safePage loaded: ${parsed.length} apps');

    _appstarPageCache[safePage] = parsed;
    if (safePage == 1 && parsed.isNotEmpty) _appstarPageSize = parsed.length;
    _appstarTotalApps ??= _appstarTotal(decoded, fallback: parsed.length);
    print('[Appstar] Total apps: ${_appstarTotalApps ?? 0} | Page size: ${_appstarPageSize ?? parsed.length}');
    return parsed;
  }

  Future<List<RemoteApp>> _fetchAppstarSlice({
    required int offset,
    required int limit,
  }) async {
    if (limit <= 0) return const <RemoteApp>[];
    await _ensureAppstarMetadata();
    final pageSize = _appstarPageSize ?? 0;
    if (pageSize <= 0) return const <RemoteApp>[];

    final firstPage = (offset ~/ pageSize) + 1;
    final firstIndex = offset % pageSize;
    final result = <RemoteApp>[];
    var page = firstPage;
    var index = firstIndex;

    while (result.length < limit) {
      final rows = await _fetchAppstarPage(page);
      if (rows.isEmpty || index >= rows.length) break;
      final needed = limit - result.length;
      result.addAll(rows.skip(index).take(needed));
      if (rows.length < pageSize) break;
      page++;
      index = 0;
    }
    return result;
  }

  Future<List<RemoteApp>> _fetchAppstarSearch(String search) async {
    final term = search.trim();
    if (term.isEmpty) return const <RemoteApp>[];
    final uri = Uri.parse(_appstarApi).replace(
      queryParameters: <String, String>{'search': term},
    );
    print('[Appstar] Search: "$term" -> $uri');
    final decoded = await _appstarRequest(uri);
    final results = _parseAppstarApps(_appstarAppsList(decoded), uri);
    print('[Appstar] Search "$term" returned: ${results.length} apps');
    return results;
  }

  Future<dynamic> _appstarRequest(Uri uri) async {
    print('[Appstar] Connecting: $uri');
    final response = await _jsonGet(uri);
    print('[Appstar] HTTP status: ${response.statusCode}');
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        _extractError(
          body,
          fallback: 'تعذر تحميل مكتبة Appstar (${response.statusCode})',
        ),
        uri: uri,
      );
    }
    try {
      return jsonDecode(body);
    } catch (e) {
      print('[Appstar] JSON parse error: $e');
      rethrow;
    }
  }

  List<dynamic> _appstarAppsList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final apps = decoded['apps'];
      if (apps is List) return apps;
      final data = decoded['data'];
      if (data is List) return data;
      if (data is Map && data['apps'] is List) return data['apps'] as List;
    }
    throw const FormatException('استجابة مكتبة Appstar غير صالحة');
  }

  int _appstarTotal(dynamic decoded, {required int fallback}) {
    if (decoded is Map) {
      for (final key in const [
        'total_apps',
        'total_all_apps',
        'total',
        'count',
      ]) {
        final value = decoded[key];
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      final data = decoded['data'];
      if (data is Map) return _appstarTotal(data, fallback: fallback);
    }
    return fallback;
  }

  List<RemoteApp> _parseAppstarApps(List<dynamic> rawApps, Uri base) {
    final apps = <RemoteApp>[];
    for (var index = 0; index < rawApps.length; index++) {
      final raw = rawApps[index];
      if (raw is! Map) continue;
      final source = Map<String, dynamic>.from(raw);

      final name = _firstText(source, const ['name', 'title', 'displayName', 'appName']);
      final bundleId = _firstText(
        source,
        const ['bundleID', 'bundle_id', 'bundleIdentifier', 'bundleId'],
      );
      final version = _firstText(
        source,
        const ['version', 'bundle_version', 'bundleVersion'],
      );
      final description = _firstText(
        source,
        const [
          'localizedDescription_ar',
          'localizedDescription_en',
          'localizedDescription',
          'description',
          'subtitle',
        ],
      );
      final category = _firstText(
        source,
        const ['category_ar', 'category_en', 'category', 'type'],
      );
      final developer = _firstText(
        source,
        const ['developerName', 'developer_name', 'developer'],
      );
      final icon = _absoluteUrl(
        _firstText(source, const ['iconURL', 'icon_url', 'iconUrl', 'imageURL']),
        base: base,
      );
      final download = _absoluteUrl(
        _firstText(
          source,
          const [
            'downloadURL',
            'download_url',
            'downloadUrl',
            'dohaveURL',
            'url',
          ],
        ),
        base: base,
      );
      final size = _firstInt(
        source,
        const ['size', 'fileSize', 'file_size'],
      );
      final createdAt = _firstDate(
        source,
        const ['versionDate', 'date', 'created_at', 'updated_at'],
      );
      final screenshots = _zsignScreenshots(source, const <String, dynamic>{}, base);
      final sourceId = _firstText(source, const ['id', 'appID', 'identifier']);
      final stableId = bundleId.isNotEmpty
          ? bundleId
          : (sourceId.isNotEmpty
              ? sourceId
              : '${name.isEmpty ? 'app' : name}:$index');

      apps.add(RemoteApp(
        id: 'appstar:$stableId',
        slug: sourceId.isNotEmpty ? sourceId : stableId,
        name: name,
        nameAr: name,
        subtitle: description,
        subtitleAr: description,
        developerName: developer,
        bundleId: bundleId,
        version: version,
        category: category,
        size: size,
        iconUrl: icon,
        downloadUrl: download.isEmpty ? null : download,
        storageType: 'appstar',
        screenshots: screenshots,
        createdAt: createdAt,
        downloadCount: 0,
      ));
    }
    return apps;
  }

  String _firstText(
    Map<String, dynamic> source,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  int _firstInt(
    Map<String, dynamic> source,
    List<String> keys, {
    int fallback = 0,
  }) {
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value.toInt();
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final direct = int.tryParse(text);
      if (direct != null) return direct;
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(KB|MB|GB)', caseSensitive: false)
          .firstMatch(text);
      if (match != null) {
        final amount = double.tryParse(match.group(1) ?? '') ?? 0;
        switch ((match.group(2) ?? '').toUpperCase()) {
          case 'GB':
            return (amount * 1024 * 1024 * 1024).round();
          case 'MB':
            return (amount * 1024 * 1024).round();
          case 'KB':
            return (amount * 1024).round();
        }
      }
    }
    return fallback;
  }

  DateTime? _firstDate(
    Map<String, dynamic> source,
    List<String> keys, {
    DateTime? fallback,
  }) {
    for (final key in keys) {
      final text = source[key]?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  String _absoluteUrl(String value, {required Uri base}) {
    final text = value.trim();
    if (text.isEmpty) return '';
    final parsed = Uri.tryParse(text);
    if (parsed == null) return text;
    if (parsed.hasScheme) return parsed.toString();
    return base.resolveUri(parsed).toString();
  }

  List<String> _zsignScreenshots(
    Map<String, dynamic> source,
    Map<String, dynamic> version,
    Uri base,
  ) {
    final urls = <String>[];
    void collect(dynamic value) {
      if (value is String) {
        final url = _absoluteUrl(value, base: base);
        if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
        return;
      }
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        final candidate = _firstText(
          map,
          const ['url', 'imageURL', 'imageUrl', 'image_url', 'src'],
        );
        if (candidate.isNotEmpty) collect(candidate);
      }
    }

    for (final key in const [
      'screenshots',
      'screenshotURLs',
      'screenshotUrls',
      'screenshot_urls',
    ]) {
      collect(source[key]);
      collect(version[key]);
    }
    return urls;
  }

  Future<List<String>> fetchBoomaCategories({int sampleSize = 240}) async {
    final apps = await fetchApps(offset: 0, limit: sampleSize, search: '');
    final categories = apps
        .map((app) => app.category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  Future<Uri> resolveDownload(RemoteApp app) async {
    final direct = app.downloadUrl?.trim() ?? '';
    if (direct.isNotEmpty) {
      final parsed = Uri.tryParse(direct);
      if (parsed != null && parsed.hasScheme) return parsed;
    }

    if (app.storageType == 'nsign') {
      return _resolveNsignDownload(app);
    }

    if (app.storageType == 'zsign') {
      throw const HttpException('مكتبة Zsign لم ترجع رابط IPA صالحًا لهذا التطبيق');
    }

    if (app.storageType == 'appstar') {
      throw const HttpException('مكتبة Appstar لم ترجع رابط IPA صالحًا لهذا التطبيق');
    }

    if (app.storageType.startsWith('custom:')) {
      throw const HttpException('المصدر المضاف لم يرجع رابط IPA مباشرًا لهذا التطبيق');
    }

    final uri = Uri.parse('$_proxyBase/download.php').replace(
      queryParameters: {
        'id': app.id,
        'json': '1',
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );

    final response = await _jsonGet(uri);
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        _extractError(body,
            fallback:
                'تعذر الحصول على رابط التنزيل (${response.statusCode})'),
        uri: uri,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const FormatException('استجابة رابط التنزيل غير صالحة');
    }

    if (decoded is! Map) {
      throw const FormatException('استجابة رابط التنزيل غير صالحة');
    }

    final data = Map<String, dynamic>.from(decoded);
    final url = (data['url'] ?? '').toString().trim();

    if (data['ok'] != true || url.isEmpty) {
      throw HttpException(
        (data['detail'] ?? data['error'] ?? 'لم يرجع المصدر رابط IPA صالحًا')
            .toString(),
        uri: uri,
      );
    }

    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) {
      throw const FormatException('رابط IPA المستلم غير صالح');
    }
    return parsed;
  }


  Future<Uri> _resolveNsignDownload(RemoteApp app) async {
    // Cinema Max is part of the NSign/iPAsOON catalogue but its public catalog
    // row intentionally omits a download URL. Keep the verified installation
    // package as a direct fallback so the app can always be downloaded.
    if (app.bundleId == 'ipasoon.Cinema-Max') {
      return Uri.parse('https://night-script.top/js/output/4262_HSBCBankplc_CinemaMax_10_ipasoonCinemaMax.signed.ipa');
    }
    final sourceId = app.slug.trim().isNotEmpty
        ? app.slug.trim()
        : app.id.replaceFirst(RegExp(r'^nsign:'), '');
    final uri = Uri.parse(_nsignDownloadApi).replace(
      queryParameters: <String, String>{'id': sourceId},
    );
    final response = await _jsonGet(uri);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        _extractError(body, fallback: 'تعذر الحصول على رابط NSign (${response.statusCode})'),
        uri: uri,
      );
    }

    String url = '';
    final plain = body.trim();
    final plainUri = Uri.tryParse(plain);
    if (plainUri != null && plainUri.hasScheme && (plainUri.scheme == 'http' || plainUri.scheme == 'https')) {
      url = plain;
    } else {
      try {
        url = _findDownloadUrl(jsonDecode(body));
      } catch (_) {}
    }
    if (url.isEmpty) {
      throw HttpException('لم يرجع NSign رابط IPA صالحًا لهذا التطبيق', uri: uri);
    }
    final absolute = _absoluteUrl(url, base: uri);
    final parsed = Uri.tryParse(absolute);
    if (parsed == null || !parsed.hasScheme) {
      throw FormatException('رابط NSign المستلم غير صالح: $absolute');
    }
    return parsed;
  }

  String _findDownloadUrl(dynamic value) {
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return '';
      final lower = text.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://') || lower.endsWith('.ipa')) {
        return text;
      }
      return '';
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final kind = (map['kind'] ?? '').toString().toLowerCase();
      if (kind == 'software-package' && map['url'] != null) {
        final found = _findDownloadUrl(map['url']);
        if (found.isNotEmpty) return found;
      }
      for (final key in const [
        'downloadURL', 'downloadUrl', 'download_url', 'dohaveURL',
        'ipa_url', 'ipaUrl', 'download', 'fileURL', 'file_url', 'link',
      ]) {
        if (!map.containsKey(key)) continue;
        final found = _findDownloadUrl(map[key]);
        if (found.isNotEmpty) return found;
      }
      if (map['url'] is String) {
        final candidate = (map['url'] as String).trim();
        final lower = candidate.toLowerCase();
        if (lower.contains('.ipa') || lower.contains('download')) return candidate;
      }
      for (final nestedKey in const ['data', 'app', 'result', 'version', 'assets', 'items']) {
        if (!map.containsKey(nestedKey)) continue;
        final found = _findDownloadUrl(map[nestedKey]);
        if (found.isNotEmpty) return found;
      }
    }
    if (value is List) {
      for (final item in value) {
        final found = _findDownloadUrl(item);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }

  Future<String> downloadIpa(
    RemoteApp app, {
    required void Function(int received, int total) onProgress,
    IpaDownloadControl? control,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'Imports'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final safeName = _safeFileName(app.name.isEmpty ? app.slug : app.name);
    final safeVersion = _safeFileName(app.version);
    final filename =
        '${safeName.isEmpty ? 'Application' : safeName}${safeVersion.isEmpty ? '' : '-$safeVersion'}-${DateTime.now().millisecondsSinceEpoch}.ipa';
    final file = File(p.join(dir.path, filename));

    // First try: use the latest direct URL returned by the active source.
    var directUri = await resolveDownload(app);
    var result = await _downloadUrlToFile(
      directUri,
      file,
      app.size,
      onProgress,
      control: control,
    );

    // A release-assets link can be short-lived/stale. If the CDN rejects it,
    // ask the resolver for a fresh URL and retry once.
    if (!result.ok && (result.statusCode == 403 || result.statusCode == 404)) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
      directUri = await resolveDownload(app);
      result = await _downloadUrlToFile(
        directUri,
        file,
        app.size,
        onProgress,
        control: control,
      );
    }

    // Final fallback: let our server fetch/stream the IPA. Nothing is stored
    // on the server; it simply relays the bytes. This fixes sources that reject
    // direct iOS/CDN requests.
    if (!result.ok &&
        app.storageType != 'alsaray' &&
        app.storageType != 'zsign' &&
        app.storageType != 'appstar' &&
        app.storageType != 'nsign' &&
        !app.storageType.startsWith('custom:') &&
        (result.statusCode == 403 || result.statusCode == 404)) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      final proxyUri = Uri.parse('$_proxyBase/download.php').replace(
        queryParameters: {
          'id': app.id,
          'stream': '1',
          't': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      result = await _downloadUrlToFile(
        proxyUri,
        file,
        app.size,
        onProgress,
        fromProxy: true,
        control: control,
      );
    }

    if (!result.ok) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw HttpException(
        'فشل تنزيل ملف IPA (${result.statusCode}) - ${result.detail}',
        uri: result.uri,
      );
    }

    if (!await file.exists() || await file.length() < 1024) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw const HttpException('الملف الذي تم تنزيله فارغ أو غير صالح');
    }

    return file.path;
  }

  Future<_DownloadResult> _downloadUrlToFile(
    Uri uri,
    File file,
    int fallbackTotal,
    void Function(int received, int total) onProgress, {
    bool fromProxy = false,
    IpaDownloadControl? control,
  }) async {
    HttpClientResponse? response;
    IOSink? sink;
    try {
      if (control?.isCancelled == true) {
        return _DownloadResult(false, -1, uri, 'cancelled');
      }
      final request = await _client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 12;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        fromProxy ? '*/*' : 'application/octet-stream,*/*;q=0.9',
      );
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set('Pragma', 'no-cache');
      if (!fromProxy &&
          (uri.host == 'github.com' ||
              uri.host.endsWith('.github.com') ||
              uri.host == 'githubusercontent.com' ||
              uri.host.endsWith('.githubusercontent.com'))) {
        request.headers.set(HttpHeaders.refererHeader, 'https://github.com/');
      }

      response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        return _DownloadResult(
          false,
          response.statusCode,
          uri,
          _extractError(body,
              fallback: 'HTTP ${response.statusCode} من مصدر الملف'),
        );
      }

      if (control?.isCancelled == true) {
        return _DownloadResult(false, -1, uri, 'cancelled');
      }

      sink = file.openWrite();
      var received = 0;
      final total =
          response.contentLength > 0 ? response.contentLength : fallbackTotal;

      final done = Completer<void>();
      late final StreamSubscription<List<int>> subscription;
      subscription = response.listen(
        (chunk) {
          sink!.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        },
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      control?._attach(subscription);
      try {
        if (control == null) {
          await done.future;
        } else {
          await Future.any<void>([done.future, control.cancelled]);
          if (control.isCancelled) {
            await subscription.cancel();
            await sink.flush();
            await sink.close();
            sink = null;
            try {
              if (await file.exists()) await file.delete();
            } catch (_) {}
            return _DownloadResult(false, -1, uri, 'cancelled');
          }
        }
      } finally {
        control?._detach(subscription);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      return _DownloadResult(true, response.statusCode, uri, 'ok');
    } on SocketException catch (e) {
      return _DownloadResult(false, 0, uri, 'SocketException: ${e.message}');
    } on HandshakeException catch (e) {
      return _DownloadResult(false, 0, uri, 'TLS: $e');
    } catch (e) {
      return _DownloadResult(false, 0, uri, e.toString());
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
    }
  }

  Future<HttpClientResponse> _jsonGet(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
    );
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    request.headers.set('Pragma', 'no-cache');
    return request.close();
  }

  String _extractError(String body, {required String fallback}) {
    if (body.trim().isEmpty) return fallback;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail =
            (decoded['detail'] ?? decoded['error'] ?? decoded['message'] ?? '')
                .toString()
                .trim();
        if (detail.isNotEmpty) return detail;
      }
    } catch (_) {}
    final clean = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isEmpty
        ? fallback
        : clean.substring(0, clean.length > 180 ? 180 : clean.length);
  }

  String _safeFileName(String value) => value
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void close() => _client.close(force: true);
}

class _DownloadResult {
  final bool ok;
  final int statusCode;
  final Uri uri;
  final String detail;

  const _DownloadResult(this.ok, this.statusCode, this.uri, this.detail);
}


class IpaDownloadControl {
  StreamSubscription<List<int>>? _subscription;
  bool _paused = false;
  bool _cancelled = false;
  final Completer<void> _cancelCompleter = Completer<void>();

  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;
  Future<void> get cancelled => _cancelCompleter.future;

  void pause() {
    if (_cancelled) return;
    _paused = true;
    _subscription?.pause();
  }

  void resume() {
    if (_cancelled) return;
    _paused = false;
    _subscription?.resume();
  }

  void toggle() => _paused ? resume() : pause();

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _paused = false;
    if (!_cancelCompleter.isCompleted) _cancelCompleter.complete();
    final sub = _subscription;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
  }

  void _attach(StreamSubscription<List<int>> subscription) {
    _subscription = subscription;
    if (_cancelled) {
      subscription.cancel();
      return;
    }
    if (_paused) subscription.pause();
  }

  void _detach(StreamSubscription<List<int>> subscription) {
    if (identical(_subscription, subscription)) _subscription = null;
  }
}
