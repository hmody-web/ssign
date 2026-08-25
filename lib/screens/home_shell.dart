import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'library_screen.dart';
import 'certificates_screen.dart';
import 'sign_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget { const HomeShell({super.key}); @override State<HomeShell> createState()=>_HomeShellState(); }
class _HomeShellState extends State<HomeShell>{
  int index=0;
  final pages=const [LibraryScreen(),CertificatesScreen(),SignScreen(),SettingsScreen()];
  @override Widget build(BuildContext context)=>Scaffold(
    body:SafeArea(child:AnimatedSwitcher(duration:const Duration(milliseconds:260),transitionBuilder:(c,a)=>FadeTransition(opacity:a,child:SlideTransition(position:Tween(begin:const Offset(.025,0),end:Offset.zero).animate(a),child:c)),child:KeyedSubtree(key:ValueKey(index),child:pages[index]))),
    bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:const [
      NavigationDestination(icon:Icon(CupertinoIcons.folder),selectedIcon:Icon(CupertinoIcons.folder_fill),label:'Files'),
      NavigationDestination(icon:Icon(CupertinoIcons.checkmark_shield),selectedIcon:Icon(CupertinoIcons.checkmark_shield_fill),label:'Certificates'),
      NavigationDestination(icon:Icon(CupertinoIcons.signature),label:'Sign'),
      NavigationDestination(icon:Icon(CupertinoIcons.gear),selectedIcon:Icon(CupertinoIcons.gear_solid),label:'Settings'),
    ]),
  );
}
