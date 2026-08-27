import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/remote_app.dart';

class IpaLibraryService {
  static const String _proxyBase = 'https://scrptaty.com/apps/ipa';
  static const String _alsarayApi = 'https://scrptaty.com/apps/alsaray/api.php';
  static const String _zsignSource = 'https://appiraq.com/han.json';
  static const String _appstarApi = 'https://appstar.app/my/get-7md/Api.php';

  List<RemoteApp>? _zsignCache;
  DateTime? _zsignCacheAt;
  static const Duration _zsignCacheDuration = Duration(minutes: 5);

  final Map<int, List<RemoteApp>> _appstarPageCache = <int, List<RemoteApp>>{};
  DateTime? _appstarCacheAt;
  int? _appstarTotalApps;
  int? _appstarPageSize;
  static const Duration _appstarCacheDuration = Duration(minutes: 5);

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  Future<List<RemoteApp>> fetchApps({
    int offset = 0,
    int limit = 60,
    String search = '',
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit <= 0 ? 60 : limit;
    final term = search.trim();

    List<RemoteApp> alsarayApps = const <RemoteApp>[];
    Object? alsarayError;
    try {
      alsarayApps = await _fetchAlsarayApps(search: term);
    } catch (e) {
      alsarayError = e;
    }

    List<RemoteApp> zsignApps = const <RemoteApp>[];
    try {
      zsignApps = await _fetchZsignApps(search: term);
    } catch (_) {
      // Zsign is an additional source. Keep the existing library working if
      // the source is temporarily unavailable.
    }

    // Search requests use Appstar's dedicated search endpoint because it can
    // return matches from the whole Appstar catalogue without walking every
    // page first.
    if (term.isNotEmpty) {
      List<RemoteApp> appstarApps = const <RemoteApp>[];
      try {
        appstarApps = await _fetchAppstarSearch(term);
      } catch (_) {
        // Appstar is optional and must not break the other sources.
      }

      final customApps = <RemoteApp>[
        ...alsarayApps,
        ...zsignApps,
        ...appstarApps,
      ];
      final result = <RemoteApp>[];
      if (safeOffset < customApps.length) {
        result.addAll(customApps.skip(safeOffset).take(safeLimit));
      }

      final remaining = safeLimit - result.length;
      if (remaining > 0) {
        final iosBoomOffset = safeOffset <= customApps.length
            ? 0
            : safeOffset - customApps.length;
        try {
          result.addAll(await _fetchIosBoomApps(
            offset: iosBoomOffset,
            limit: remaining,
            search: term,
          ));
        } catch (e) {
          if (result.isEmpty) {
            if (alsarayError != null) throw alsarayError;
            rethrow;
          }
        }
      }
      return result;
    }

    // Appstar exposes total_apps, so we can keep the complete catalogue
    // available with true pagination instead of downloading thousands of
    // records into memory on every refresh.
    int appstarCount = 0;
    try {
      appstarCount = await _ensureAppstarMetadata();
    } catch (_) {
      appstarCount = 0;
    }

    final prefixApps = <RemoteApp>[...alsarayApps, ...zsignApps];
    final prefixCount = prefixApps.length;
    final appstarStart = prefixCount;
    final iosBoomStart = prefixCount + appstarCount;
    final result = <RemoteApp>[];
    var cursor = safeOffset;

    if (cursor < prefixCount && result.length < safeLimit) {
      final available = prefixCount - cursor;
      final wanted = safeLimit - result.length;
      final take = wanted < available ? wanted : available;
      result.addAll(prefixApps.skip(cursor).take(take));
      cursor += take;
    }

    if (cursor < iosBoomStart && result.length < safeLimit && appstarCount > 0) {
      final rawAppstarOffset = cursor - appstarStart;
      final appstarOffset = rawAppstarOffset < 0
          ? 0
          : (rawAppstarOffset > appstarCount ? appstarCount : rawAppstarOffset);
      final available = appstarCount - appstarOffset;
      final wanted = safeLimit - result.length;
      final take = wanted < available ? wanted : available;
      try {
        final appstar = await _fetchAppstarSlice(
          offset: appstarOffset,
          limit: take,
        );
        result.addAll(appstar);
        cursor += appstar.length;
        // If the upstream API returned fewer rows than its advertised total,
        // skip to the next source rather than leaving pagination stuck.
        if (appstar.length < take) cursor = iosBoomStart;
      } catch (_) {
        cursor = iosBoomStart;
      }
    }

    final remaining = safeLimit - result.length;
    if (remaining > 0) {
      final iosBoomOffset = cursor <= iosBoomStart ? 0 : cursor - iosBoomStart;
      try {
        result.addAll(await _fetchIosBoomApps(
          offset: iosBoomOffset,
          limit: remaining,
          search: '',
        ));
      } catch (e) {
        if (result.isEmpty) {
          if (alsarayError != null) throw alsarayError;
          rethrow;
        }
      }
    }

    if (result.isEmpty && alsarayError != null && appstarCount == 0) {
      throw alsarayError;
    }
    return result;
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

        final name = _firstText(source, const ['name', 'title']);
        final bundleId = _firstText(
          source,
          const ['bundleIdentifier', 'bundle_id', 'bundleId'],
        );
        final appVersion = _firstText(
          version,
          const ['version', 'versionString', 'shortVersion'],
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
          _firstText(source, const ['iconURL', 'iconUrl', 'icon_url', 'icon']),
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

    final term = search.trim().toLowerCase();
    if (term.isEmpty) return List<RemoteApp>.from(apps);
    return apps.where((app) {
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

      final name = _firstText(source, const ['name', 'title']);
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

  Future<List<RemoteApp>> _fetchIosBoomApps({
    required int offset,
    required int limit,
    String search = '',
  }) async {
    if (limit <= 0) return const <RemoteApp>[];

    final query = <String, String>{
      'offset': '$offset',
      'limit': '$limit',
    };

    final term = search.trim();
    if (term.isNotEmpty) query['search'] = term;

    final uri = Uri.parse('$_proxyBase/library.php').replace(
      queryParameters: query,
    );

    final response = await _jsonGet(uri);
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        _extractError(
          body,
          fallback: 'تعذر تحميل مكتبة التطبيقات (${response.statusCode})',
        ),
        uri: uri,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const FormatException('استجابة المكتبة غير صالحة');
    }

    if (decoded is Map && decoded['ok'] == false) {
      throw HttpException(
        (decoded['detail'] ??
                decoded['error'] ??
                'تعذر تحميل مكتبة التطبيقات')
            .toString(),
        uri: uri,
      );
    }

    if (decoded is! List) {
      throw const FormatException('استجابة المكتبة غير صالحة');
    }

    return decoded
        .whereType<Map>()
        .map((e) => RemoteApp.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }


  Future<List<String>> fetchBoomaCategories({int sampleSize = 240}) async {
    final apps = await _fetchIosBoomApps(offset: 0, limit: sampleSize, search: '');
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

    if (app.storageType == 'zsign') {
      throw const HttpException('مكتبة Zsign لم ترجع رابط IPA صالحًا لهذا التطبيق');
    }

    if (app.storageType == 'appstar') {
      throw const HttpException('مكتبة Appstar لم ترجع رابط IPA صالحًا لهذا التطبيق');
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

    // First try: latest direct GitHub/release URL returned by iOSBoom.
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
