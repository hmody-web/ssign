import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_store.dart';
import '../services/admin_service.dart';
import '../services/localized.dart';
import '../services/signing_service.dart';
import '../services/booma_public_service.dart';
import '../services/app_version_service.dart';
import '../services/library_sources_store.dart';
import '../services/source_catalog_service.dart';
import '../widgets/app_notice.dart';
import '../widgets/glass_card.dart';
import '../widgets/native_ios_controls.dart';
import 'certificates_screen.dart';
import 'admin_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Key? topKey;
  const SettingsScreen({super.key, this.topKey});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late Future<bool> _adminVisibility;
  BoomaUpdateInfo? _updateInfo;
  String _installedVersion = '';
  String _installedBuild = '';
  bool _updateLoading = true;
  bool _updateBusy = false;
  bool _updateInstallStarted = false;
  double _updateProgress = 0;
  String? _updateError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _adminVisibility = AdminService.instance.isThisDeviceAdmin();
    _loadUpdateState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_updateBusy) _loadUpdateState();
    });
  }

  int _compareVersion(String a, String b) {
    List<int> parts(String value) => value.split(RegExp(r'[^0-9]+')).where((x) => x.isNotEmpty).map((x) => int.tryParse(x) ?? 0).toList();
    final aa = parts(a), bb = parts(b), count = aa.length > bb.length ? aa.length : bb.length;
    for (var i = 0; i < count; i++) {
      final av = i < aa.length ? aa[i] : 0;
      final bv = i < bb.length ? bb[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  bool get _hasUpdate {
    final info = _updateInfo;
    if (info == null || !info.active || info.ipaUrl.trim().isEmpty || info.version.trim().isEmpty) return false;
    final versionCompare = _compareVersion(info.version, _installedVersion);
    if (versionCompare > 0) return true;
    if (versionCompare < 0) return false;
    final targetBuild = int.tryParse(info.build);
    final currentBuild = int.tryParse(_installedBuild);
    return targetBuild != null && currentBuild != null && targetBuild > currentBuild;
  }

  Future<void> _loadUpdateState() async {
    try {
      final results = await Future.wait<dynamic>([
        AppVersionService.instance.current(),
        BoomaPublicService.instance.updateInfo(),
      ]);
      final installed = results[0] as InstalledAppInfo;
      final update = results[1] as BoomaUpdateInfo;
      if (!mounted) return;
      setState(() {
        _installedVersion = installed.version;
        _installedBuild = installed.build;
        _updateInfo = update;
        _updateLoading = false;
        _updateError = null;
        _updateInstallStarted = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateLoading = false;
        _updateError = tr('تعذر فحص التحديث حالياً', 'Could not check for updates');
      });
    }
  }

  Future<void> _installUpdate() async {
    final info = _updateInfo;
    if (info == null || !_hasUpdate || _updateBusy) return;
    setState(() { _updateBusy = true; _updateProgress = 0; _updateError = null; });
    try {
      final file = await BoomaPublicService.instance.downloadUpdate(info.ipaUrl, onProgress: (p) {
        if (mounted) setState(() => _updateProgress = p * .92);
      });
      if (!mounted) return;
      setState(() => _updateProgress = .95);
      final launched = await SigningService().install(file.path);
      if (!launched) throw Exception(tr('تعذر بدء مثبت التحديث', 'Could not start the update installer'));
      var started = false;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        started = await SigningService().installDownloadStarted();
        if (started) break;
      }
      if (!started) throw Exception(tr('لم يبدأ مثبت iOS، حاول مرة أخرى', 'The iOS installer did not start. Try again.'));
      if (!mounted) return;
      setState(() { _updateBusy = false; _updateProgress = 1; _updateInstallStarted = true; });
      showAppNotice(context, tr('بدأ تثبيت التحديث. سيتم إغلاق بومة تلقائياً.', 'Update installation started. Booma will close automatically.'), type: AppNoticeType.success, duration: const Duration(seconds: 2));
      // A GET for app.ipa starts only after the user confirms Install. Keep the
      // local OTA server alive until iOS has fully received the IPA, otherwise
      // terminating Booma early can corrupt/cancel larger updates. Then close
      // two seconds later.
      if (Platform.isIOS) {
        for (var i = 0; i < 240; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (await SigningService().installDownloadFinished()) break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        exit(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _updateBusy = false; _updateProgress = 0; _updateError = e.toString().replaceFirst('Exception: ', ''); });
      showAppNotice(context, _updateError!, type: AppNoticeType.error);
    }
  }

  Widget _updateCard(BuildContext context) {
    final info = _updateInfo;
    final available = _hasUpdate;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    String buttonText;
    if (_updateLoading) {
      buttonText = tr('فحص…', 'Checking…');
    } else if (_updateBusy) {
      buttonText = '${(_updateProgress * 100).round()}%';
    } else if (_updateInstallStarted) {
      buttonText = tr('قيد التثبيت', 'Installing');
    } else if (available) {
      buttonText = tr('تحديث', 'Update');
    } else if (_updateError != null && info == null) {
      buttonText = tr('غير متاح', 'Unavailable');
    } else {
      buttonText = tr('محدّث', 'Up to date');
    }
    final subtitle = info?.description.trim().isNotEmpty == true
        ? info!.description
        : tr('متجر شامل لتطبيقاتك', 'Your complete app library');
    return Material(
      color: _settingsCardColor(context),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: onSurface.withValues(alpha: .10), width: .55), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/images/icon.png', width: 52, height: 52, fit: BoxFit.cover)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(info?.appName.trim().isNotEmpty == true ? info!.appName : 'Booma', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.35, color: onSurface.withValues(alpha: .50))),
            if (_updateError != null) ...[
              const SizedBox(height: 3),
              Text(_updateError!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: CupertinoColors.systemRed)),
            ] else if (info != null && info.version.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(available ? '${tr('متوفر', 'Available')} v${info.version}${info.build.isNotEmpty ? ' (${info.build})' : ''}' : '${tr('الإصدار الحالي', 'Current')} v$_installedVersion${_installedBuild.isNotEmpty ? ' ($_installedBuild)' : ''}', style: TextStyle(fontSize: 9.5, color: onSurface.withValues(alpha: .36))),
            ],
          ])),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            height: 36,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              color: available && !_updateBusy && !_updateInstallStarted ? Theme.of(context).colorScheme.primary : onSurface.withValues(alpha: .08),
              onPressed: available && !_updateBusy && !_updateInstallStarted ? _installUpdate : null,
              child: _updateBusy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: _updateProgress, strokeWidth: 2.2, color: Colors.white))
                  : Text(buttonText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: available && !_updateInstallStarted ? Colors.white : onSurface.withValues(alpha: .55))),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _refreshAdminVisibility() async {
    final next = AdminService.instance.isThisDeviceAdmin();
    if (mounted) setState(() => _adminVisibility = next);
    await next;
  }
  static final Uri _developerUrl = Uri.parse('https://scrptaty.com');

  Future<void> _openDeveloperSite(BuildContext context) async {
    final opened = await launchUrl(_developerUrl, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showAppNotice(context, tr('تعذر فتح موقع المطور', 'Could not open developer website'), type: AppNoticeType.error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppStore.instance,
        builder: (context, _) {
          final store = AppStore.instance;
          return ListView(
            key: const PageStorageKey('settings-main-scroll'),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              Text(tr('الإعدادات', 'Settings'), key: widget.topKey, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 16),

              _updateCard(context),
              const SizedBox(height: 9),

              _compactCard(
                context,
                icon: CupertinoIcons.checkmark_shield_fill,
                title: tr('الشهادات', 'Certificates'),
                subtitle: tr('إدارة P12 وProvisioning Profile', 'Manage P12 and provisioning profiles'),
                onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const _CertificatesPage())),
              ),
              const SizedBox(height: 9),

              FutureBuilder<bool>(
                future: _adminVisibility,
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _compactCard(
                      context,
                      icon: CupertinoIcons.lock_shield_fill,
                      title: tr('لوحة التحكم', 'Admin Control Panel'),
                      subtitle: tr('إدارة بومة من هذا الجهاز الموثوق', 'Manage Booma from this trusted device'),
                      onTap: () async {
                        await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const AdminGateScreen()));
                        await _refreshAdminVisibility();
                      },
                    ),
                  );
                },
              ),

              _sourcesCard(context),
              const SizedBox(height: 9),

              _compactCard(
                context,
                icon: CupertinoIcons.bolt_fill,
                title: tr('توقيع تلقائي بعد التنزيل', 'Auto-sign after download'),
                subtitle: tr('تنزيل ثم توقيع وبدء التثبيت تلقائياً', 'Download, sign, then start installation automatically'),
                trailing: Switch.adaptive(
                  value: store.autoSignAfterDownload,
                  onChanged: (value) async {
                    if (value) {
                      final runtime = await SigningService().automaticSigningState();
                      if (runtime['ready'] != true && store.identities.isEmpty) {
                        if (context.mounted) showAppNotice(context, tr('بيانات التوقيع غير متاحة حالياً.', 'Signing data is not available right now.'), type: AppNoticeType.warning);
                        return;
                      }
                    }
                    await store.setAutoSignAfterDownload(value);
                  },
                ),
              ),
              const SizedBox(height: 9),

              _compactCard(
                context,
                icon: store.theme == 'light' ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill,
                title: tr('المظهر', 'Appearance'),
                subtitle: store.theme == 'light' ? tr('فاتح', 'Light') : tr('داكن', 'Dark'),
                onTap: () => _showThemeSheet(context, store),
              ),
              const SizedBox(height: 9),

              _compactCard(
                context,
                icon: CupertinoIcons.globe,
                title: tr('اللغة', 'Language'),
                subtitle: store.languageCode == 'ar' ? 'العربية' : 'English',
                onTap: () => _showLanguageSheet(context, store),
              ),
              const SizedBox(height: 9),

              _settingsGroup(
                context,
                children: [
                  _settingsInfoRow(context, CupertinoIcons.shield, tr('التوقيع المحلي', 'Local Signing'), tr('تتم معالجة بيانات التوقيع على الجهاز', 'Signing data is processed on-device')),
                  _settingsInfoRow(context, CupertinoIcons.folder, tr('الملفات الموقعة', 'Signed Output'), tr('إدارة ملفات IPA الموقعة من قسم التوقيع', 'Manage signed IPA files from the Sign tab')),
                  _settingsInfoRow(context, CupertinoIcons.lock, tr('الخصوصية', 'Privacy'), tr('تبقى الشهادات داخل مساحة التطبيق', 'Certificates stay inside the app sandbox'), last: true),
                ],
              ),
              const SizedBox(height: 9),
              _developerCard(context),
            ],
          );
        },
      );

  Color _settingsCardColor(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Color.alphaBlend(
      onSurface.withValues(alpha: theme.brightness == Brightness.dark ? .055 : .028),
      theme.scaffoldBackgroundColor,
    );
  }

  Widget _compactCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final divider = Theme.of(context).colorScheme.onSurface.withValues(alpha: .10);
    return Material(
      color: _settingsCardColor(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: divider, width: .55), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            _tileIcon(context, icon, size: 42),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.3, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
            ])),
            const SizedBox(width: 8),
            trailing ?? Icon(CupertinoIcons.chevron_forward, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .33)),
          ]),
        ),
      ),
    );
  }

  Widget _settingsGroup(BuildContext context, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _settingsCardColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .10), width: .55),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _settingsInfoRow(BuildContext context, IconData icon, String title, String subtitle, {bool last = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10.5),
    decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .09), width: .55))),
    child: Row(children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .46))),
      ])),
    ]),
  );

  Future<void> _showThemeSheet(BuildContext context, AppStore store) async {
    await showCupertinoModalPopup<void>(context: context, builder: (c) => CupertinoActionSheet(
      title: Text(tr('مظهر التطبيق', 'App Appearance')),
      actions: [
        CupertinoActionSheetAction(onPressed: () { store.setTheme('dark'); Navigator.pop(c); }, child: Text(tr('داكن', 'Dark'))),
        CupertinoActionSheetAction(onPressed: () { store.setTheme('light'); Navigator.pop(c); }, child: Text(tr('فاتح', 'Light'))),
      ],
      cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(c), child: Text(tr('إلغاء', 'Cancel'))),
    ));
  }

  Future<void> _showLanguageSheet(BuildContext context, AppStore store) async {
    await showCupertinoModalPopup<void>(context: context, builder: (c) => CupertinoActionSheet(
      title: Text(tr('اللغة', 'Language')),
      actions: [
        CupertinoActionSheetAction(onPressed: () { store.setLanguage('ar'); Navigator.pop(c); }, child: const Text('العربية')),
        CupertinoActionSheetAction(onPressed: () { store.setLanguage('en'); Navigator.pop(c); }, child: const Text('English')),
      ],
      cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(c), child: Text(tr('إلغاء', 'Cancel'))),
    ));
  }


  Widget _sourcesCard(BuildContext context) => AnimatedBuilder(
        animation: LibrarySourcesStore.instance,
        builder: (context, _) {
          final sources = LibrarySourcesStore.instance.sources;
          final enabledCount = sources.where((item) => item.enabled).length;
          return _compactCard(
            context,
            icon: CupertinoIcons.square_stack_3d_up_fill,
            title: tr('المصادر', 'Sources'),
            subtitle: tr('$enabledCount من ${sources.length} مصادر مفعّلة', '$enabledCount of ${sources.length} sources enabled'),
            onTap: () => _openSourcesPage(context),
          );
        },
      );

  Future<void> _openSourcesPage(BuildContext context) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: Theme.of(pageContext).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            title: Text(tr('مصادر التطبيقات', 'App Sources'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          body: AnimatedBuilder(
            animation: LibrarySourcesStore.instance,
            builder: (context, _) {
              final sourceStore = LibrarySourcesStore.instance;
              final sources = sourceStore.sources;
              final enabledCount = sources.where((item) => item.enabled).length;
              final primary = Theme.of(context).colorScheme.primary;
              final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: .50);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                children: [
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(CupertinoIcons.antenna_radiowaves_left_right, color: primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('مكتبات بومة', 'Booma Libraries'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text(
                                tr('$enabledCount من ${sources.length} مصادر ظاهرة حالياً', '$enabledCount of ${sources.length} sources are currently visible'),
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      children: [
                        for (var i = 0; i < sources.length; i++) ...[
                          _sourceRow(context, sources[i]),
                          if (i != sources.length - 1)
                            Divider(height: 1, indent: 56, color: Theme.of(context).dividerColor.withValues(alpha: .68)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  NativeIOSButton(
                    title: tr('إضافة مصدر جديد', 'Add New Source'),
                    systemImage: 'plus.circle.fill',
                    onPressed: () => _showAddSourceSheet(context),
                    prominent: true,
                    height: 50,
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _showSourceHelp(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(CupertinoIcons.info_circle_fill, size: 15, color: primary),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                tr('طريقة إضافة أي مكتبة JSON عبر رابط URL', 'How to add a JSON library using a URL'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sourceCatalogSection(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sourceCatalogSection(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: .48);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(CupertinoIcons.square_grid_2x2_fill, color: primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('مكتبة المصادر', 'Source Library'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(
                    tr('مصادر جاهزة يضيفها الأدمن من الخادم', 'Ready-to-use sources published by the admin'),
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(tr('محدّثة', 'Live'), style: TextStyle(color: primary, fontSize: 9.5, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<SourceCatalogItem>>(
          future: SourceCatalogService.instance.fetch(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: const Center(child: CupertinoActivityIndicator(radius: 12)),
              );
            }
            if (snapshot.hasError) {
              return GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(CupertinoIcons.exclamationmark_triangle_fill, color: CupertinoColors.systemOrange, size: 27),
                    const SizedBox(height: 8),
                    Text(tr('تعذر تحميل مكتبة المصادر', 'Could not load source library'), style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${snapshot.error}'.replaceFirst('Exception: ', ''), textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: muted)),
                  ],
                ),
              );
            }
            final items = snapshot.data ?? const <SourceCatalogItem>[];
            if (items.isEmpty) {
              return GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                child: Column(
                  children: [
                    Icon(CupertinoIcons.archivebox, color: muted, size: 25),
                    const SizedBox(height: 7),
                    Text(tr('لا توجد مصادر منشورة حالياً', 'No published sources yet'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 620 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: columns == 3 ? .78 : .72,
                  ),
                  itemBuilder: (context, index) => _sourceCatalogCard(context, items[index]),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _sourceCatalogCard(BuildContext context, SourceCatalogItem item) {
    final store = LibrarySourcesStore.instance;
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: .48);
    final added = store.containsCatalog(item.id, url: item.url);
    return GlassCard(
      radius: 23,
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 10),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              color: primary.withValues(alpha: .08),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .65)),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.imageUrl.isEmpty
                ? Icon(CupertinoIcons.square_stack_3d_up_fill, color: primary, size: 29)
                : Image.network(
                    item.imageUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => Icon(CupertinoIcons.square_stack_3d_up_fill, color: primary, size: 29),
                  ),
          ),
          const SizedBox(height: 9),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              item.description.trim().isEmpty ? tr('مكتبة تطبيقات جاهزة للإضافة', 'Ready app source') : item.description.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.8, height: 1.35, color: muted),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(12),
              color: added ? onSurface.withValues(alpha: .07) : primary.withValues(alpha: .14),
              disabledColor: onSurface.withValues(alpha: .055),
              onPressed: added
                  ? null
                  : () async {
                      try {
                        await store.addCatalogSource(
                          catalogId: item.id,
                          name: item.name,
                          url: item.url,
                          description: item.description,
                          imageUrl: item.imageUrl,
                        );
                        if (context.mounted) {
                          showAppNotice(
                            context,
                            tr('تمت إضافة ${item.name}', '${item.name} added'),
                            type: AppNoticeType.success,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showAppNotice(
                            context,
                            e.toString().replaceFirst('FormatException: ', ''),
                            type: AppNoticeType.error,
                          );
                        }
                      }
                    },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(added ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.plus_circle_fill, size: 14, color: added ? muted : primary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      added ? tr('مضاف', 'Added') : tr('إضافة المصدر', 'Add Source'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: added ? muted : primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(BuildContext context, LibrarySourceConfig source) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: .48);
    String host = source.url;
    try {
      host = Uri.parse(source.url).host;
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: source.enabled ? .13 : .055),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: source.imageUrl.trim().isNotEmpty
                ? Image.network(
                    source.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      source.id == 'nsign' ? CupertinoIcons.cloud_download_fill : CupertinoIcons.tray_full_fill,
                      size: 17,
                      color: source.enabled ? primary : muted,
                    ),
                  )
                : Icon(
                    source.id == 'nsign' ? CupertinoIcons.cloud_download_fill : CupertinoIcons.tray_full_fill,
                    size: 17,
                    color: source.enabled ? primary : muted,
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (source.builtIn) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          tr('مدمج', 'Built-in'),
                          style: TextStyle(fontSize: 8.5, color: primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
                if (source.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    source.description.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: muted),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 9.5, color: muted.withValues(alpha: .84)),
                ),
              ],
            ),
          ),
          if (!source.builtIn)
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              minSize: 32,
              onPressed: () async {
                await LibrarySourcesStore.instance.removeCustomSource(source.id);
                if (context.mounted) {
                  showAppNotice(
                    context,
                    tr('تم حذف المصدر', 'Source removed'),
                    type: AppNoticeType.success,
                  );
                }
              },
              child: const Icon(CupertinoIcons.trash, size: 17, color: CupertinoColors.systemRed),
            ),
          CupertinoSwitch(
            value: source.enabled,
            activeColor: primary,
            onChanged: (value) => LibrarySourcesStore.instance.setEnabled(source.id, value),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSourceSheet(BuildContext context) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottom = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
          child: GlassCard(
            radius: 30,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _tileIcon(sheetContext, CupertinoIcons.link),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('إضافة مصدر جديد', 'Add a New Source'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(
                            tr('ألصق رابط المكتبة؛ بومة يحاول التعرّف تلقائياً على أشهر صيغ JSON.', 'Paste a library URL; Booma automatically detects common JSON source formats.'),
                            style: TextStyle(fontSize: 11.5, color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: .5)),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 36,
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Icon(CupertinoIcons.xmark_circle_fill, size: 26),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                CupertinoTextField(
                  controller: nameController,
                  placeholder: tr('اسم المصدر (اختياري)', 'Source name (optional)'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Theme.of(sheetContext).dividerColor),
                  ),
                ),
                const SizedBox(height: 10),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: CupertinoTextField(
                    controller: urlController,
                    placeholder: 'https://example.com/apps.json',
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: .055),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Theme.of(sheetContext).dividerColor),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  tr(
                    'يدعم بومة القوائم المباشرة وصيغ apps / data / items / results / packages ومصادر AltStore وFeather. ويفضّل وجود رابط IPA مباشر لكل تطبيق.',
                    'Booma supports direct lists, apps/data/items/results/packages containers, plus AltStore and Feather-style sources. A direct IPA URL per app is preferred.',
                  ),
                  style: TextStyle(fontSize: 10.5, height: 1.45, color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: .46)),
                ),
                const SizedBox(height: 16),
                NativeIOSButton(
                  title: tr('إضافة المصدر', 'Add Source'),
                  systemImage: 'plus',
                  prominent: true,
                  height: 48,
                  onPressed: () async {
                    try {
                      await LibrarySourcesStore.instance.addCustomSource(
                        url: urlController.text,
                        name: nameController.text,
                      );
                      if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                    } catch (e) {
                      if (sheetContext.mounted) {
                        showAppNotice(
                          sheetContext,
                          e.toString().replaceFirst('FormatException: ', ''),
                          type: AppNoticeType.error,
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    nameController.dispose();
    urlController.dispose();
    if (result == true && context.mounted) {
      showAppNotice(
        context,
        tr('تمت إضافة المصدر وسيظهر ضمن تصنيفات المكتبة', 'Source added and will appear in the library filters'),
        type: AppNoticeType.success,
      );
    }
  }

  Future<void> _showSourceHelp(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          child: GlassCard(
            radius: 30,
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _tileIcon(sheetContext, CupertinoIcons.book_circle_fill),
                    const SizedBox(width: 11),
                    Expanded(child: Text(tr('طريقة إضافة مصدر URL', 'Adding a URL Source'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 36,
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Icon(CupertinoIcons.xmark_circle_fill, size: 26),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                _helpStep(sheetContext, '1', tr('انسخ رابط مكتبة موثوقة يعيد بيانات JSON.', 'Copy a trusted library URL that returns JSON data.')),
                _helpStep(sheetContext, '2', tr('اضغط «إضافة مصدر»، ألصق الرابط واكتب اسماً إن أردت.', 'Tap “Add Source”, paste the URL, and optionally give it a name.')),
                _helpStep(sheetContext, '3', tr('بعد الإضافة سيظهر المصدر تلقائياً كتصنيف في صفحة التطبيقات ويمكن إخفاؤه من هنا.', 'After adding it, the source appears automatically as a filter in Apps and can be hidden here.')),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    tr(
                      'بومة يحاول قراءة أغلب صيغ المكتبات الشائعة تلقائياً: قائمة JSON مباشرة، apps، data، items، results، packages، ومصادر AltStore/Feather مع versions وdownloadURL. كما يتعرّف على أشهر أسماء حقول الأيقونة والإصدار ورابط IPA. استخدم HTTPS ومصدراً تثق به؛ جلب المكتبة والتصفح لا ينفذان أي توقيع.',
                      'Booma automatically reads many common source layouts: direct JSON lists, apps, data, items, results, packages, and AltStore/Feather sources with versions and downloadURL. It also recognizes common icon, version, and IPA URL field names. Prefer HTTPS and trusted sources; browsing and loading do not sign anything.',
                    ),
                    style: TextStyle(fontSize: 11.5, height: 1.55, color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: .66)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _helpStep(BuildContext context, String number, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Text(number, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600)))),
          ],
        ),
      );

  Widget _settingsChoice(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => NativeIOSButton(
        key: ValueKey('appearance-$title-$selected'),
        title: title,
        systemImage: selected ? 'checkmark.circle.fill' : null,
        onPressed: onTap,
        prominent: selected,
        height: 54,
      );

  Widget _tileIcon(BuildContext context, IconData icon, {double size = 46}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      );

  Widget _developerCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: .52);
    final divider = Theme.of(context).colorScheme.onSurface.withValues(alpha: .10);
    return Material(
      color: _settingsCardColor(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDeveloperSite(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: divider, width: .55),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .22)),
                  image: const DecorationImage(image: AssetImage('assets/images/avatar.png'), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('محمد السراي', 'Mohammed Al-Saray'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(tr('مبرمج ومطور تطبيقات ومواقع ويب', 'Software, app and web developer'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 11.3)),
              ])),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_forward, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .33)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData i, String t, String s) => Row(children: [
        Icon(i),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(s, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
      ]);
}

class _CertificatesPage extends StatelessWidget {
  const _CertificatesPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('الشهادات', 'Certificates')), backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
        body: const CertificatesScreen(),
      );
}
