import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/remote_app.dart';
import '../models/sign_models.dart';
import '../services/app_download_manager.dart';
import '../services/localized.dart';

class AppDetailScreen extends StatefulWidget {
  final RemoteApp app;
  final bool isArabic;
  final List<RemoteApp> libraryApps;
  final ValueChanged<ImportedFile> onSign;

  const AppDetailScreen({
    super.key,
    required this.app,
    required this.isArabic,
    required this.libraryApps,
    required this.onSign,
  });

  @override
  State<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends State<AppDetailScreen> {
  final _downloads = AppDownloadManager.instance;
  RemoteApp get app => widget.app;

  Future<void> _download() async {
    try {
      await _downloads.start(app);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr('فشل تنزيل التطبيق', 'Download failed')}: ${_friendlyError(e)}')),
      );
    }
  }

  void _signAndLeave(ImportedFile file) {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    widget.onSign(file);
  }

  void _openSimilar(RemoteApp item) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => AppDetailScreen(
          app: item,
          isArabic: widget.isArabic,
          libraryApps: widget.libraryApps,
          onSign: widget.onSign,
        ),
      ),
    );
  }

  String _friendlyError(Object e) {
    final s = e.toString().replaceFirst('HttpException: ', '').trim();
    if (s.contains('SocketException')) return tr('تحقق من اتصال الإنترنت', 'Check your internet connection');
    return s.isNotEmpty ? s : tr('تعذر إكمال العملية', 'Unable to complete the operation');
  }

  @override
  Widget build(BuildContext context) {
    final similar = widget.libraryApps
        .where((item) =>
            item.id != app.id &&
            app.category.trim().isNotEmpty &&
            item.category.trim().toLowerCase() == app.category.trim().toLowerCase())
        .take(8)
        .toList();
    final description = app.displaySubtitle(widget.isArabic);

    return Scaffold(
      body: AnimatedBuilder(
        animation: _downloads,
        builder: (context, _) {
          final state = _downloads.stateFor(app);
          return CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                stretch: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .92),
                surfaceTintColor: Colors.transparent,
                leading: Padding(
                  padding: const EdgeInsets.all(7),
                  child: _RoundButton(
                    icon: widget.isArabic ? CupertinoIcons.chevron_right : CupertinoIcons.chevron_left,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _Header(
                      app: app,
                      isArabic: widget.isArabic,
                      state: state,
                      onDownload: _download,
                      onTogglePause: () => _downloads.togglePause(app),
                      onSign: state.file == null ? null : () => _signAndLeave(state.file!),
                    ),
                    const SizedBox(height: 22),
                    _Stats(app: app),
                    const SizedBox(height: 28),
                    _SectionDivider(),
                    const SizedBox(height: 20),
                    _SectionTitle(tr('ما الجديد', "What's New")),
                    const SizedBox(height: 10),
                    Text(
                      app.version.trim().isEmpty
                          ? tr('معلومات الإصدار غير متوفرة', 'Version information is unavailable')
                          : '${tr('الإصدار', 'Version')} ${app.version}',
                      style: TextStyle(fontSize: 15, height: 1.55, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .72)),
                    ),
                    if (app.createdAt != null) ...[
                      const SizedBox(height: 5),
                      Text(_formatDate(app.createdAt!), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .42))),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _SectionDivider(),
                      const SizedBox(height: 20),
                      _SectionTitle(tr('حول التطبيق', 'About this app')),
                      const SizedBox(height: 10),
                      Text(description, style: TextStyle(fontSize: 15, height: 1.65, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .78))),
                    ],
                    if (app.screenshots.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _SectionDivider(),
                      const SizedBox(height: 20),
                      _SectionTitle(tr('معاينة', 'Preview')),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 420,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: app.screenshots.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) => _Screenshot(url: app.screenshots[index], onTap: () => _showPreview(index)),
                        ),
                      ),
                    ],
                    if (similar.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _SectionDivider(),
                      const SizedBox(height: 20),
                      _SectionTitle(tr('تطبيقات مشابهة', 'Similar Apps')),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 132,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: similar.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 13),
                          itemBuilder: (context, index) => _SimilarApp(app: similar[index], isArabic: widget.isArabic, onTap: () => _openSimilar(similar[index])),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPreview(int initial) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .9),
      builder: (context) => _PreviewDialog(urls: app.screenshots, initial: initial),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return '$d/$m/${local.year}';
  }
}

class _Header extends StatelessWidget {
  final RemoteApp app;
  final bool isArabic;
  final AppDownloadSnapshot state;
  final VoidCallback onDownload;
  final VoidCallback onTogglePause;
  final VoidCallback? onSign;

  const _Header({
    required this.app,
    required this.isArabic,
    required this.state,
    required this.onDownload,
    required this.onTogglePause,
    required this.onSign,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = app.displaySubtitle(isArabic);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AppIcon(url: app.iconUrl, size: 122, radius: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.displayName(isArabic), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 25, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -.5)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.3, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
                ],
                const SizedBox(height: 14),
                if (state.downloading)
                  _ProgressPauseButton(state: state, onTap: onTogglePause)
                else if (state.file != null)
                  FilledButton(
                    onPressed: onSign,
                    style: FilledButton.styleFrom(minimumSize: const Size(92, 38), padding: const EdgeInsets.symmetric(horizontal: 23), shape: const StadiumBorder()),
                    child: Text(tr('توقيع', 'Sign'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  )
                else
                  FilledButton(
                    onPressed: onDownload,
                    style: FilledButton.styleFrom(minimumSize: const Size(92, 38), padding: const EdgeInsets.symmetric(horizontal: 23), shape: const StadiumBorder()),
                    child: Text(tr('تنزيل', 'GET'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressPauseButton extends StatelessWidget {
  final AppDownloadSnapshot state;
  final VoidCallback onTap;
  const _ProgressPauseButton({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 41,
              height: 41,
              child: CircularProgressIndicator(value: state.progress, strokeWidth: 3.4, strokeCap: StrokeCap.round),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(state.paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill, size: 15, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Stats extends StatelessWidget {
  final RemoteApp app;
  const _Stats({required this.app});

  @override
  Widget build(BuildContext context) {
    final items = <_StatData>[
      _StatData(tr('الحجم', 'SIZE'), Icons.storage_rounded, _size(app.size)),
      _StatData(tr('التصنيف', 'CATEGORY'), Icons.category_rounded, app.category.isEmpty ? '—' : app.category),
      _StatData(tr('الإصدار', 'VERSION'), Icons.new_releases_rounded, app.version.isEmpty ? '—' : app.version),
      const _StatData('المطور', Icons.person_rounded, 'Alsaray'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: Theme.of(context).dividerColor))),
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => _Stat(data: items[index]),
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _StatData {
  final String label;
  final IconData icon;
  final String value;
  const _StatData(this.label, this.icon, this.value);
}

class _Stat extends StatelessWidget {
  final _StatData data;
  const _Stat({required this.data});

  @override
  Widget build(BuildContext context) {
    final valueColor = Theme.of(context).colorScheme.primary;
    return Container(
      width: 126,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: valueColor.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: valueColor.withValues(alpha: .13)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(data.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .42))),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(data.icon, size: 21, color: valueColor),
              const SizedBox(width: 8),
              Flexible(child: Text(data.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: valueColor))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(height: 1, color: Theme.of(context).dividerColor);
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.4));
}

class _Screenshot extends StatelessWidget {
  final String url;
  final VoidCallback onTap;
  const _Screenshot({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 210,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
            child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(CupertinoIcons.photo, size: 38)), loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CupertinoActivityIndicator())),
          ),
        ),
      );
}

class _SimilarApp extends StatelessWidget {
  final RemoteApp app;
  final bool isArabic;
  final VoidCallback onTap;
  const _SimilarApp({required this.app, required this.isArabic, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AppIcon(url: app.iconUrl, size: 82, radius: 19),
              const SizedBox(height: 7),
              Text(app.displayName(isArabic), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(app.version.isEmpty ? app.category : 'v${app.version}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .43))),
            ],
          ),
        ),
      );
}

class _AppIcon extends StatelessWidget {
  final String url;
  final double size;
  final double radius;
  const _AppIcon({required this.url, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .1),
          child: url.isEmpty
              ? Icon(CupertinoIcons.app_fill, size: size * .43, color: Theme.of(context).colorScheme.primary)
              : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(CupertinoIcons.app_fill, size: size * .43, color: Theme.of(context).colorScheme.primary)),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .08),
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: Icon(icon, size: 20))),
      );
}

class _PreviewDialog extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const _PreviewDialog({required this.urls, required this.initial});

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initial;
    _controller = PageController(initialPage: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: Image.network(widget.urls[i], fit: BoxFit.contain, loadingBuilder: (context, child, p) => p == null ? child : const CupertinoActivityIndicator())),
                ),
              ),
              PositionedDirectional(
                top: 10,
                start: 12,
                child: _RoundButton(icon: CupertinoIcons.xmark, onTap: () => Navigator.of(context).pop()),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_index + 1} / ${widget.urls.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
