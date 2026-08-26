import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/localized.dart';
import 'library_screen.dart';
import 'apps_screen.dart';
import 'sign_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  late final PageController _pageController;
  ImportedFile? _preparedSignFile;
  final _topKeys = List<GlobalKey>.generate(4, (_) => GlobalKey());

  void _openSignForFile(ImportedFile file) {
    setState(() => _preparedSignFile = file);
    _goToPage(2);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page < 0 || page > 3) return;
    if (page == index) {
      final ctx = _topKeys[page].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic, alignment: 0);
      }
      return;
    }
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppStore.instance,
        builder: (context, _) => Scaffold(
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
              onPageChanged: (page) {
                if (index != page) setState(() => index = page);
              },
              children: [
                AppsScreen(onSignRequested: _openSignForFile, topKey: _topKeys[0]),
                LibraryScreen(onSignRequested: _openSignForFile, topKey: _topKeys[1]),
                SignScreen(preparedFile: _preparedSignFile, topKey: _topKeys[2]),
                SettingsScreen(topKey: _topKeys[3]),
              ],
            ),
          ),
          bottomNavigationBar: _BottomNavigationLayer(
            controller: _pageController,
            selectedIndex: index,
            onSelected: _goToPage,
          ),
        ),
      );
}

class _BottomNavigationLayer extends StatelessWidget {
  final PageController controller;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _BottomNavigationLayer({
    required this.controller,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: 82 + bottomInset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    bg,
                    bg.withValues(alpha: .96),
                    bg.withValues(alpha: .66),
                    bg.withValues(alpha: 0),
                  ],
                  stops: const [0, .32, .68, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _SlidingBottomBar(
                controller: controller,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlidingBottomBar extends StatefulWidget {
  final PageController controller;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _SlidingBottomBar({
    required this.controller,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<_SlidingBottomBar> createState() => _SlidingBottomBarState();
}

class _SlidingBottomBarState extends State<_SlidingBottomBar> {
  double? _dragLogicalPosition;
  double? _heldTargetPosition;
  bool _isTouchingBar = false;

  static const _items = <_BottomItem>[
    _BottomItem(CupertinoIcons.square_grid_2x2, CupertinoIcons.square_grid_2x2_fill, 'بــومـة', 'Booma'),
    _BottomItem(CupertinoIcons.folder, CupertinoIcons.folder_fill, 'الملفات', 'Files'),
    _BottomItem(CupertinoIcons.signature, CupertinoIcons.signature, 'التوقيع', 'Sign'),
    _BottomItem(CupertinoIcons.gear, CupertinoIcons.gear_solid, 'الإعدادات', 'Settings'),
  ];

  double _pagePosition() {
    if (_dragLogicalPosition != null) return _dragLogicalPosition!;
    if (_heldTargetPosition != null) {
      if (widget.controller.hasClients) {
        final page = widget.controller.page ?? widget.selectedIndex.toDouble();
        if ((page - _heldTargetPosition!).abs() < .02) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _heldTargetPosition != null) {
              setState(() => _heldTargetPosition = null);
            }
          });
        } else {
          return _heldTargetPosition!;
        }
      } else {
        return _heldTargetPosition!;
      }
    }
    if (widget.controller.hasClients) return widget.controller.page ?? widget.selectedIndex.toDouble();
    return widget.selectedIndex.toDouble();
  }

  void _updateDragAt(Offset localPosition, double width, bool rtl) {
    final slot = width / _items.length;
    var visual = (localPosition.dx / slot) - .5;
    visual = visual.clamp(0.0, (_items.length - 1).toDouble()).toDouble();
    final logical = rtl ? (_items.length - 1) - visual : visual;
    setState(() => _dragLogicalPosition = logical.clamp(0.0, (_items.length - 1).toDouble()).toDouble());
  }

  void _endDrag() {
    final value = (_dragLogicalPosition ?? widget.selectedIndex.toDouble())
        .round()
        .clamp(0, _items.length - 1)
        .toInt();
    setState(() {
      _dragLogicalPosition = null;
      _heldTargetPosition = value.toDouble();
    });
    widget.onSelected(value);
  }

  void _setTouching(bool value) {
    if (_isTouchingBar == value) return;
    setState(() => _isTouchingBar = value);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedScale(
      scale: _isTouchingBar ? 1.025 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _setTouching(true),
        onPointerUp: (_) => _setTouching(false),
        onPointerCancel: (_) => _setTouching(false),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width - 28;
            final slot = width / _items.length;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _updateDragAt(d.localPosition, width, rtl),
              onHorizontalDragUpdate: (d) => _updateDragAt(d.localPosition, width, rtl),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: () => setState(() => _dragLogicalPosition = null),
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: .76),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: .07)
                        : Colors.black.withValues(alpha: .05),
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final logicalPosition = _pagePosition();
                    final visualPosition = rtl ? (_items.length - 1) - logicalPosition : logicalPosition;
                    final indicatorLeft = visualPosition * slot + 5;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: Duration.zero,
                          curve: Curves.linear,
                          left: indicatorLeft,
                          top: 6,
                          width: slot - 10,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        Row(
                          children: List.generate(_items.length, (i) {
                            final item = _items[i];
                            final distance = (logicalPosition - i).abs().clamp(0.0, 1.0).toDouble();
                            final selectedness = 1.0 - distance;
                            final color = Color.lerp(
                              Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
                              primary,
                              selectedness,
                            )!;
                            return Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => widget.onSelected(i),
                                child: SizedBox.expand(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(selectedness > .5 ? item.selectedIcon : item.icon, size: 21, color: color),
                                      const SizedBox(height: 3),
                                      Text(
                                        tr(item.ar, item.en),
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          height: 1,
                                          fontWeight: selectedness > .5 ? FontWeight.w800 : FontWeight.w600,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
          ),
        ),
      ),
    );
  }
}

class _BottomItem {
  final IconData icon;
  final IconData selectedIcon;
  final String ar;
  final String en;
  const _BottomItem(this.icon, this.selectedIcon, this.ar, this.en);
}
