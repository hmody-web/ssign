import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class BoomaBanner {
  final String id;
  final String name;
  final String description;
  final String iconUrl;
  final String coverUrl;
  final String linkUrl;
  final bool enabled;
  final DateTime? createdAt;
  const BoomaBanner({required this.id,required this.name,required this.description,required this.iconUrl,required this.coverUrl,required this.linkUrl,required this.enabled,required this.createdAt});
  factory BoomaBanner.fromJson(Map<String,dynamic> j)=>BoomaBanner(
    id:'${j['id']??''}',name:'${j['name']??''}',description:'${j['description']??''}',
    iconUrl:'${j['icon_url']??''}',coverUrl:'${j['cover_url']??''}',linkUrl:'${j['link_url']??''}',enabled:j['enabled']!=false,createdAt:DateTime.tryParse('${j['created_at']??''}'),
  );
}

class BoomaUpdateInfo {
  final bool active;
  final String releaseId;
  final String title;
  final String appName;
  final String description;
  final String ipaUrl;
  const BoomaUpdateInfo({required this.active,required this.releaseId,required this.title,required this.appName,required this.description,required this.ipaUrl});
  factory BoomaUpdateInfo.fromJson(Map<String,dynamic> j)=>BoomaUpdateInfo(
    active:j['active']==true, releaseId:'${j['release_id']??''}', title:'${j['title']??'يتوفر تحديث جديد'}',
    appName:'${j['app_name']??'Booma'}', description:'${j['description']??'متجر شامل لتطبيقاتك'}', ipaUrl:'${j['ipa_url']??'https://scrptaty.com/apps/booma/Boomaz.ipa'}',
  );
}

class BoomaPublicService {
  BoomaPublicService._();
  static final instance=BoomaPublicService._();
  static const _base='https://scrptaty.com/pannel/booma_public.php';
  final HttpClient _client=HttpClient()..connectionTimeout=const Duration(seconds:20);

  Future<Map<String,dynamic>> _get(String action) async {
    final uri=Uri.parse('$_base?action=$action');
    final req=await _client.getUrl(uri); req.headers.set(HttpHeaders.acceptHeader,'application/json');
    final res=await req.close().timeout(const Duration(seconds:25));
    final body=await utf8.decoder.bind(res).join();
    if(res.statusCode<200||res.statusCode>=300) throw HttpException('HTTP ${res.statusCode}',uri:uri);
    final d=jsonDecode(body); if(d is! Map) throw const FormatException('Invalid response');
    return Map<String,dynamic>.from(d);
  }

  Future<List<BoomaBanner>> banners() async {
    final d=await _get('banners');
    return (d['items'] is List ? d['items'] as List : const []).whereType<Map>().map((e)=>BoomaBanner.fromJson(Map<String,dynamic>.from(e))).where((e)=>e.enabled).toList();
  }

  Future<BoomaUpdateInfo> updateInfo() async => BoomaUpdateInfo.fromJson(await _get('update'));

  Future<File> downloadUpdate(String url,{required void Function(double) onProgress}) async {
    final uri=Uri.parse(url); final req=await _client.getUrl(uri); final res=await req.close().timeout(const Duration(seconds:45));
    if(res.statusCode<200||res.statusCode>=300) throw HttpException('HTTP ${res.statusCode}',uri:uri);
    final total=res.contentLength; final dir=await getTemporaryDirectory(); final file=File('${dir.path}/Booma_Update_${DateTime.now().millisecondsSinceEpoch}.ipa');
    final sink=file.openWrite(); var received=0;
    await for(final chunk in res){sink.add(chunk);received+=chunk.length;if(total>0)onProgress((received/total).clamp(0.0,1.0));}
    await sink.close(); onProgress(1); return file;
  }
}
