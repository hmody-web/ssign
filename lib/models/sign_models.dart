import 'dart:convert';

class ImportedFile {
  final String id;
  final String name;
  final String path;
  final String kind;
  final int size;
  final DateTime importedAt;
  final String? bundleId;
  final String? version;
  final String? iconPath;

  const ImportedFile({
    required this.id,
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    required this.importedAt,
    this.bundleId,
    this.version,
    this.iconPath,
  });

  ImportedFile copyWith({String? name, String? kind, String? bundleId, String? version, String? iconPath}) => ImportedFile(
    id: id,
    name: name ?? this.name,
    path: path,
    kind: kind ?? this.kind,
    size: size,
    importedAt: importedAt,
    bundleId: bundleId ?? this.bundleId,
    version: version ?? this.version,
    iconPath: iconPath ?? this.iconPath,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'kind': kind,
    'size': size,
    'importedAt': importedAt.toIso8601String(),
    'bundleId': bundleId,
    'version': version,
    'iconPath': iconPath,
  };

  factory ImportedFile.fromJson(Map<String, dynamic> j) => ImportedFile(
    id: j['id'] as String,
    name: j['name'] as String,
    path: j['path'] as String,
    kind: j['kind'] as String,
    size: (j['size'] as num).toInt(),
    importedAt: DateTime.parse(j['importedAt'] as String),
    bundleId: j['bundleId'] as String?,
    version: j['version'] as String?,
    iconPath: j['iconPath'] as String?,
  );
}

class SigningIdentity {
  final String id;
  final String name;
  final String p12Path;
  final String provisionPath;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const SigningIdentity({
    required this.id,
    required this.name,
    required this.p12Path,
    required this.provisionPath,
    required this.createdAt,
    this.expiresAt,
  });

  bool get isValid => expiresAt == null || expiresAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'p12Path': p12Path,
        'provisionPath': provisionPath,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory SigningIdentity.fromJson(Map<String, dynamic> j) => SigningIdentity(
        id: j['id'] as String,
        name: j['name'] as String,
        p12Path: j['p12Path'] as String,
        provisionPath: j['provisionPath'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        expiresAt: j['expiresAt'] == null ? null : DateTime.tryParse(j['expiresAt'].toString()),
      );
}

class SignOptions {
  final String bundleId;
  final String displayName;
  final String version;
  final String build;
  final bool removeSupportedDevices;
  final String iconPath;
  const SignOptions({this.bundleId='',this.displayName='',this.version='',this.build='',this.removeSupportedDevices=false,this.iconPath=''});
}

String encodeList(List<Map<String,dynamic>> v)=>jsonEncode(v);
