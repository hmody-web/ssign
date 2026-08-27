import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/remote_app.dart';

class IpaLibraryService {
  static const String _proxyBase = 'https://scrptaty.com/apps/ipa';
  static const String _alsarayApi = 'https://scrptaty.com/apps/alsaray/api.php';

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

    final result = <RemoteApp>[];
    final customCount = alsarayApps.length;

    // AlSaray is merged at the beginning of the same library. Pagination is
    // calculated as one logical list so custom apps are not repeated.
    if (safeOffset < customCount) {
      final take = safeLimit.clamp(0, customCount - safeOffset);
      result.addAll(
        alsarayApps.skip(safeOffset).take(take),
      );
    }

    final remaining = safeLimit - result.length;
    if (remaining > 0) {
      final iosBoomOffset =
          safeOffset <= customCount ? 0 : safeOffset - customCount;
      try {
        final iosBoom = await _fetchIosBoomApps(
          offset: iosBoomOffset,
          limit: remaining,
          search: term,
        );
        result.addAll(iosBoom);
      } catch (e) {
        // Keep the user's private library usable even when the external
        // source is temporarily unavailable.
        if (result.isEmpty) {
          if (alsarayError != null) rethrow;
          throw e;
        }
      }
    }

    if (result.isEmpty && alsarayError != null) {
      // If there were no external results either, surface the custom-source
      // error instead of silently returning an empty library.
      try {
        final probe = await _fetchIosBoomApps(
          offset: safeOffset,
          limit: safeLimit,
          search: term,
        );
        if (probe.isNotEmpty) return probe;
      } catch (_) {}
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
