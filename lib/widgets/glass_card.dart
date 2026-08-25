import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GlassCard({super.key,required this.child,this.padding=const EdgeInsets.all(18),this.radius=24});
  @override
  Widget build(BuildContext context) {
    final dark=Theme.of(context).brightness==Brightness.dark;
    return ClipRRect(
      borderRadius:BorderRadius.circular(radius),
      child:BackdropFilter(
        filter:ImageFilter.blur(sigmaX:18,sigmaY:18),
        child:Container(
          padding:padding,
          decoration:BoxDecoration(
            color:dark?const Color(0xFF141A25).withValues(alpha:.76):Colors.white.withValues(alpha:.82),
            borderRadius:BorderRadius.circular(radius),
            border:Border.all(color:dark?Colors.white.withValues(alpha:.085):Colors.white.withValues(alpha:.85)),
            boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:dark ? .22 : .04),blurRadius:30,offset:const Offset(0,10))],
          ),
          child:child,
        ),
      ),
    );
  }
}
