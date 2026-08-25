import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/file_import_service.dart';
import '../services/signing_service.dart';
import '../widgets/glass_card.dart';

class SignScreen extends StatefulWidget { const SignScreen({super.key}); @override State<SignScreen> createState()=>_SignScreenState(); }
class _SignScreenState extends State<SignScreen>{
  final store=AppStore.instance, importer=FileImportService(), signing=SigningService();
  String? ipaPath; String? identityId; bool busy=false; bool removeDevices=false; double progress=0;
  final bundle=TextEditingController(),name=TextEditingController(),version=TextEditingController(),buildCtrl=TextEditingController();

  Future<void> _chooseIpa() async { final v=await importer.pickFiles(extensions:['ipa']); if(v.isEmpty)return; final f=v.first; await store.addFiles([f]); setState(()=>ipaPath=f.path); try{final info=await signing.inspectIpa(f.path); if(!mounted)return; setState((){bundle.text=(info['bundleId']??'').toString();name.text=(info['displayName']??'').toString();version.text=(info['version']??'').toString();buildCtrl.text=(info['build']??'').toString();});}catch(_){} }

  Future<void> _sign() async {
    SigningIdentity? id;
    for (final item in store.identities) { if (item.id == identityId) { id = item; break; } }
    if(ipaPath==null||id==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Choose an IPA and a signing identity first.')));return;}
    setState((){busy=true;progress=.18;});
    try{
      final storedPassword=await signing.loadPassword(id.id);
      final out=await signing.sign(ipaPath:ipaPath!,p12Path:id.p12Path,p12Password:storedPassword,provisionPath:id.provisionPath,options:SignOptions(bundleId:bundle.text.trim(),displayName:name.text.trim(),version:version.text.trim(),build:buildCtrl.text.trim(),removeSupportedDevices:removeDevices));
      setState(()=>progress=.95); final file=File(out); final model=ImportedFile(id:DateTime.now().microsecondsSinceEpoch.toString(),name:p.basename(out),path:out,kind:'Signed IPA',size:await file.length(),importedAt:DateTime.now()); await store.addSignedOutput(model); if(!mounted)return; setState(()=>progress=1); await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Signed successfully ✓'),content:Text('Created ${p.basename(out)}'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Done')),TextButton(onPressed:() async {Navigator.pop(ctx);await signing.share(out);},child:const Text('Export')),FilledButton(onPressed:() async {Navigator.pop(ctx);final ok=await signing.install(out);if(mounted&&!ok)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('iOS did not open the installer.')));},child:const Text('Install'))]));
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Signing failed: $e')));} finally{if(mounted)setState((){busy=false;progress=0;});}
  }

  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:store,builder:(context,_)=>ListView(padding:const EdgeInsets.all(18),children:[
    const Text('Sign App',style:TextStyle(fontSize:32,fontWeight:FontWeight.w800,letterSpacing:-1)),const SizedBox(height:6),const Text('IPA → certificate → signed IPA',style:TextStyle(color:Colors.black54)),const SizedBox(height:22),
    GlassCard(child:Column(children:[
      _picker(CupertinoIcons.app_badge,'Application',ipaPath==null?'Select an IPA':p.basename(ipaPath!),_chooseIpa),const Divider(height:28),
      DropdownButtonFormField<String>(value:identityId,decoration:const InputDecoration(labelText:'Signing identity'),items:store.identities.map((e)=>DropdownMenuItem(value:e.id,child:Text(e.name))).toList(),onChanged:(v)=>setState(()=>identityId=v),hint:Text(store.identities.isEmpty?'Add a certificate first':'Choose certificate')),
    ])),const SizedBox(height:16),
    GlassCard(child:Column(children:[TextField(controller:bundle,decoration:const InputDecoration(labelText:'Bundle Identifier',hintText:'Leave unchanged if blank')),const SizedBox(height:10),TextField(controller:name,decoration:const InputDecoration(labelText:'Display Name',hintText:'Leave unchanged if blank')),const SizedBox(height:10),Row(children:[Expanded(child:TextField(controller:version,decoration:const InputDecoration(labelText:'Version'))),const SizedBox(width:10),Expanded(child:TextField(controller:buildCtrl,decoration:const InputDecoration(labelText:'Build')))]),const SizedBox(height:8),SwitchListTile(contentPadding:EdgeInsets.zero,value:removeDevices,onChanged:(v)=>setState(()=>removeDevices=v),title:const Text('Remove UIDeviceFamily restrictions'),subtitle:const Text('Optional compatibility tweak'))])),
    const SizedBox(height:18),if(busy)...[LinearProgressIndicator(value:progress==0?null:progress),const SizedBox(height:12)],FilledButton.icon(style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(58),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))),onPressed:busy?null:_sign,icon:busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(CupertinoIcons.signature),label:Text(busy?'Signing…':'Start Signing',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700))),const SizedBox(height:10),const Text('Sign uses your own P12 and provisioning profile. Signed files are saved locally in the app sandbox.',textAlign:TextAlign.center,style:TextStyle(fontSize:11,color:Colors.black45)),
  ]));

  Widget _picker(IconData icon,String title,String subtitle,VoidCallback action)=>Row(children:[Icon(icon),const SizedBox(width:13),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),Text(subtitle,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.black45,fontSize:12))])),FilledButton.tonal(onPressed:action,child:const Text('Choose'))]);
}

