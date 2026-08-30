import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

class NativeIOSButton extends StatefulWidget {
  final String title;
  final String? systemImage;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool destructive;
  final double height;
  final double? width;

  const NativeIOSButton({
    super.key,
    required this.title,
    this.systemImage,
    this.onPressed,
    this.prominent = false,
    this.destructive = false,
    this.height = 44,
    this.width,
  });

  @override
  State<NativeIOSButton> createState() => _NativeIOSButtonState();
}

class _NativeIOSButtonState extends State<NativeIOSButton> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          onPressed: widget.onPressed,
          child: Text(widget.title),
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: UiKitView(
        viewType: 'booma/native_system_button',
        creationParams: {
          'title': widget.title,
          'systemImage': widget.systemImage,
          'enabled': widget.onPressed != null,
          'prominent': widget.prominent,
          'destructive': widget.destructive,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          final channel = MethodChannel('booma/native_control/$id');
          _channel = channel;
          channel.setMethodCallHandler((call) async {
            if (call.method == 'tap') widget.onPressed?.call();
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

class NativeIOSTextField extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final bool autofocus;
  final int maxLines;
  final double height;
  final String? leadingSystemImage;

  const NativeIOSTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.height = 46,
    this.leadingSystemImage,
  });

  @override
  State<NativeIOSTextField> createState() => _NativeIOSTextFieldState();
}

class _NativeIOSTextFieldState extends State<NativeIOSTextField> {
  MethodChannel? _channel;
  bool _nativeUpdate = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_pushText);
  }

  @override
  void didUpdateWidget(covariant NativeIOSTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_pushText);
      widget.controller.addListener(_pushText);
    }
  }

  void _pushText() {
    if (_nativeUpdate) return;
    _channel?.invokeMethod('setText', widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return CupertinoTextField(
        controller: widget.controller,
        placeholder: widget.placeholder,
        obscureText: widget.obscureText,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        prefix: widget.leadingSystemImage == null
            ? null
            : const Padding(
                padding: EdgeInsetsDirectional.only(start: 10),
                child: Icon(CupertinoIcons.search, size: 18),
              ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: UiKitView(
        viewType: 'booma/native_system_text_field',
        creationParams: {
          'text': widget.controller.text,
          'placeholder': widget.placeholder,
          'obscure': widget.obscureText,
          'autofocus': widget.autofocus,
          'multiline': widget.maxLines > 1,
          'leadingSystemImage': widget.leadingSystemImage,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          final channel = MethodChannel('booma/native_control/$id');
          _channel = channel;
          channel.setMethodCallHandler((call) async {
            if (call.method == 'changed') {
              final text = (call.arguments as String?) ?? '';
              _nativeUpdate = true;
              widget.controller.value = widget.controller.value.copyWith(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
                composing: TextRange.empty,
              );
              _nativeUpdate = false;
              widget.onChanged?.call(text);
            } else if (call.method == 'submitted') {
              widget.onSubmitted?.call((call.arguments as String?) ?? widget.controller.text);
            }
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_pushText);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

class NativeIOSCategories extends StatefulWidget {
  final List<String> values;
  final List<String> labels;
  final String? selected;
  final bool isArabic;
  final ValueChanged<String?> onChanged;
  final double height;

  const NativeIOSCategories({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.isArabic,
    required this.onChanged,
    this.height = 48,
  });

  @override
  State<NativeIOSCategories> createState() => _NativeIOSCategoriesState();
}

class _NativeIOSCategoriesState extends State<NativeIOSCategories> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: UiKitView(
        key: ValueKey('${widget.selected}|${widget.values.join(',')}'),
        viewType: 'booma/native_system_categories',
        creationParams: {
          'values': widget.values,
          'labels': widget.labels,
          'selected': widget.selected,
          'isArabic': widget.isArabic,
        },
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
        },
        onPlatformViewCreated: (id) {
          final channel = MethodChannel('booma/native_control/$id');
          _channel = channel;
          channel.setMethodCallHandler((call) async {
            if (call.method == 'selected') {
              final value = call.arguments as String?;
              widget.onChanged(value?.isEmpty == true ? null : value);
            }
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

class NativeIOSAppCard extends StatefulWidget {
  final Map<String, dynamic> app;
  final Map<String, dynamic> downloadState;
  final bool isArabic;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback? onSign;
  final double height;

  const NativeIOSAppCard({
    super.key,
    required this.app,
    required this.downloadState,
    required this.isArabic,
    required this.onTap,
    required this.onDownload,
    required this.onPause,
    this.onSign,
    this.height = 90,
  });

  @override
  State<NativeIOSAppCard> createState() => _NativeIOSAppCardState();
}

class _NativeIOSAppCardState extends State<NativeIOSAppCard> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant NativeIOSAppCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadState != widget.downloadState) {
      _channel?.invokeMethod<void>('updateState', widget.downloadState).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: UiKitView(
        key: ValueKey('native-app-card-${widget.app['id']}-${widget.isArabic}'),
        viewType: 'booma/native_app_card',
        creationParams: {
          'app': widget.app,
          'state': widget.downloadState,
          'isArabic': widget.isArabic,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          final channel = MethodChannel('booma/native_control/$id');
          _channel = channel;
          channel.setMethodCallHandler((call) async {
            switch (call.method) {
              case 'tap': widget.onTap(); break;
              case 'download': widget.onDownload(); break;
              case 'pause': widget.onPause(); break;
              case 'sign': widget.onSign?.call(); break;
            }
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}


class NativeIOSFeaturedBanner extends StatefulWidget {
  final Map<String, dynamic> app;
  final bool isArabic;
  final VoidCallback onTap;
  final double height;

  const NativeIOSFeaturedBanner({
    super.key,
    required this.app,
    required this.isArabic,
    required this.onTap,
    this.height = 215,
  });

  @override
  State<NativeIOSFeaturedBanner> createState() => _NativeIOSFeaturedBannerState();
}

class _NativeIOSFeaturedBannerState extends State<NativeIOSFeaturedBanner> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: UiKitView(
        key: ValueKey('featured-${widget.app['id']}-${widget.isArabic}'),
        viewType: 'booma/native_featured_banner',
        creationParams: {
          'app': widget.app,
          'isArabic': widget.isArabic,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          final channel = MethodChannel('booma/native_control/$id');
          _channel = channel;
          channel.setMethodCallHandler((call) async {
            if (call.method == 'tap') widget.onTap();
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}
