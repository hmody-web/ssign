import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_store.dart';
import '../services/localized.dart';
import '../widgets/glass_card.dart';
import 'certificates_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static final Uri _developerUrl = Uri.parse('https://scrptaty.com');

  Future<void> _openDeveloperSite(BuildContext context) async {
    final opened = await launchUrl(
      _developerUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تعذر فتح موقع المطور', 'Could not open developer website'))),
      );
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
              Text(
                tr('الإعدادات', 'Settings'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 20),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('اللغة', 'Language'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ar', label: Text('العربية')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {store.languageCode},
                      onSelectionChanged: (v) => store.setLanguage(v.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      CupertinoIcons.checkmark_shield_fill,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    tr('الشهادات', 'Certificates'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    tr(
                      'إدارة شهادات P12 وملفات provisioning',
                      'Manage P12 and provisioning identities',
                    ),
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(builder: (_) => const _CertificatesPage()),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  children: [
                    _row(
                      CupertinoIcons.shield,
                      tr('التوقيع المحلي', 'Local Signing'),
                      tr(
                        'تتم معالجة P12 وملف mobileprovision على الجهاز',
                        'P12 + mobileprovision are processed on-device',
                      ),
                    ),
                    const Divider(height: 26),
                    _row(
                      CupertinoIcons.folder,
                      tr('الملفات الموقعة', 'Signed Output'),
                      tr(
                        'تصدير ملفات IPA الموقعة من قسم الملفات',
                        'Export signed IPA files from the Files tab',
                      ),
                    ),
                    const Divider(height: 26),
                    _row(
                      CupertinoIcons.lock,
                      tr('الخصوصية', 'Privacy'),
                      tr(
                        'تبقى الشهادات داخل مساحة التطبيق',
                        'Certificates stay inside the app sandbox',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _developerCard(context),
            ],
          );
        },
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
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .28),
                    ),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/avatar.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('محمد السراي', 'Mohammed Al-Saray'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          'مبرمج ومطور تطبيقات ومواقع ويب، مهتم ببناء تجارب رقمية عملية وسلسة.',
                          'Software, app and web developer focused on practical and smooth digital experiences.',
                        ),
                        style: TextStyle(
                          color: muted,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.arrow_up_left_square,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData i, String t, String s) => Row(
        children: [
          Icon(i),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(s, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
        ],
      );
}

class _CertificatesPage extends StatelessWidget {
  const _CertificatesPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(tr('الشهادات', 'Certificates')),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: const CertificatesScreen(),
      );
}
