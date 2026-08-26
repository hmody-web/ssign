import 'package:flutter/services.dart';
import '../models/sign_models.dart';

class SigningService {
  static const _channel=MethodChannel('sign/native');

  Future<Map<String,dynamic>> inspectIpa(String ipaPath) async {
    final raw=await _channel.invokeMapMethod<String,dynamic>('inspectIpa',{'ipaPath':ipaPath});
    return raw??<String,dynamic>{};
  }

  Future<Map<String,dynamic>> inspectIdentity({required String p12Path, required String password, required String provisionPath}) async {
    final raw=await _channel.invokeMapMethod<String,dynamic>('inspectIdentity',{'p12Path':p12Path,'password':password,'provisionPath':provisionPath});
    return raw??<String,dynamic>{};
  }

  Future<String> sign({required String ipaPath,required String p12Path,required String p12Password,required String provisionPath,required SignOptions options}) async {
    final result=await _channel.invokeMethod<String>('signIpa',{
      'ipaPath':ipaPath,'p12Path':p12Path,'p12Password':p12Password,'provisionPath':provisionPath,
      'bundleId':options.bundleId,'displayName':options.displayName,'version':options.version,'build':options.build,
      'removeSupportedDevices':options.removeSupportedDevices,'iconPath':options.iconPath,
    });
    if(result==null||result.isEmpty) throw StateError('Signing engine returned no output path');
    return result;
  }

  Future<void> savePassword(String id,String password) async => _channel.invokeMethod<void>('savePassword',{'id':id,'password':password});
  Future<String> loadPassword(String id) async => (await _channel.invokeMethod<String>('loadPassword',{'id':id})) ?? '';
  Future<void> deletePassword(String id) async => _channel.invokeMethod<void>('deletePassword',{'id':id});

  Future<void> share(String path) async => _channel.invokeMethod<void>('shareFile',{'path':path});
  Future<bool> install(String path) async {
    try {
      return (await _channel.invokeMethod<bool>('installIpa', {'path': path})) ?? false;
    } on PlatformException {
      return false;
    }
  }
}
