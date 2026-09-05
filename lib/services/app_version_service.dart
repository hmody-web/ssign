import 'package:flutter/services.dart';

class InstalledAppInfo {
  final String version;
  final String build;
  const InstalledAppInfo({required this.version, required this.build});
}

class AppVersionService {
  AppVersionService._();
  static final instance = AppVersionService._();
  static const _channel = MethodChannel('booma/app_info');

  Future<InstalledAppInfo> current() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('current');
    return InstalledAppInfo(
      version: '${data?['version'] ?? ''}'.trim(),
      build: '${data?['build'] ?? ''}'.trim(),
    );
  }
}
