import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/remote_app.dart';

class IpaLibraryService {
  static const String _proxyBase = 'https://scrptaty.com/apps/ipa';

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  Future<List<RemoteApp>> fetchApps({
    int offset = 0,
    int limit = 60,
    String search = '',
  }) async {
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
        _extractError(body,
            fallback:
                'تعذر تحميل مكتبة التطبيقات (${response.statusCode})'),
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
    if (!result.ok && (result.statusCode == 403 || result.statusCode == 404)) {
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
      if (!fromProxy) {
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
        await done.future;
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

  bool get isPaused => _paused;

  void pause() {
    _paused = true;
    _subscription?.pause();
  }

  void resume() {
    _paused = false;
    _subscription?.resume();
  }

  void toggle() => _paused ? resume() : pause();

  void _attach(StreamSubscription<List<int>> subscription) {
    _subscription = subscription;
    if (_paused) subscription.pause();
  }

  void _detach(StreamSubscription<List<int>> subscription) {
    if (identical(_subscription, subscription)) _subscription = null;
  }
}
