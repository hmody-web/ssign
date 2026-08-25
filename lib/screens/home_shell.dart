import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/localized.dart';
import 'library_screen.dart';
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

  void _openSignForFile(ImportedFile file) {
    setState(() => _preparedSignFile = file);
    _goToPage(1);
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
    if (page == index) return;
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
              physics: const BouncingScrollPhysics(
                parent: PageScrollPhysics(),
              ),
              onPageChanged: (page) {
                if (index != page) {
                  setState(() => index = page);
                }
              },
              children: [
                LibraryScreen(onSignRequested: _openSignForFile),
                SignScreen(preparedFile: _preparedSignFile),
                const SettingsScreen(),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: .68),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: .10)
                          : Colors.white.withValues(alpha: .82),
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: NavigationBar(
                    height: 72,
                    backgroundColor: Colors.transparent,
                    indicatorColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: .18),
                    selectedIndex: index,
                    onDestinationSelected: _goToPage,
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(CupertinoIcons.folder),
                        selectedIcon: const Icon(CupertinoIcons.folder_fill),
                        label: tr('الملفات', 'Files'),
                      ),
                      NavigationDestination(
                        icon: const Icon(CupertinoIcons.signature),
                        label: tr('التوقيع', 'Sign'),
                      ),
                      NavigationDestination(
                        icon: const Icon(CupertinoIcons.gear),
                        selectedIcon: const Icon(CupertinoIcons.gear_solid),
                        label: tr('الإعدادات', 'Settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
