import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sign_models.dart';
import '../services/app_store.dart';
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
  static const _nativeTabChannel = MethodChannel('booma/native_system_tab_bar_channel');

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

  void _syncNativeSelection(int page) {
    if (!Platform.isIOS) return;
    _nativeTabChannel.invokeMethod<void>('setSelectedIndex', page).catchError((_) {});
  }

  void _goToPage(int page, {bool animate = true}) {
    if (page < 0 || page > 3) return;
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
          body: SafeArea(
            bottom: false,
            child: Builder(
              builder: (context) {
                final pages = <Widget>[
                  AppsScreen(onSignRequested: _openSignForFile, topKey: _topKeys[0]),
                  LibraryScreen(onSignRequested: _openSignForFile, topKey: _topKeys[1]),
                  SignScreen(
                    preparedFile: _preparedSignFile,
                    topKey: _topKeys[2],
                    onSelectionCleared: () {
                      if (_preparedSignFile != null) setState(() => _preparedSignFile = null);
                    },
                  ),
                  SettingsScreen(topKey: _topKeys[3]),
                ];

                // Keep only the selected iOS page mounted. Retaining several hidden
                // UIKit platform views inside an IndexedStack can destabilize composition
                // when opening the Files tab. App data itself stays in AppStore/services.
                if (Platform.isIOS) {
                  return KeyedSubtree(
                    key: ValueKey('ios-page-$index'),
                    child: pages[index],
                  );
                }

                return PageView(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
                  onPageChanged: (page) {
                    if (index != page) setState(() => index = page);
                    _syncNativeSelection(page);
                  },
                  children: pages,
                );
              },
            ),
          ),
          bottomNavigationBar: _SystemBottomBar(
            selectedIndex: index,
            onSelected: _goToPage,
          ),
        ),
      );
}

class _SystemBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _SystemBottomBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    if (Platform.isIOS) {
      // Real UIKit UITabBar. No custom blur/glass is drawn by Flutter.
      // On supported iOS versions the operating system supplies Liquid Glass.
      return SizedBox(
        height: 50 + bottomInset,
        child: UiKitView(
          key: ValueKey('native-tab-${AppStore.instance.languageCode}'),
          viewType: 'booma/native_system_tab_bar',
          creationParams: <String, dynamic>{
            'selectedIndex': selectedIndex,
            'isArabic': AppStore.instance.isArabic,
          },
          creationParamsCodec: const StandardMessageCodec(),
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
