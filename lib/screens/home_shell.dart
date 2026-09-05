import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/booma_public_service.dart';
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
  bool _checkingUpdate = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkMandatoryUpdate());
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
          if (Platform.isIOS) _nativeTabChannel.invokeMethod<void>('setCompact', compact).catchError((_) {});
          if (mounted) setState(() {});
        }
      }
    }
    return false;
  }

  Future<void> _checkMandatoryUpdate() async {
    if (_checkingUpdate || !mounted) return;
    _checkingUpdate = true;
    try {
      final info = await BoomaPublicService.instance.updateInfo();
      if (!info.active || info.releaseId.isEmpty || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('booma.update.installedRelease') == info.releaseId) return;
      if (!mounted) return;
      await _showMandatoryUpdate(info);
    } catch (_) {
      // Update checks must never block normal startup if the server is offline.
    } finally {
      _checkingUpdate = false;
    }
  }

  Future<void> _showMandatoryUpdate(BoomaUpdateInfo info) async {
    double progress = 0;
    String stage = tr('جاهز للتحديث', 'Ready to update');
    bool busy = false;
    bool completed = false;
    String? error;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, _, __) => PopScope(
        canPop: false,
        child: StatefulBuilder(builder: (context, setModalState) {
          Future<void> begin() async {
            if (busy || completed) return;
            setModalState(() { busy = true; error = null; stage = tr('جاري تنزيل التحديث…', 'Downloading update…'); progress = 0; });
            try {
              final file = await BoomaPublicService.instance.downloadUpdate(info.ipaUrl, onProgress: (p) {
                if (dialogContext.mounted) setModalState(() { progress = p * .86; stage = tr('جاري تنزيل التحديث…', 'Downloading update…'); });
              });
              if (!dialogContext.mounted) return;
              setModalState(() { progress = .90; stage = tr('جاري بدء التثبيت…', 'Starting installation…'); });
              final launched = await SigningService().install(file.path);
              if (!launched) throw Exception(tr('تعذر بدء تثبيت التحديث', 'Could not start update installation'));
              var started = false;
              for (var i = 0; i < 24; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 500));
                started = await SigningService().installDownloadStarted();
                if (dialogContext.mounted) setModalState(() { progress = (.91 + (i / 24) * .07).clamp(.91, .98); stage = tr('جاري التثبيت…', 'Installing…'); });
                if (started) break;
              }
              if (!started) throw Exception(tr('لم يبدأ مثبت النظام. اضغط تحديث للمحاولة مجددًا.', 'The system installer did not start. Try again.'));
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('booma.update.installedRelease', info.releaseId);
              if (dialogContext.mounted) setModalState(() { progress = 1; busy = false; completed = true; stage = tr('اكتمل إرسال التحديث إلى مثبت النظام', 'Update handed to the system installer'); });
            } catch (e) {
              if (dialogContext.mounted) setModalState(() { busy = false; progress = 0; error = e.toString().replaceFirst('Exception: ', ''); stage = tr('تعذر إكمال التحديث', 'Update failed'); });
            }
          }

          Future<void> openApp() async {
            final uri = Uri.parse('booma://open');
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }

          final cardColor = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0D0D0F) : Colors.white;
          return SafeArea(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(28), border: Border.all(color: Theme.of(context).dividerColor)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(info.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .08))),
                      child: Row(children: [
                        ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset('assets/images/icon.png', width: 66, height: 66, fit: BoxFit.cover)),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(info.appName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(info.description, style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 12)),
                        ])),
                        const SizedBox(width: 10),
                        if (!busy && !completed)
                          CupertinoButton.filled(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9), onPressed: begin, child: Text(tr('تحديث', 'Update')))
                        else if (busy)
                          SizedBox(width: 48, height: 48, child: Stack(alignment: Alignment.center, children: [CircularProgressIndicator(value: progress, strokeWidth: 3), Text('${(progress * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))]))
                        else
                          CupertinoButton(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), color: Theme.of(context).colorScheme.primary, onPressed: openApp, child: Text(tr('فتح', 'Open'))),
                      ]),
                    ),
                    const SizedBox(height: 13),
                    Text(stage, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
                    if (error != null) ...[const SizedBox(height: 9), Text(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w700))],
                  ]),
                ),
              ),
            ),
          );
        }),
      ),
      transitionBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: ScaleTransition(scale: Tween<double>(begin: .96, end: 1).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: child)),
    );
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
      // Real UIKit UITabBar. No custom blur/glass is drawn by Flutter.
      // On supported iOS versions the operating system supplies Liquid Glass.
      return AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        height: 50 + bottomInset,
        child: AnimatedScale(
          scale: compact ? .90 : 1,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: UiKitView(
          key: ValueKey('native-tab-${AppStore.instance.languageCode}'),
          viewType: 'booma/native_system_tab_bar',
          creationParams: <String, dynamic>{
            'selectedIndex': selectedIndex,
            'isArabic': AppStore.instance.isArabic,
          },
          creationParamsCodec: const StandardMessageCodec(),
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
