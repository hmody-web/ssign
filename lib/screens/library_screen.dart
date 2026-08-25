import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/app_store.dart';
import '../services/file_import_service.dart';
import '../services/signing_service.dart';
import '../widgets/glass_card.dart';

class LibraryScreen extends StatefulWidget { const LibraryScreen({super.key}); @override State<LibraryScreen> createState()=>_LibraryScreenState(); }
class _LibraryScreenState extends State<LibraryScreen>{
  final importer=FileImportService(); final store=AppStore.instance; final signer=SigningService();
  Future<void> _import() async { final v=await importer.pickFiles(); if(v.isNotEmpty) await store.addFiles(v); }
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:store,builder:(context,_)=>CustomScrollView(slivers:[
    SliverPadding(padding:const EdgeInsets.fromLTRB(18,12,18,14),sliver:SliverToBoxAdapter(child:Row(children:[
      const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Sign',style:TextStyle(fontSize:34,fontWeight:FontWeight.w800,letterSpacing:-1.2)),Text('Your signing workspace',style:TextStyle(color:Colors.black54))])),
      IconButton.filledTonal(onPressed:_import,icon:const Icon(CupertinoIcons.add)),
    ]))),
    SliverPadding(padding:const EdgeInsets.symmetric(horizontal:18),sliver:SliverToBoxAdapter(child:GlassCard(child:Row(children:[
      const Icon(CupertinoIcons.tray_arrow_down,size:34),const SizedBox(width:14),
      const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Import files',style:TextStyle(fontWeight:FontWeight.w700,fontSize:17)),SizedBox(height:3),Text('IPA, P12, mobileprovision or ZIP',style:TextStyle(color:Colors.black54))])),
      FilledButton(onPressed:_import,child:const Text('Import')),
    ])))),
    const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.fromLTRB(20,26,20,10),child:Text('Library',style:TextStyle(fontSize:21,fontWeight:FontWeight.w800)))),
    if(store.files.isEmpty) const SliverFillRemaining(hasScrollBody:false,child:Center(child:Text('No files yet\nImport an IPA or signing asset to begin',textAlign:TextAlign.center,style:TextStyle(color:Colors.black45))))
    else SliverPadding(padding:const EdgeInsets.fromLTRB(18,0,18,30),sliver:SliverList.builder(itemCount:store.files.length,itemBuilder:(_,i){final f=store.files.reversed.toList()[i]; return Padding(padding:const EdgeInsets.only(bottom:10),child:GlassCard(padding:const EdgeInsets.all(14),child:Row(children:[
      Container(width:48,height:48,decoration:BoxDecoration(color:Colors.black.withValues(alpha:.05),borderRadius:BorderRadius.circular(14)),child:Icon(_icon(f.kind))),const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(f.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w700)),Text('${f.kind} • ${_size(f.size)}',style:const TextStyle(color:Colors.black45,fontSize:12))])),
      PopupMenuButton<String>(onSelected:(v) async { if(v=='share') await signer.share(f.path); if(v=='delete'){try{await File(f.path).delete();}catch(_){} await store.removeFile(f.id);} },itemBuilder:(_)=>[const PopupMenuItem(value:'share',child:Text('Share / Export')),const PopupMenuItem(value:'delete',child:Text('Delete'))]),
    ])));})),
  ]));
  IconData _icon(String k)=>switch(k){'IPA'=>CupertinoIcons.app_badge,'Signed IPA'=>CupertinoIcons.checkmark_shield_fill,'Certificate'=>CupertinoIcons.lock_shield,'Provision'=>CupertinoIcons.doc_text,_=>CupertinoIcons.doc};
  String _size(int b)=>b>1024*1024?'${(b/1024/1024).toStringAsFixed(1)} MB':'${(b/1024).toStringAsFixed(0)} KB';
}
