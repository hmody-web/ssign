import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_app.dart';
import '../models/sign_models.dart';
import '../services/app_download_manager.dart';
import '../services/app_store.dart';
import '../services/ipa_library_service.dart';
import '../services/localized.dart';
import '../widgets/glass_card.dart';
import 'app_detail_screen.dart';

class AppsScreen extends StatefulWidget {
  final ValueChanged<ImportedFile>? onSignRequested;
  const AppsScreen({super.key, this.onSignRequested});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 60;
  static const _cacheKey = 'ipa.library.cache.v2';
  static const _cacheSyncKey = 'ipa.library.cache.synced.v2';
  static const _syncEvery = Duration(minutes: 5);

  final _service = IpaLibraryService();
  final _downloads = AppDownloadManager.instance;
  final _store = AppStore.instance;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<RemoteApp> _apps = [];
  List<RemoteApp>? _searchResults;

  Timer? _syncTimer;
  Timer? _searchDebounce;
  bool _loading = false;
  bool _loadingMore = false;
  bool _syncing = false;
  bool _hasMore = true;
  bool _searchOpen = false;
  String? _selectedCategory;
  String? _error;
  int _searchGeneration = 0;
  DateTime? _lastSync;

  @override
  bool get wantKeepAlive => true;

  List<RemoteApp> get _visibleApps {
    final source = _searchController.text.trim().isEmpty ? _apps : (_searchResults ?? const <RemoteApp>[]);
    final category = _selectedCategory?.trim().toLowerCase();
    if (category == null || category.isEmpty) return source;
    return source.where((app) => app.category.trim().toLowerCase() == category).toList();
  }

  List<String> get _categories {
    final values = _apps
        .map((app) => app.category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _restoreThenLoad();
    _syncTimer = Timer.periodic(_syncEvery, (_) => _syncIncrementally());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _restoreThenLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    final synced = prefs.getInt(_cacheSyncKey);
    if (synced != null) _lastSync = DateTime.fromMillisecondsSinceEpoch(synced);

    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((e) => RemoteApp.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() {
            _apps
              ..clear()
              ..addAll(list);
            _hasMore = list.length >= _pageSize;
          });
        }
      } catch (_) {}
    }

    if (_apps.isEmpty) {
      await _loadInitial();
    } else if (_lastSync == null || DateTime.now().difference(_lastSync!) >= _syncEvery) {
      unawaited(_syncIncrementally());
    }
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_apps.map((e) => e.toJson()).toList()));
    final now = DateTime.now();
    _lastSync = now;
    await prefs.setInt(_cacheSyncKey, now.millisecondsSinceEpoch);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
    });
    try {
      final items = await _service.fetchApps(offset: 0, limit: _pageSize);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _apps
          ..clear()
          ..addAll(items);
        _hasMore = items.length == _pageSize;
      });
      await _saveCache();
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && generation == _searchGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _syncIncrementally() async {
    if (_syncing || _searchController.text.trim().isNotEmpty) return;
    _syncing = true;
    try {
      final limit = math.max(_pageSize, _apps.length);
      final fresh = await _service.fetchApps(offset: 0, limit: limit);
      if (!mounted) return;

      final oldById = {for (final app in _apps) app.id: app};
      final freshById = {for (final app in fresh) app.id: app};
      bool changed = false;

      for (var i = 0; i < _apps.length; i++) {
        final updated = freshById[_apps[i].id];
        if (updated != null && updated.contentFingerprint != _apps[i].contentFingerprint) {
          _apps[i] = updated;
          changed = true;
        }
      }

      final newItems = fresh.where((item) => !oldById.containsKey(item.id)).toList();
      if (newItems.isNotEmpty) {
        _apps.insertAll(0, newItems);
        changed = true;
      }

      if (changed) setState(() {});
      _hasMore = fresh.length >= limit;
      await _saveCache();
    } catch (_) {
      // Keep cached content untouched when a background check fails.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final term = _searchController.text.trim();
    final current = term.isEmpty ? _apps : (_searchResults ?? const <RemoteApp>[]);
    setState(() => _loadingMore = true);
    try {
      final items = await _service.fetchApps(offset: current.length, limit: _pageSize, search: term);
      if (!mounted) return;
      setState(() {
        if (term.isEmpty) {
          final ids = _apps.map((e) => e.id).toSet();
          _apps.addAll(items.where((e) => ids.add(e.id)));
        } else {
          final results = _searchResults ?? <RemoteApp>[];
          final ids = results.map((e) => e.id).toSet();
          results.addAll(items.where((e) => ids.add(e.id)));
          _searchResults = results;
        }
        _hasMore = items.length == _pageSize;
      });
      if (term.isEmpty) await _saveCache();
    } catch (_) {
      // Preserve current content.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 380), _runSearch);
    setState(() {});
  }

  Future<void> _runSearch() async {
    final term = _searchController.text.trim();
    if (term.isEmpty) {
      setState(() {
        _searchResults = null;
        _hasMore = _apps.length >= _pageSize;
      });
      return;
    }

    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
    });
    try {
      final items = await _service.fetchApps(offset: 0, limit: _pageSize, search: term);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = items;
        _hasMore = items.length == _pageSize;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && generation == _searchGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _startDownload(RemoteApp app) async {
    try {
      final file = await _downloads.start(app);
      if (!mounted || file == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تم تنزيل التطبيق وإضافته إلى الملفات', 'App downloaded and added to Files'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr('فشل تنزيل التطبيق', 'Download failed')}: ${_friendlyError(e)}')),
      );
    }
  }

  void _openDetails(RemoteApp app) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => AppDetailScreen(
          app: app,
          isArabic: _store.isArabic,
          libraryApps: List<RemoteApp>.unmodifiable(_apps),
          onSign: (file) => widget.onSignRequested?.call(file),
        ),
      ),
    );
  }

  String _friendlyError(Object e) {
    final s = e.toString().replaceFirst('HttpException: ', '').trim();
    if (s.contains('SocketException')) return tr('تحقق من اتصال الإنترنت', 'Check your internet connection');
    return s.isNotEmpty ? s : tr('تعذر إكمال العملية', 'Unable to complete the operation');
  }

  List<RemoteApp> get _featured {
    final list = _apps.where((a) => a.screenshots.isNotEmpty).toList()
      ..sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isArabic = _store.isArabic;
    final apps = _visibleApps;
    final featured = _featured;

    return RefreshIndicator(
      onRefresh: _syncIncrementally,
      child: CustomScrollView(
        key: const PageStorageKey('apps-scroll-view'),
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Booma | بــومـة', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                            const SizedBox(height: 5),
                            Text(
                              tr('مكتبة تطبيقات IPA جاهزة للتنزيل والتوقيع', 'IPA library ready to download and sign'),
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _CircleAction(
                        icon: _searchOpen ? CupertinoIcons.xmark : CupertinoIcons.search,
                        onTap: () {
                          setState(() => _searchOpen = !_searchOpen);
                          if (!_searchOpen) {
                            _searchController.clear();
                            _runSearch();
                            FocusScope.of(context).unfocus();
                          }
                        },
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: !_searchOpen
                        ? const SizedBox(height: 14)
                        : Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 4),
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              onChanged: _onSearchChanged,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: tr('ابحث باسم التطبيق أو المطور...', 'Search apps or developers...'),
                                prefixIcon: const Icon(CupertinoIcons.search),
                                suffixIcon: _searchController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _searchController.clear();
                                          _runSearch();
                                          setState(() {});
                                        },
                                        icon: const Icon(CupertinoIcons.xmark_circle_fill),
                                      ),
                              ),
                            ),
                          ),
                  ),
                  if (featured.isNotEmpty && _searchController.text.trim().isEmpty) ...[
                    const SizedBox(height: 4),
                    _FeaturedCarousel(apps: featured, isArabic: isArabic, onTap: _openDetails),
                    const SizedBox(height: 16),
                    if (_categories.isNotEmpty)
                      _CategoryShelf(
                        categories: _categories,
                        selected: _selectedCategory,
                        onChanged: (value) => setState(() => _selectedCategory = value),
                      ),
                    const SizedBox(height: 22),
                    _AppsSectionDivider(title: tr('التطبيقات', 'Apps')),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          if (_loading && apps.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CupertinoActivityIndicator(radius: 15)))
          else if (_error != null && apps.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle, size: 44),
                      const SizedBox(height: 12),
                      Text(tr('تعذر تحميل مكتبة التطبيقات', 'Could not load the app library'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 14),
                      FilledButton.tonal(onPressed: _loadInitial, child: Text(tr('إعادة المحاولة', 'Retry'))),
                    ],
                  ),
                ),
              ),
            )
          else if (apps.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(tr('لا توجد نتائج مطابقة', 'No matching apps found'))))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
              sliver: SliverList.builder(
                itemCount: apps.length + (_loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == apps.length) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Center(child: CupertinoActivityIndicator()));
                  }
                  final app = apps[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimatedBuilder(
                      animation: _downloads,
                      builder: (context, _) {
                        final state = _downloads.stateFor(app);
                        return _AppCard(
                          app: app,
                          isArabic: isArabic,
                          state: state,
                          onDownload: () => _startDownload(app),
                          onTogglePause: () => _downloads.togglePause(app),
                          onSign: (file) => widget.onSignRequested?.call(file),
                          onTap: () => _openDetails(app),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 21)),
        ),
      );
}


class _CategoryShelf extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _CategoryShelf({required this.categories, required this.selected, required this.onChanged});

  IconData _iconFor(String category) {
    final c = category.toLowerCase();
    if (c.contains('game') || c.contains('لعب')) return CupertinoIcons.game_controller_solid;
    if (c.contains('social') || c.contains('تواصل')) return CupertinoIcons.person_2_fill;
    if (c.contains('photo') || c.contains('صور')) return CupertinoIcons.photo_fill;
    if (c.contains('video') || c.contains('فيديو')) return CupertinoIcons.play_rectangle_fill;
    if (c.contains('music') || c.contains('موسي')) return CupertinoIcons.music_note_2;
    if (c.contains('tool') || c.contains('أدوات') || c.contains('ادوات')) return CupertinoIcons.wrench_fill;
    if (c.contains('business') || c.contains('عمل')) return CupertinoIcons.briefcase_fill;
    if (c.contains('education') || c.contains('تعليم')) return CupertinoIcons.book_fill;
    return CupertinoIcons.square_grid_2x2_fill;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final allSelected = selected == null || selected!.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            blurRadius: 24,
            offset: const Offset(0, 10),
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .18 : .06),
          ),
        ],
      ),
      child: SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: categories.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, index) {
            final isAll = index == 0;
            final category = isAll ? tr('الكل', 'All') : categories[index - 1];
            final active = isAll ? allSelected : selected == category;
            return GestureDetector(
              onTap: () => onChanged(isAll ? null : category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: 82,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? primary.withValues(alpha: .16) : Theme.of(context).colorScheme.onSurface.withValues(alpha: .045),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: active ? primary.withValues(alpha: .38) : Theme.of(context).dividerColor),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isAll ? CupertinoIcons.square_grid_2x2_fill : _iconFor(category), size: 23, color: active ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: .58)),
                    const SizedBox(height: 7),
                    Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: .72))),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppsSectionDivider extends StatelessWidget {
  final String title;
  const _AppsSectionDivider({required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Container(height: 1, color: Theme.of(context).dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          Expanded(child: Container(height: 1, color: Theme.of(context).dividerColor)),
        ],
      );
}

class _FeaturedCarousel extends StatefulWidget {
  final List<RemoteApp> apps;
  final bool isArabic;
  final ValueChanged<RemoteApp> onTap;
  const _FeaturedCarousel({required this.apps, required this.isArabic, required this.onTap});

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: .94);
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || widget.apps.length < 2 || !_controller.hasClients) return;
      _index = (_index + 1) % widget.apps.length;
      _controller.animateToPage(_index, duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 210,
        child: PageView.builder(
          controller: _controller,
          physics: const BouncingScrollPhysics(),
          itemCount: widget.apps.length,
          onPageChanged: (v) => _index = v,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: _FeaturedBannerCard(app: widget.apps[index], isArabic: widget.isArabic, onTap: () => widget.onTap(widget.apps[index])),
          ),
        ),
      );
}

class _FeaturedBannerCard extends StatefulWidget {
  final RemoteApp app;
  final bool isArabic;
  final VoidCallback onTap;
  const _FeaturedBannerCard({required this.app, required this.isArabic, required this.onTap});

  @override
  State<_FeaturedBannerCard> createState() => _FeaturedBannerCardState();
}

class _FeaturedBannerCardState extends State<_FeaturedBannerCard> with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _shineController;
  int _image = 0;

  @override
  void initState() {
    super.initState();
    _shineController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2900))..repeat();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.app.screenshots.length < 2) return;
      setState(() => _image = (_image + 1) % widget.app.screenshots.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final subtitle = app.displaySubtitle(widget.isArabic);
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                switchInCurve: Curves.easeOutCubic,
                child: SizedBox.expand(
                  key: ValueKey('${app.id}-$_image'),
                  child: Image.network(
                    app.screenshots[_image],
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: widget.isArabic ? Alignment.centerRight : Alignment.centerLeft,
                  end: widget.isArabic ? Alignment.centerLeft : Alignment.centerRight,
                  colors: const [Colors.black, Color(0xE6000000), Color(0x66000000), Color(0x12000000)],
                  stops: const [0, .42, .72, 1],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _shineController,
              builder: (context, _) {
                final t = _shineController.value;
                final travel = 1.5 - (3.0 * t);
                final glow = .28 + (.18 * math.sin(t * math.pi * 2).abs());
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      offset: Offset(MediaQuery.sizeOf(context).width * travel, -70 + 180 * t),
                      child: Transform.rotate(
                        angle: -.72,
                        child: Container(
                          width: 62,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .25), Colors.white.withValues(alpha: .62), Colors.white.withValues(alpha: .18), Colors.white.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withValues(alpha: glow), width: 1.15),
                        boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: glow * .25), blurRadius: 10, spreadRadius: -.5)],
                      ),
                    ),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Align(
                alignment: widget.isArabic ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox(
                  width: 205,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _NetworkAppIcon(url: app.iconUrl, size: 58, radius: 14),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(app.displayName(widget.isArabic), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, height: 1.12)),
                          ),
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 11),
                        Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w500)),
                      ],
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .18))),
                            child: Text(app.version.isEmpty ? tr('جديد', 'New') : 'v${app.version}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final RemoteApp app;
  final bool isArabic;
  final AppDownloadSnapshot state;
  final VoidCallback onDownload;
  final VoidCallback onTogglePause;
  final ValueChanged<ImportedFile> onSign;
  final VoidCallback onTap;

  const _AppCard({
    required this.app,
    required this.isArabic,
    required this.state,
    required this.onDownload,
    required this.onTogglePause,
    required this.onSign,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = app.displayName(isArabic);
    final subtitle = app.displaySubtitle(isArabic);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            _NetworkAppIcon(url: app.iconUrl, size: 62, radius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
                  ],
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 7,
                    runSpacing: 3,
                    children: [
                      if (app.version.isNotEmpty) _meta(context, 'v${app.version}'),
                      if (app.size > 0) _meta(context, _size(app.size)),
                      if (app.category.isNotEmpty) _meta(context, app.category),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _DownloadAction(
              state: state,
              onDownload: onDownload,
              onPause: onTogglePause,
              onSign: state.file == null ? null : () => onSign(state.file!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, String text) => Text(text, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .42), fontWeight: FontWeight.w600));

  String _size(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _DownloadAction extends StatelessWidget {
  final AppDownloadSnapshot state;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback? onSign;
  const _DownloadAction({required this.state, required this.onDownload, required this.onPause, required this.onSign});

  @override
  Widget build(BuildContext context) {
    if (state.downloading) {
      return SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 39,
              height: 39,
              child: CircularProgressIndicator(value: state.progress, strokeWidth: 3.2, strokeCap: StrokeCap.round),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPause,
                child: SizedBox(
                  width: 31,
                  height: 31,
                  child: Icon(state.paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill, size: 15, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.file != null) {
      return FilledButton(
        onPressed: onSign,
        style: FilledButton.styleFrom(minimumSize: const Size(82, 36), padding: const EdgeInsets.symmetric(horizontal: 18), shape: const StadiumBorder()),
        child: Text(tr('توقيع', 'Sign'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      );
    }

    return FilledButton(
      onPressed: onDownload,
      style: FilledButton.styleFrom(minimumSize: const Size(82, 36), padding: const EdgeInsets.symmetric(horizontal: 18), shape: const StadiumBorder()),
      child: Text(tr('تنزيل', 'GET'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }
}

class _NetworkAppIcon extends StatelessWidget {
  final String url;
  final double size;
  final double radius;
  const _NetworkAppIcon({required this.url, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
          child: url.isEmpty
              ? Icon(CupertinoIcons.app_fill, color: Theme.of(context).colorScheme.primary, size: size * .48)
              : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(CupertinoIcons.app_fill, color: Theme.of(context).colorScheme.primary, size: size * .48)),
        ),
      );
}
