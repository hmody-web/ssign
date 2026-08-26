import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_store.dart';
import '../services/localized.dart';
import '../widgets/app_notice.dart';
import '../widgets/glass_card.dart';
import 'certificates_screen.dart';
import 'admin_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Key? topKey;
  const SettingsScreen({super.key, this.topKey});
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
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              Text(tr('الإعدادات', 'Settings'), key: topKey, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
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
                  children: [
                    Row(
                      children: [
                        _tileIcon(context, CupertinoIcons.globe),
                        const SizedBox(width: 12),
                        Expanded(child: Text(tr('اللغة', 'Language'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: SegmentedButton<String>(
                          style: ButtonStyle(
                            visualDensity: VisualDensity.comfortable,
                            shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          ),
                          segments: const [
                            ButtonSegment(value: 'ar', icon: Icon(CupertinoIcons.textformat_alt, size: 17), label: Text('العربية')),
                            ButtonSegment(value: 'en', icon: Icon(CupertinoIcons.textformat, size: 17), label: Text('English')),
                          ],
                          selected: {store.languageCode},
                          onSelectionChanged: (v) => store.setLanguage(v.first),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      _tileIcon(context, store.theme == 'light' ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('مظهر التطبيق', 'App Appearance'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        Text(tr('اختر الوضع الفاتح أو الداكن وسيتم حفظ اختيارك', 'Choose light or dark mode and your choice will be saved'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
                      ])),
                    ]),
                    const SizedBox(height: 15),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'dark', icon: const Icon(CupertinoIcons.moon_fill), label: Text(tr('داكن', 'Dark'))),
                        ButtonSegment(value: 'light', icon: const Icon(CupertinoIcons.sun_max_fill), label: Text(tr('فاتح', 'Light'))),
                      ],
                      selected: {store.theme},
                      onSelectionChanged: (v) => store.setTheme(v.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const AdminGateScreen())),
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
