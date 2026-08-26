import 'dart:convert';

class RemoteApp {
  final String id;
  final String slug;
  final String name;
  final String nameAr;
  final String subtitle;
  final String subtitleAr;
  final String developerName;
  final String bundleId;
  final String version;
  final String category;
  final int size;
  final String iconUrl;
  final String? downloadUrl;
  final String storageType;
  final List<String> screenshots;
  final DateTime? createdAt;
  final int downloadCount;

  const RemoteApp({
    required this.id,
    required this.slug,
    required this.name,
    required this.nameAr,
    required this.subtitle,
    required this.subtitleAr,
    required this.developerName,
    required this.bundleId,
    required this.version,
    required this.category,
    required this.size,
    required this.iconUrl,
    required this.downloadUrl,
    required this.storageType,
    required this.screenshots,
    required this.createdAt,
    required this.downloadCount,
  });

  factory RemoteApp.fromJson(Map<String, dynamic> j) => RemoteApp(
        id: (j['id'] ?? '').toString(),
        slug: (j['slug'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        nameAr: (j['name_ar'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        subtitleAr: (j['subtitle_ar'] ?? '').toString(),
        developerName: (j['developer_name'] ?? '').toString(),
        bundleId: (j['bundle_id'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        size: _toInt(j['size']),
        iconUrl: (j['icon_url'] ?? '').toString(),
        downloadUrl: j['download_url']?.toString(),
        storageType: (j['storage_type'] ?? '').toString(),
        screenshots: _parseScreenshots(j['screenshots']),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
        downloadCount: _toInt(j['download_count']),
      );


  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'name_ar': nameAr,
        'subtitle': subtitle,
        'subtitle_ar': subtitleAr,
        'developer_name': developerName,
        'bundle_id': bundleId,
        'version': version,
        'category': category,
        'size': size,
        'icon_url': iconUrl,
        'download_url': downloadUrl,
        'storage_type': storageType,
        'screenshots': screenshots,
        'created_at': createdAt?.toIso8601String(),
        'download_count': downloadCount,
      };

  String get contentFingerprint => jsonEncode(toJson());

  String displayName(bool arabic) {
    if (arabic && nameAr.trim().isNotEmpty) return nameAr.trim();
    return name.trim().isEmpty ? slug : name.trim();
  }

  String displaySubtitle(bool arabic) {
    if (arabic && subtitleAr.trim().isNotEmpty) return subtitleAr.trim();
    return subtitle.trim();
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _parseScreenshots(dynamic value) {
    dynamic source = value;
    if (source is String) {
      final text = source.trim();
      if (text.isEmpty) return const [];
      try {
        source = jsonDecode(text);
      } catch (_) {
        return text
            .split(RegExp(r'[,\n]'))
            .map((e) => e.trim())
            .where((e) => Uri.tryParse(e)?.hasScheme == true)
            .toList();
      }
    }

    if (source is! List) return const [];
    final urls = <String>[];
    for (final item in source) {
      String candidate = '';
      if (item is String) {
        candidate = item.trim();
      } else if (item is Map) {
        candidate = (item['url'] ??
                item['image_url'] ??
                item['image'] ??
                item['src'] ??
                item['screenshot_url'] ??
                '')
            .toString()
            .trim();
      }
      final uri = Uri.tryParse(candidate);
      if (candidate.isNotEmpty && uri?.hasScheme == true && !urls.contains(candidate)) {
        urls.add(candidate);
      }
    }
    return urls;
  }
}
