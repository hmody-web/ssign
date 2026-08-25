import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GlassCard({super.key,required this.child,this.padding=const EdgeInsets.all(18)});
  @override Widget build(BuildContext context)=>ClipRRect(borderRadius:BorderRadius.circular(22),child:BackdropFilter(filter:ImageFilter.blur(sigmaX:15,sigmaY:15),child:Container(padding:padding,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.78),borderRadius:BorderRadius.circular(22),border:Border.all(color:Colors.white.withValues(alpha:.8)),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.035),blurRadius:25,offset:const Offset(0,8))]),child:child)));
}
