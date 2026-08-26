import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum AppNoticeType { success, error, info, warning }

OverlayEntry? _activeNotice;

void showAppNotice(
  BuildContext context,
  String message, {
  AppNoticeType type = AppNoticeType.info,
}) {
  _activeNotice?.remove();
  _activeNotice = null;

  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppNoticeOverlay(
      message: message,
      type: type,
      onDismiss: () {
        if (_activeNotice == entry) {
          _activeNotice = null;
        }
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _activeNotice = entry;
  overlay.insert(entry);
}

class _AppNoticeOverlay extends StatefulWidget {
  final String message;
  final AppNoticeType type;
  final VoidCallback onDismiss;

  const _AppNoticeOverlay({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_AppNoticeOverlay> createState() => _AppNoticeOverlayState();
}

class _AppNoticeOverlayState extends State<_AppNoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 190),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(.13, -.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1780), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.type) {
      case AppNoticeType.success:
        return CupertinoIcons.check_mark_circled_solid;
      case AppNoticeType.error:
        return CupertinoIcons.xmark_circle_fill;
      case AppNoticeType.warning:
        return CupertinoIcons.exclamationmark_triangle_fill;
      case AppNoticeType.info:
        return CupertinoIcons.info_circle_fill;
    }
  }

  Color _accent(BuildContext context) {
    switch (widget.type) {
      case AppNoticeType.success:
        return const Color(0xFF34C759);
      case AppNoticeType.error:
        return const Color(0xFFFF453A);
      case AppNoticeType.warning:
        return const Color(0xFFFF9F0A);
      case AppNoticeType.info:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final top = MediaQuery.paddingOf(context).top + 10;

    return Positioned(
      top: top,
      right: 12,
      left: 56,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topRight,
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 390),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: (dark ? const Color(0xFF171717) : Colors.white)
                            .withValues(alpha: dark ? .88 : .91),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: .22),
                          width: .8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: dark ? .26 : .10),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: TextDirection.rtl,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .13),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(_icon, size: 19, color: accent),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.message,
                              textAlign: TextAlign.right,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
