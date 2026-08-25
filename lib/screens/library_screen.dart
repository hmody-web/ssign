import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/file_import_service.dart';
import '../services/signing_service.dart';
import '../services/localized.dart';
import '../widgets/glass_card.dart';

class LibraryScreen extends StatefulWidget { const LibraryScreen({super.key}); @override State<LibraryScreen> createState()=>_LibraryScreenState(); }
class _LibraryScreenState extends State<LibraryScreen>{
  final importer=FileImportService(); final store=AppStore.instance; final signer=SigningService();

  Future<void> _import() async {
    final picked=await importer.pickFiles();
    if(picked.isEmpty)return;
    final enriched=<ImportedFile>[];
    for(final f in picked){
      if(f.kind=='IPA'){
        try{
          final info=await signer.inspectIpa(f.path);
          final appName=(info['displayName']??'').toString().trim();
          enriched.add(f.copyWith(name:appName.isEmpty?f.name:appName,bundleId:(info['bundleId']??'').toString(),version:(info['version']??'').toString(),iconPath:(info['iconPath']??'').toString()));
        }catch(_){enriched.add(f);}
      }else{enriched.add(f);}
    }
    await store.addFiles(enriched);
  }

  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:store,builder:(context,_)=>CustomScrollView(slivers:[
    SliverPadding(padding:const EdgeInsets.fromLTRB(18,18,18,14),sliver:SliverToBoxAdapter(child:Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('بــــومـة | Booma',style:TextStyle(fontSize:34,fontWeight:FontWeight.w800,letterSpacing:-1.2)),Text(tr('مساحة التوقيع الخاصة بك','Your signing workspace'),style:TextStyle(color:Theme.of(context).colorScheme.onSurface.withValues(alpha:.55)))])),
      IconButton.filledTonal(onPressed:_import,icon:const Icon(CupertinoIcons.add)),
    ]))),
    SliverPadding(padding:const EdgeInsets.symmetric(horizontal:18),sliver:SliverToBoxAdapter(child:GlassCard(child:Row(children:[
      Icon(CupertinoIcons.tray_arrow_down,size:34,color:Theme.of(context).colorScheme.primary),const SizedBox(width:14),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(tr('استيراد الملفات','Import files'),style:const TextStyle(fontWeight:FontWeight.w700,fontSize:17)),const SizedBox(height:3),Text(tr('IPA أو P12 أو mobileprovision أو ZIP','IPA, P12, mobileprovision or ZIP'),style:TextStyle(color:Theme.of(context).colorScheme.onSurface.withValues(alpha:.55)))])),
      FilledButton(onPressed:_import,child:Text(tr('استيراد','Import'))),
    ])))),
    SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(20,26,20,10),child:Text(tr('الملفات','Library'),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w800)))),
    if(store.files.isEmpty) SliverFillRemaining(hasScrollBody:false,child:Center(child:Text(tr('لا توجد ملفات بعد\nاستورد تطبيق IPA أو ملف توقيع للبدء','No files yet\nImport an IPA or signing asset to begin'),textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.onSurface.withValues(alpha:.45)))))
    else SliverPadding(padding:const EdgeInsets.fromLTRB(18,0,18,120),sliver:SliverList.builder(itemCount:store.files.length,itemBuilder:(_,i){final f=store.files.reversed.toList()[i]; return Padding(padding:const EdgeInsets.only(bottom:10),child:GlassCard(padding:const EdgeInsets.all(14),child:Row(children:[
      _appIcon(context,f),const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(f.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:15.5)),const SizedBox(height:3),Text(_subtitle(f),style:TextStyle(color:Theme.of(context).colorScheme.onSurface.withValues(alpha:.48),fontSize:12))])),
      PopupMenuButton<String>(onSelected:(v) async { if(v=='share') await signer.share(f.path); if(v=='delete'){try{await File(f.path).delete();}catch(_){} await store.removeFile(f.id);} },itemBuilder:(_)=>[PopupMenuItem(value:'share',child:Text(tr('مشاركة / تصدير','Share / Export'))),PopupMenuItem(value:'delete',child:Text(tr('حذف','Delete')))]),
    ])));})),
  ]));

  Widget _appIcon(BuildContext context,ImportedFile f){
    final path=f.iconPath;
    if(path!=null&&path.isNotEmpty&&File(path).existsSync()){
      return ClipRRect(borderRadius:BorderRadius.circular(14),child:Image.file(File(path),width:52,height:52,fit:BoxFit.cover,errorBuilder:(_,__,___)=>_fallback(context,f)));
    }
    return _fallback(context,f);
  }
  Widget _fallback(BuildContext context,ImportedFile f)=>Container(width:52,height:52,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primary.withValues(alpha:.12),borderRadius:BorderRadius.circular(14)),child:Icon(_icon(f.kind),color:Theme.of(context).colorScheme.primary));
  String _subtitle(ImportedFile f){final kind=switch(f.kind){'Signed IPA'=>tr('IPA موقع','Signed IPA'),'Certificate'=>tr('شهادة','Certificate'),'Provision'=>tr('ملف توفير','Provision'),'Archive'=>tr('أرشيف','Archive'),_=>f.kind}; final bits=<String>[kind]; if((f.version??'').isNotEmpty)bits.add('${tr('الإصدار','v')} ${f.version}'); bits.add(_size(f.size)); return bits.join(' • ');}
  IconData _icon(String k)=>switch(k){'IPA'=>CupertinoIcons.app_badge,'Signed IPA'=>CupertinoIcons.checkmark_shield_fill,'Certificate'=>CupertinoIcons.lock_shield,'Provision'=>CupertinoIcons.doc_text,_=>CupertinoIcons.doc};
  String _size(int b)=>b>1024*1024?'${(b/1024/1024).toStringAsFixed(1)} MB':'${(b/1024).toStringAsFixed(0)} KB';
}
