import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_store.dart';
import '../services/admin_service.dart';
import '../services/localized.dart';
import '../services/signing_service.dart';
import '../services/library_sources_store.dart';
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

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<bool> _adminVisibility;

  @override
  void initState() {
    super.initState();
    _adminVisibility = AdminService.instance.isThisDeviceAdmin();
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
              Text(tr('الإعدادات', 'Settings'), key: widget.topKey, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 20),
              GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  leading: _tileIcon(context, CupertinoIcons.checkmark_shield_fill),
                  title: Text(tr('الشهادات', 'Certificates'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(tr('إدارة شهادات P12 وملفات provisioning', 'Manage P12 and provisioning identities')),
                  trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                  onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const _CertificatesPage())),
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      _tileIcon(context, CupertinoIcons.globe),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('اللغة', 'Language'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                        const SizedBox(height: 2),
                        Text(tr('اختر لغة واجهة التطبيق', 'Choose the app interface language'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
                      ])),
                    ]),
                    const SizedBox(height: 15),
                    Row(children: [
                      Expanded(child: _settingsChoice(
                        context,
                        selected: store.languageCode == 'ar',
                        icon: CupertinoIcons.textformat_alt,
                        title: 'العربية',
                        subtitle: 'RTL',
                        onTap: () => store.setLanguage('ar'),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _settingsChoice(
                        context,
                        selected: store.languageCode == 'en',
                        icon: CupertinoIcons.textformat,
                        title: 'English',
                        subtitle: 'LTR',
                        onTap: () => store.setLanguage('en'),
                      )),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      _tileIcon(context, store.theme == 'light' ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('مظهر التطبيق', 'App Appearance'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                        const SizedBox(height: 2),
                        Text(tr('اختر المظهر الأنسب لك وسيتم حفظه تلقائياً', 'Choose your preferred appearance; it is saved automatically'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
                      ])),
                    ]),
                    const SizedBox(height: 15),
                    Row(children: [
                      Expanded(child: _settingsChoice(
                        context,
                        selected: store.theme == 'dark',
                        icon: CupertinoIcons.moon_stars_fill,
                        title: tr('داكن', 'Dark'),
                        subtitle: tr('مريح للعين', 'Easy on eyes'),
                        onTap: () => store.setTheme('dark'),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _settingsChoice(
                        context,
                        selected: store.theme == 'light',
                        icon: CupertinoIcons.sun_max_fill,
                        title: tr('فاتح', 'Light'),
                        subtitle: tr('واضح ومشرق', 'Bright & clear'),
                        onTap: () => store.setTheme('light'),
                      )),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sourcesCard(context),
              const SizedBox(height: 14),
              GlassCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  secondary: _tileIcon(context, CupertinoIcons.bolt_fill),
                  title: Text(tr('التوقيع التلقائي بعد التنزيل', 'Auto-sign after download'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(tr('ينزّل التطبيق ثم يوقّعه ويبدأ التثبيت تلقائياً بالخلفية', 'Download, sign, then start installation automatically in the background')),
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
                    if (context.mounted) {
                      showAppNotice(context, value ? tr('تم تفعيل التوقيع التلقائي', 'Auto-sign enabled') : tr('تم إيقاف التوقيع التلقائي', 'Auto-sign disabled'), type: AppNoticeType.success);
                    }
                  },
                ),
              ),

              FutureBuilder<bool>(
                future: _adminVisibility,
                builder: (context, snapshot) {
                  // Important: while checking, or if the server cannot verify this
                  // device, render absolutely nothing. This prevents the Admin card
                  // from briefly flashing on unauthorized devices.
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Column(
                    children: [
                      const SizedBox(height: 14),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () async {
                            await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const AdminGateScreen()));
                            await _refreshAdminVisibility();
                          },
                          child: GlassCard(
                            child: Row(children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: .65)]),
                                  borderRadius: BorderRadius.circular(17),
                                  boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: .24), blurRadius: 20, offset: const Offset(0, 8))],
                                ),
                                child: const Icon(CupertinoIcons.lock_shield_fill, color: Colors.white, size: 27),
                              ),
                              const SizedBox(width: 13),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tr('لوحة تحكم الأدمن', 'Admin Control Panel'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                                const SizedBox(height: 3),
                                Text(tr('دخول مشفر ومربوط بهذا الجهاز فقط', 'Encrypted access locked to this device'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .52))),
                              ])),
                              Icon(CupertinoIcons.chevron_forward, size: 18, color: Theme.of(context).colorScheme.primary),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  children: [
                    _row(CupertinoIcons.shield, tr('التوقيع المحلي', 'Local Signing'), tr('تتم معالجة P12 وملف mobileprovision على الجهاز', 'P12 + mobileprovision are processed on-device')),
                    const Divider(height: 26),
                    _row(CupertinoIcons.folder, tr('الملفات الموقعة', 'Signed Output'), tr('يمكن إدارة ملفات IPA الموقعة من قسم التوقيع', 'Manage signed IPA files from the Sign tab')),
                    const Divider(height: 26),
                    _row(CupertinoIcons.lock, tr('الخصوصية', 'Privacy'), tr('تبقى الشهادات داخل مساحة التطبيق', 'Certificates stay inside the app sandbox')),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _developerCard(context),
            ],
          );
        },
      );


  Widget _sourcesCard(BuildContext context) => AnimatedBuilder(
        animation: LibrarySourcesStore.instance,
        builder: (context, _) {
          final sources = LibrarySourcesStore.instance.sources;
          final enabledCount = sources.where((item) => item.enabled).length;
          final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: .50);
          final primary = Theme.of(context).colorScheme.primary;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _openSourcesPage(context),
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
                child: Row(
                  children: [
                    _tileIcon(context, CupertinoIcons.square_stack_3d_up_fill),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('مصادر التطبيقات', 'App Sources'),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tr(
                              '$enabledCount مصادر مفعّلة • اضغط للإدارة',
                              '$enabledCount sources enabled • Tap to manage',
                            ),
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        '$enabledCount/${sources.length}',
                        style: TextStyle(color: primary, fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(CupertinoIcons.chevron_forward, size: 17, color: muted),
                  ],
                ),
              ),
            ),
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
                ],
              );
            },
          ),
        ),
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
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: source.enabled ? .13 : .055),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
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
                const SizedBox(height: 2),
                Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 10.5, color: muted),
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

  Widget _tileIcon(BuildContext context, IconData icon) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      );

  Widget _developerCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: .58);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _openDeveloperSite(context),
        child: GlassCard(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(80),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .28)),
                  image: const DecorationImage(image: AssetImage('assets/images/avatar.png'), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('محمد السراي', 'Mohammed Al-Saray'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('مبرمج ومطور تطبيقات ومواقع ويب', 'Software, app and web developer'), style: TextStyle(color: muted, fontSize: 12.5, height: 1.45)),
              ])),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.arrow_up_left_square, size: 19, color: Theme.of(context).colorScheme.primary),
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
