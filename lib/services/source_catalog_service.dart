import 'dart:convert';
import 'dart:io';

class SourceCatalogItem {
  final String id;
  final String name;
  final String url;
  final String description;
  final String imageUrl;
  final bool enabled;
  final int sortOrder;

  const SourceCatalogItem({
    required this.id,
    required this.name,
    required this.url,
    required this.description,
    required this.imageUrl,
    required this.enabled,
    required this.sortOrder,
  });

  factory SourceCatalogItem.fromJson(Map<String, dynamic> json) => SourceCatalogItem(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        url: '${json['url'] ?? ''}',
        description: '${json['description'] ?? ''}',
        imageUrl: '${json['image_url'] ?? json['imageUrl'] ?? ''}',
        enabled: json['enabled'] != false,
        sortOrder: int.tryParse('${json['sort_order'] ?? 0}') ?? 0,
      );
}

class SourceCatalogService {
  SourceCatalogService._();
  static final instance = SourceCatalogService._();

  static const endpoint = 'https://scrptaty.com/pannel/source_library.php';
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  List<SourceCatalogItem>? _cache;
  DateTime? _cacheAt;
  static const _cacheDuration = Duration(minutes: 2);

  Future<List<SourceCatalogItem>> fetch({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _cache != null &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < _cacheDuration) {
      return List<SourceCatalogItem>.unmodifiable(_cache!);
    }

    final uri = Uri.parse(endpoint).replace(queryParameters: const {'action': 'list'});
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('تعذر تحميل مكتبة المصادر (${response.statusCode})', uri: uri);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const FormatException('رد مكتبة المصادر غير صالح');
    }
    if (decoded is! Map || decoded['ok'] != true || decoded['sources'] is! List) {
      throw const FormatException('صيغة مكتبة المصادر غير صالحة');
    }

    final items = (decoded['sources'] as List)
        .whereType<Map>()
        .map((raw) => SourceCatalogItem.fromJson(Map<String, dynamic>.from(raw)))
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty && item.url.isNotEmpty && item.enabled)
        .toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    _cache = items;
    _cacheAt = now;
    return List<SourceCatalogItem>.unmodifiable(items);
  }

  void invalidate() {
    _cache = null;
    _cacheAt = null;
  }
}
