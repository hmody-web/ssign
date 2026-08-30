import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'native_ios_controls.dart';

String _textOf(m.Widget? w) {
  if (w is m.Text) return w.data ?? '';
  return '';
}

String? _symbolOf(m.Widget? w) {
  if (w is! m.Icon) return null;
  final d = w.icon;
  if (d == CupertinoIcons.add || d == CupertinoIcons.add_circled) return 'plus';
  if (d == CupertinoIcons.xmark || d == CupertinoIcons.xmark_circle_fill) return 'xmark';
  if (d == CupertinoIcons.trash) return 'trash';
  if (d == CupertinoIcons.refresh) return 'arrow.clockwise';
  if (d == CupertinoIcons.chevron_back) return 'chevron.backward';
  if (d == CupertinoIcons.chevron_forward) return 'chevron.forward';
  if (d == CupertinoIcons.ellipsis) return 'ellipsis';
  if (d == CupertinoIcons.folder || d == CupertinoIcons.folder_fill) return 'folder';
  if (d == CupertinoIcons.folder_badge_plus) return 'folder.badge.plus';
  if (d == CupertinoIcons.photo) return 'photo';
  if (d == CupertinoIcons.cloud_upload_fill) return 'icloud.and.arrow.up.fill';
  if (d == CupertinoIcons.arrow_down_circle_fill) return 'arrow.down.circle.fill';
  if (d == CupertinoIcons.signature) return 'signature';
  if (d == CupertinoIcons.lock_shield) return 'lock.shield';
  return 'circle';
}

class NativeCompatFilledButton extends m.StatelessWidget {
  final VoidCallback? onPressed;
  final m.Widget child;
  final m.Widget? icon;
  final m.ButtonStyle? style;
  final bool tonal;

  const NativeCompatFilledButton({super.key, required this.onPressed, required this.child, this.style})
      : icon = null,
        tonal = false;

  const NativeCompatFilledButton.icon({super.key, required this.onPressed, required m.Widget icon, required m.Widget label, this.style})
      : icon = icon,
        child = label,
        tonal = false;

  const NativeCompatFilledButton.tonalIcon({super.key, required this.onPressed, required m.Widget icon, required m.Widget label, this.style})
      : icon = icon,
        child = label,
        tonal = true;

  static m.ButtonStyle styleFrom({
    m.Color? backgroundColor,
    m.Color? foregroundColor,
    m.Size? minimumSize,
    m.EdgeInsetsGeometry? padding,
    m.OutlinedBorder? shape,
    m.VisualDensity? visualDensity,
  }) => m.FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        minimumSize: minimumSize,
        padding: padding,
        shape: shape,
        visualDensity: visualDensity,
      );

  @override
  m.Widget build(m.BuildContext context) {
    if (!Platform.isIOS) {
      if (icon != null) {
        return tonal
            ? m.FilledButton.tonalIcon(onPressed: onPressed, icon: icon!, label: child, style: style)
            : m.FilledButton.icon(onPressed: onPressed, icon: icon!, label: child, style: style);
      }
      return m.FilledButton(onPressed: onPressed, style: style, child: child);
    }
    return NativeIOSButton(
      title: _textOf(child),
      systemImage: _symbolOf(icon),
      onPressed: onPressed,
      prominent: !tonal,
      height: 44,
    );
  }
}

class NativeCompatTextButton extends m.StatelessWidget {
  final VoidCallback? onPressed;
  final m.Widget child;
  final m.ButtonStyle? style;
  const NativeCompatTextButton({super.key, required this.onPressed, required this.child, this.style});

  static m.ButtonStyle styleFrom({
    m.Size? minimumSize,
    m.EdgeInsetsGeometry? padding,
    m.VisualDensity? visualDensity,
  }) => m.TextButton.styleFrom(minimumSize: minimumSize, padding: padding, visualDensity: visualDensity);

  @override
  m.Widget build(m.BuildContext context) {
    if (!Platform.isIOS) return m.TextButton(onPressed: onPressed, style: style, child: child);
    return NativeIOSButton(title: _textOf(child), onPressed: onPressed, height: 38);
  }
}

class NativeCompatIconButton extends m.StatelessWidget {
  final VoidCallback? onPressed;
  final m.Widget icon;
  final String? tooltip;
  final double? iconSize;
  final m.ButtonStyle? style;
  final bool tonal;

  const NativeCompatIconButton({super.key, required this.onPressed, required this.icon, this.tooltip, this.iconSize, this.style}) : tonal = false;
  const NativeCompatIconButton.filledTonal({super.key, required this.onPressed, required this.icon, this.tooltip, this.iconSize, this.style}) : tonal = true;

  @override
  m.Widget build(m.BuildContext context) {
    if (!Platform.isIOS) {
      return tonal
          ? m.IconButton.filledTonal(onPressed: onPressed, icon: icon, tooltip: tooltip, iconSize: iconSize, style: style)
          : m.IconButton(onPressed: onPressed, icon: icon, tooltip: tooltip, iconSize: iconSize, style: style);
    }
    return NativeIOSButton(title: '', systemImage: _symbolOf(icon), onPressed: onPressed, width: 44, height: 44, prominent: false);
  }
}
