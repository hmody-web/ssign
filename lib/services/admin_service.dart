import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminApp {
  final String id;
  final String name;
  final String developer;
  final String description;
  final String bundleId;
  final String version;
  final String build;
  final String category;
  final int size;
  final String iconUrl;
  final List<String> screenshots;
  final String ipaUrl;
  final String updatedAt;

  const AdminApp({
    required this.id,
    required this.name,
    required this.developer,
    required this.description,
    required this.bundleId,
    required this.version,
    required this.build,
    required this.category,
    required this.size,
    required this.iconUrl,
    required this.screenshots,
    required this.ipaUrl,
    required this.updatedAt,
  });

  factory AdminApp.fromJson(Map<String, dynamic> j) => AdminApp(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        developer: '${j['developer'] ?? ''}',
        description: '${j['description'] ?? ''}',
        bundleId: '${j['bundle_id'] ?? ''}',
        version: '${j['version'] ?? ''}',
        build: '${j['build'] ?? ''}',
        category: '${j['category'] ?? ''}',
        size: int.tryParse('${j['size'] ?? 0}') ?? 0,
        iconUrl: '${j['icon_url'] ?? ''}',
        screenshots: (j['screenshots'] is List)
            ? (j['screenshots'] as List).map((e) => '$e').toList()
            : const [],
        ipaUrl: '${j['ipa_url'] ?? ''}',
        updatedAt: '${j['updated_at'] ?? ''}',
      );
}

class AdminSource {
  final String id;
  final String name;
  final String url;
  final String description;
  final String imageUrl;
  final bool enabled;
  final int sortOrder;

  const AdminSource({
    required this.id,
    required this.name,
    required this.url,
    required this.description,
    required this.imageUrl,
    required this.enabled,
    required this.sortOrder,
  });

  factory AdminSource.fromJson(Map<String, dynamic> j) => AdminSource(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        url: '${j['url'] ?? ''}',
        description: '${j['description'] ?? ''}',
        imageUrl: '${j['image_url'] ?? j['imageUrl'] ?? ''}',
        enabled: j['enabled'] != false,
        sortOrder: int.tryParse('${j['sort_order'] ?? 0}') ?? 0,
      );
}

class AdminDashboardData {
  final int appCount;
  final int bytes;
  final String updatedAt;
  final List<AdminApp> apps;
  const AdminDashboardData(this.appCount, this.bytes, this.updatedAt, this.apps);
}

class AdminIdentity {
  final String publicKey;
  final bool hardwareBacked;
  final String deviceLabel;
  const AdminIdentity(this.publicKey, this.hardwareBacked, this.deviceLabel);
}

class AdminService {
  AdminService._();
  static final instance = AdminService._();

  static const _base = 'https://scrptaty.com/apps/alsaray/admin_api.php';
  static const _sourcesBase = 'https://scrptaty.com/pannel/source_library.php';
  static const _channel = MethodChannel('sign/admin_secure');
  static const _deviceIdKey = 'alsaray_admin_device_id_v1';

  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 35);
  String? _accessToken;
  final ValueNotifier<String?> deletedAppId = ValueNotifier<String?>(null);

  Future<String?> get deviceId async {
    // Keep the pairing id in Keychain as well as SharedPreferences. iOS normally
    // preserves Keychain items across app deletion/reinstallation, while
    // SharedPreferences is removed with the app container.
    try {
      final secure = await _channel.invokeMethod<String>('loadDeviceId');
      if (secure != null && secure.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_deviceIdKey) != secure) {
          await prefs.setString(_deviceIdKey, secure);
        }
        return secure;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_deviceIdKey);
    if (legacy != null && legacy.isNotEmpty) {
      try { await _channel.invokeMethod<void>('saveDeviceId', {'device_id': legacy}); } catch (_) {}
      return legacy;
    }
    return null;
  }
  bool get hasSession => _accessToken?.isNotEmpty == true;

  /// Lightweight server check used only to decide whether the Admin card should
  /// be visible in Settings. Real access still requires the signed challenge.
  Future<bool> isThisDeviceAdmin() async {
    final id = await _ensureDeviceId();
    if (id == null || id.isEmpty) return false;
    try {
      final r = await _json('device_status', method: 'POST', body: {'device_id': id});
      return r['authorized'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<AdminIdentity> identity() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('getIdentity');
    if (m == null || '${m['publicKey'] ?? ''}'.isEmpty) {
      throw Exception('تعذر إنشاء هوية آمنة للجهاز.');
    }
    return AdminIdentity(
      '${m['publicKey']}',
      m['hardwareBacked'] == true,
      '${m['deviceLabel'] ?? 'iPhone'}',
    );
  }

  Future<void> pair({required String username, required String password}) async {
    final id = await identity();
    if (!id.hardwareBacked && Platform.isIOS) {
      throw Exception('هذا الجهاز لا يدعم Secure Enclave المطلوب لحساب الأدمن.');
    }
    final r = await _json('pair', method: 'POST', body: {
      'username': username.trim(),
      'password': password,
      'public_key': id.publicKey,
      'label': id.deviceLabel,
    });
    final device = '${r['device_id'] ?? ''}';
    if (device.isEmpty) throw Exception('الخادم لم يرجع معرف الجهاز.');
    await _persistDeviceId(device);
  }


  Future<void> _persistDeviceId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, value);
    try {
      await _channel.invokeMethod<void>('saveDeviceId', {'device_id': value});
    } catch (_) {}
  }

  Future<String?> _ensureDeviceId() async {
    final existing = await deviceId;
    if (existing != null && existing.isNotEmpty) return existing;

    // Recovery path after deleting/reinstalling the app: the secure P-256
    // identity survives in Keychain/Secure Enclave, so the server can map that
    // public key back to the already paired device id. No password or re-pairing
    // is required, and actual admin access still requires a private-key signature.
    try {
      final id = await identity();
      final r = await _json('recover_device', method: 'POST', body: {'public_key': id.publicKey});
      final recovered = '${r['device_id'] ?? ''}';
      if (recovered.isNotEmpty) {
        await _persistDeviceId(recovered);
        return recovered;
      }
    } catch (_) {}
    return null;
  }

  Future<void> loginWithDevice() async {
    final id = await _ensureDeviceId();
    if (id == null || id.isEmpty) throw Exception('هذا الجهاز غير مربوط كأدمن.');
    final challenge = await _json('challenge', method: 'POST', body: {'device_id': id});
    final message = '${challenge['message'] ?? ''}';
    final challengeId = '${challenge['challenge_id'] ?? ''}';
    if (message.isEmpty || challengeId.isEmpty) throw Exception('تعذر إنشاء طلب التحقق.');

    final signed = await _channel.invokeMapMethod<String, dynamic>(
      'authenticateAndSign',
      {'message': message},
    );
    final signature = '${signed?['signature'] ?? ''}';
    if (signature.isEmpty) throw Exception('تعذر توقيع طلب الدخول.');

    final verified = await _json('verify', method: 'POST', body: {
      'device_id': id,
      'challenge_id': challengeId,
      'signature': signature,
    });
    final token = '${verified['token'] ?? ''}';
    if (token.isEmpty) throw Exception('تعذر إنشاء جلسة الإدارة.');
    _accessToken = token;
  }

  Future<AdminDashboardData> dashboard() async {
    final r = await _json('dashboard', method: 'GET', auth: true);
    final stats = Map<String, dynamic>.from(r['stats'] is Map ? r['stats'] as Map : const {});
    final apps = (r['apps'] is List ? r['apps'] as List : const [])
        .whereType<Map>()
        .map((e) => AdminApp.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return AdminDashboardData(
      int.tryParse('${stats['apps'] ?? apps.length}') ?? apps.length,
      int.tryParse('${stats['bytes'] ?? 0}') ?? 0,
      '${stats['updated_at'] ?? ''}',
      apps,
    );
  }

  Future<Map<String, dynamic>> inspectIpa(String path, {void Function(double p)? onProgress}) async {
    return _multipart('inspect', files: {'ipa': [path]}, auth: true, onProgress: onProgress);
  }

  Future<AdminApp> saveApp({
    String id = '',
    required String name,
    required String developer,
    required String description,
    required String bundleId,
    required String version,
    required String build,
    required String category,
    String? ipaPath,
    String? iconPath,
    List<String> screenshotPaths = const [],
    List<String> keepScreenshotUrls = const [],
    void Function(double p)? onProgress,
  }) async {
    final fields = {
      'id': id,
      'name': name,
      'developer': developer,
      'description': description,
      'bundle_id': bundleId,
      'version': version,
      'build': build,
      'category': category,
      'keep_screenshots': jsonEncode(keepScreenshotUrls),
    };
    final files = <String, List<String>>{};
    if (ipaPath?.isNotEmpty == true) files['ipa'] = [ipaPath!];
    if (iconPath?.isNotEmpty == true) files['icon'] = [iconPath!];
    if (screenshotPaths.isNotEmpty) files['screenshots[]'] = screenshotPaths;
    final r = await _multipart('save', fields: fields, files: files, auth: true, onProgress: onProgress);
    if (r['app'] is! Map) throw Exception('تعذر قراءة بيانات التطبيق بعد الحفظ.');
    return AdminApp.fromJson(Map<String, dynamic>.from(r['app'] as Map));
  }

  Future<void> deleteApp(String id) async {
    await _json('delete', method: 'POST', body: {'id': id}, auth: true);

    // Remove it from the persisted merged-library cache too. This covers the
    // case where AppsScreen is not mounted when the admin deletes the app.
    try {
      final prefs = await SharedPreferences.getInstance();
      const cacheKey = 'ipa.library.cache.v3.merged';
      final raw = prefs.getString(cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final target = id.startsWith('alsaray:') ? id : 'alsaray:$id';
          decoded.removeWhere((item) => item is Map && '${item['id'] ?? ''}' == target);
          await prefs.setString(cacheKey, jsonEncode(decoded));
        }
      }
    } catch (_) {}

    // Notify the already-mounted Apps screen immediately so the deleted card
    // disappears without waiting for the next scheduled network sync.
    deletedAppId.value = null;
    deletedAppId.value = id;
  }

  Future<List<AdminSource>> sourceCatalog() async {
    final r = await _sourceJson('admin_list', method: 'GET');
    final raw = r['sources'] is List ? r['sources'] as List : const [];
    return raw
        .whereType<Map>()
        .map((e) => AdminSource.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AdminSource> saveSource({
    String id = '',
    required String name,
    required String url,
    String description = '',
    bool enabled = true,
    int sortOrder = 0,
    String? imagePath,
  }) async {
    String imageBase64 = '';
    String imageName = '';
    if (imagePath?.isNotEmpty == true) {
      final file = File(imagePath!);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 6 * 1024 * 1024) {
          throw Exception('صورة المصدر أكبر من 6 MB.');
        }
        imageBase64 = base64Encode(bytes);
        imageName = imagePath.split(Platform.pathSeparator).last;
      }
    }
    final r = await _sourceJson('save', method: 'POST', body: {
      'id': id,
      'name': name,
      'url': url,
      'description': description,
      'enabled': enabled ? '1' : '0',
      'sort_order': '$sortOrder',
      if (imageBase64.isNotEmpty) 'image_base64': imageBase64,
      if (imageName.isNotEmpty) 'image_name': imageName,
    });
    if (r['source'] is! Map) throw Exception('تعذر قراءة بيانات المصدر بعد الحفظ.');
    return AdminSource.fromJson(Map<String, dynamic>.from(r['source'] as Map));
  }

  Future<void> deleteSource(String id) async {
    await _sourceJson('delete', method: 'POST', body: {'id': id});
  }

  Future<Map<String, dynamic>> _sourceJson(
    String action, {
    required String method,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(_sourcesBase).replace(queryParameters: {'action': action});
    final req = method == 'GET' ? await _http.getUrl(uri) : await _http.postUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    _attachAuth(req);
    if (method != 'GET') {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body ?? const {}));
    }
    final resp = await req.close();
    final text = await utf8.decoder.bind(resp).join();
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      throw Exception('رد خادم المصادر غير صالح (${resp.statusCode}).');
    }
    if (resp.statusCode == 401) _accessToken = null;
    if (resp.statusCode < 200 || resp.statusCode >= 300 || data['ok'] != true) {
      throw Exception('${data['error'] ?? data['message'] ?? 'فشل طلب المصادر (${resp.statusCode})'}');
    }
    return data;
  }

  void lock() => _accessToken = null;

  Future<Map<String, dynamic>> _json(
    String action, {
    required String method,
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final uri = Uri.parse(_base).replace(queryParameters: {'action': action});
    final req = method == 'GET' ? await _http.getUrl(uri) : await _http.postUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (auth) _attachAuth(req);
    if (method != 'GET') {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body ?? const {}));
    }
    final resp = await req.close();
    final text = await utf8.decoder.bind(resp).join();
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      throw Exception('رد الخادم غير صالح (${resp.statusCode}).');
    }
    if (resp.statusCode == 401 && auth) _accessToken = null;
    if (resp.statusCode < 200 || resp.statusCode >= 300 || data['ok'] != true) {
      throw Exception('${data['error'] ?? 'فشل الطلب (${resp.statusCode})'}');
    }
    return data;
  }

  void _attachAuth(HttpClientRequest req) {
    final token = _accessToken;
    if (token == null || token.isEmpty) throw Exception('جلسة الأدمن مقفلة. افتح لوحة التحكم من جديد.');
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }

  Future<Map<String, dynamic>> _multipart(
    String action, {
    Map<String, String> fields = const {},
    Map<String, List<String>> files = const {},
    bool auth = false,
    void Function(double p)? onProgress,
  }) async {
    final boundary = '----SSignAdmin${DateTime.now().microsecondsSinceEpoch}';
    final uri = Uri.parse(_base).replace(queryParameters: {'action': action});
    final req = await _http.postUrl(uri);
    if (auth) _attachAuth(req);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');

    final chunks = <List<int>>[];
    final crlf = utf8.encode('\r\n');
    for (final e in fields.entries) {
      chunks.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="${e.key}"\r\n\r\n${e.value}\r\n'));
    }
    for (final entry in files.entries) {
      for (final path in entry.value) {
        final f = File(path);
        if (!await f.exists()) continue;
        final filename = path.split(Platform.pathSeparator).last.replaceAll('"', '');
        final ext = filename.toLowerCase();
        final type = ext.endsWith('.png')
            ? 'image/png'
            : (ext.endsWith('.jpg') || ext.endsWith('.jpeg'))
                ? 'image/jpeg'
                : ext.endsWith('.webp')
                    ? 'image/webp'
                    : 'application/octet-stream';
        chunks.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="${entry.key}"; filename="$filename"\r\nContent-Type: $type\r\n\r\n'));
        chunks.add(await f.readAsBytes());
        chunks.add(crlf);
      }
    }
    chunks.add(utf8.encode('--$boundary--\r\n'));
    final total = chunks.fold<int>(0, (n, c) => n + c.length);
    req.contentLength = total;
    var sent = 0;
    for (final c in chunks) {
      req.add(c);
      sent += c.length;
      onProgress?.call(total <= 0 ? 0 : sent / total);
    }
    final resp = await req.close();
    final text = await utf8.decoder.bind(resp).join();
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      throw Exception('رد الخادم غير صالح (${resp.statusCode}).');
    }
    if (resp.statusCode == 401 && auth) _accessToken = null;
    if (resp.statusCode < 200 || resp.statusCode >= 300 || data['ok'] != true) {
      throw Exception('${data['error'] ?? 'فشل الرفع (${resp.statusCode})'}');
    }
    onProgress?.call(1);
    return data;
  }
}
