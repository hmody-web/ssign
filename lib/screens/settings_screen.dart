import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_store.dart';
import '../services/admin_service.dart';
import '../services/localized.dart';
import '../services/signing_service.dart';
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
