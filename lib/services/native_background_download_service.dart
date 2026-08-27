import 'dart:async';
import 'package:flutter/services.dart';

class NativeDownloadEvent {
  final String downloadId;
  final String status;
  final int downloadedBytes;
  final int totalBytes;
  final double progress;
  final bool paused;
  final String localPath;
  final String? error;

  const NativeDownloadEvent({
    required this.downloadId,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    required this.paused,
    required this.localPath,
    this.error,
  });

  factory NativeDownloadEvent.fromMap(Map<dynamic, dynamic> map) => NativeDownloadEvent(
        downloadId: (map['downloadId'] ?? '').toString(),
        status: (map['status'] ?? '').toString(),
        downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        progress: ((map['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        paused: map['paused'] == true,
        localPath: (map['localPath'] ?? '').toString(),
        error: map['error']?.toString(),
      );
}

class NativeBackgroundDownloadService {
  NativeBackgroundDownloadService._();
  static final instance = NativeBackgroundDownloadService._();

  static const _methods = MethodChannel('booma.background_download/methods');
  static const _events = EventChannel('booma.background_download/events');

  Stream<NativeDownloadEvent>? _stream;

  Stream<NativeDownloadEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => NativeDownloadEvent.fromMap(event as Map))
      .asBroadcastStream();

  Future<void> start({
    required String downloadId,
    required String appName,
    required String appIcon,
    required String downloadURL,
    required String fileName,
    required int totalBytes,
  }) async {
    await _methods.invokeMethod('start', {
      'downloadId': downloadId,
      'appName': appName,
      'appIcon': appIcon,
      'downloadURL': downloadURL,
      'fileName': fileName,
      'totalBytes': totalBytes,
    });
  }

  Future<void> pause(String id) => _methods.invokeMethod('pause', {'downloadId': id});
  Future<void> resume(String id) => _methods.invokeMethod('resume', {'downloadId': id});
  Future<void> cancel(String id) => _methods.invokeMethod('cancel', {'downloadId': id});

  Future<List<NativeDownloadEvent>> list() async {
    final raw = await _methods.invokeListMethod<dynamic>('list') ?? const [];
    return raw.whereType<Map>().map(NativeDownloadEvent.fromMap).toList();
  }
}
