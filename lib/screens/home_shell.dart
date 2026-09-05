import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/signing_service.dart';
import '../widgets/app_notice.dart';
import '../services/localized.dart';
import 'apps_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'sign_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  static const _nativeTabChannel = MethodChannel('booma/native_system_tab_bar_channel');

  int index = 0;
  late final PageController _pageController;
  ImportedFile? _preparedSignFile;
  bool _signingBusy = false;
  DateTime? _lastBlockedNotice;
  bool _tabCompact = false;
  final _topKeys = List<GlobalKey>.generate(4, (_) => GlobalKey());

  void _openSignForFile(ImportedFile file) {
    setState(() => _preparedSignFile = file);
    _goToPage(2);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: index);
    if (Platform.isIOS) {
      _nativeTabChannel.setMethodCallHandler(_handleNativeTabCall);
    }
  }

  Future<dynamic> _handleNativeTabCall(MethodCall call) async {
    if (call.method == 'onTabSelected') {
      final page = call.arguments as int?;
      if (page != null) _goToPage(page, animate: false);
    }
    return null;
  }

  @override
  void dispose() {
    if (Platform.isIOS) {
      _nativeTabChannel.setMethodCallHandler(null);
    }
    _pageController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta.abs() > 1.5) {
        final compact = delta > 0;
        if (compact != _tabCompact) {
          _tabCompact = compact;
          if (Platform.isIOS) {
            // Keep scrolling buttery-smooth: UIKit animates the tab bar itself,
            // so there is no reason to rebuild the whole Flutter page here.
            _nativeTabChannel.invokeMethod<void>('setCompact', compact).catchError((_) {});
          } else if (mounted) {
            setState(() {});
          }
        }
      }
    }
    return false;
  }

  void _syncNativeSelection(int page) {
    if (!Platform.isIOS) return;
    _nativeTabChannel.invokeMethod<void>('setSelectedIndex', page).catchError((_) {});
  }

  void _goToPage(int page, {bool animate = true}) {
    if (page < 0 || page > 3) return;
    if (_signingBusy && page != 2) {
      _syncNativeSelection(2);
      final now = DateTime.now();
      if (_lastBlockedNotice == null || now.difference(_lastBlockedNotice!) > const Duration(milliseconds: 900)) {
        _lastBlockedNotice = now;
        showAppNotice(
          context,
          tr('يرجى عدم المغادرة لحين اكتمال عملية التوقيع', 'Please stay on the Sign tab until signing is complete'),
          type: AppNoticeType.warning,
          duration: const Duration(seconds: 3),
        );
      }
      return;
    }
    if (page == index) {
      final ctx = _topKeys[page].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          alignment: 0,
        );
      }
      _syncNativeSelection(page);
      return;
    }
    // A system tab selection should commit immediately. Animating a PageView
    // through intermediate pages made UIKit briefly receive an old selection,
    // which looked like the selected Liquid Glass item jumped backwards.
    if (index != page) setState(() => index = page);
    _syncNativeSelection(page);
    if (Platform.isIOS) return;
    if (animate) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(page);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppStore.instance,
        builder: (context, _) => Scaffold(
          extendBody: true,
          body: PageStorage(
            bucket: _pageStorageBucket,
            child: SafeArea(
              bottom: false,
              child: Builder(
              builder: (context) {
                final pages = <Widget>[
                  AppsScreen(onSignRequested: _openSignForFile, topKey: _topKeys[0]),
                  LibraryScreen(onSignRequested: _openSignForFile, topKey: _topKeys[1]),
                  SignScreen(
                    preparedFile: _preparedSignFile,
                    topKey: _topKeys[2],
                    onBusyChanged: (value) {
                      if (!mounted || _signingBusy == value) return;
                      setState(() => _signingBusy = value);
                      if (value) _syncNativeSelection(2);
                    },
                    onSelectionCleared: () {
                      if (_preparedSignFile != null) setState(() => _preparedSignFile = null);
                    },
                  ),
                  SettingsScreen(topKey: _topKeys[3]),
                ];

                // Keep only one UIKit-heavy page mounted at a time for stability.
                // Each section owns a PageStorageKey, so its scroll offset is restored
                // exactly when the user comes back without retaining hidden platform views.
                if (Platform.isIOS) {
                  return NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: KeyedSubtree(
                      key: ValueKey('ios-page-$index'),
                      child: pages[index],
                    ),
                  );
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: PageView(
                  controller: _pageController,
                  physics: _signingBusy ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(parent: PageScrollPhysics()),
                  onPageChanged: (page) {
                    if (index != page) setState(() => index = page);
                    _syncNativeSelection(page);
                  },
                  children: pages,
                ),
                );
              },
            ),
          ),
          ),
          bottomNavigationBar: _SystemBottomBar(
            selectedIndex: index,
            onSelected: _goToPage,
            compact: _tabCompact,
          ),
        ),
      );
}

class _SystemBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool compact;

  const _SystemBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    if (Platform.isIOS) {
      // Keep Liquid Glass itself untouched. The fade follows the active app
      // theme: light in light mode and dark in dark mode, with no blur.
      final base = Theme.of(context).scaffoldBackgroundColor;
      return SizedBox(
        height: 50 + bottomInset,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      base.withValues(alpha: 0),
                      base.withValues(alpha: .48),
                      base.withValues(alpha: .92),
                      base,
                    ],
                    stops: const [0, .44, .78, 1],
                  ),
                ),
              ),
              UiKitView(
                key: ValueKey('native-tab-${AppStore.instance.languageCode}'),
                viewType: 'booma/native_system_tab_bar',
                creationParams: <String, dynamic>{
                  'selectedIndex': selectedIndex,
                  'isArabic': AppStore.instance.isArabic,
                  'compact': compact,
                },
                creationParamsCodec: const StandardMessageCodec(),
              ),
            ],
          ),
        ),
      );
    }

    // Non-iOS fallback only. The app's iOS build uses the native UITabBar above.
    return CupertinoTabBar(
      currentIndex: selectedIndex,
      onTap: onSelected,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.square_grid_2x2),
          activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
          label: 'Booma',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.folder),
          activeIcon: Icon(CupertinoIcons.folder_fill),
          label: 'Files',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.signature),
          label: 'Sign',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.gear),
          activeIcon: Icon(CupertinoIcons.gear_solid),
          label: 'Settings',
        ),
      ],
    );
  }
}
