import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/file_import_service.dart';
import '../services/signing_service.dart';
import '../services/localized.dart';
import '../widgets/app_notice.dart';
import '../widgets/glass_card.dart';
import '../widgets/native_material_controls.dart';
import '../widgets/native_ios_controls.dart';

class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});
  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  final store = AppStore.instance;
  final importer = FileImportService();
  final signing = SigningService();
  late Future<Map<String, dynamic>> _automaticState;

  @override
  void initState() {
    super.initState();
    _automaticState = signing.automaticSigningState();
  }

  DateTime? _profileExpiry(String path) {
    try {
      final text = latin1.decode(File(path).readAsBytesSync(), allowInvalid: true);
      final match = RegExp(r'<key>ExpirationDate</key>\s*<date>([^<]+)</date>', multiLine: true).firstMatch(text);
      return match == null ? null : DateTime.tryParse(match.group(1)!.trim())?.toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _add() async {
    String? p12, prov;
    final pass = TextEditingController();
    final name = TextEditingController();
    bool busy = false;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: GlassCard(
            radius: 30,
            padding: const EdgeInsets.all(20),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('إضافة شهادة توقيع', 'Add Signing Identity'), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 15),
                  NativeIOSTextField(controller: name, placeholder: tr('اسم الشهادة', 'Name')),
                  const SizedBox(height: 10),
                  NativeIOSButton(
                    title: p12 == null ? tr('اختيار ملف P12', 'Choose P12') : p.basename(p12!),
                    systemImage: 'lock.shield',
                    onPressed: () async { final x = await importer.pickAndPersistOne('p12'); if (x != null) setLocal(() => p12 = x); },
                  ),
                  const SizedBox(height: 8),
                  NativeIOSTextField(controller: pass, obscureText: true, placeholder: tr('كلمة مرور P12', 'P12 Password')),
                  const SizedBox(height: 8),
                  NativeIOSButton(
                    title: prov == null ? tr('اختيار mobileprovision', 'Choose mobileprovision') : p.basename(prov!),
                    systemImage: 'doc.text',
                    onPressed: () async { final x = await importer.pickAndPersistOne('mobileprovision'); if (x != null) setLocal(() => prov = x); },
                  ),
                  const SizedBox(height: 14),
                  NativeIOSButton(
                    title: busy ? tr('جاري الحفظ…', 'Saving…') : tr('حفظ الشهادة', 'Save Identity'),
                    systemImage: 'checkmark.shield',
                    prominent: true,
                    onPressed: busy ? null : () async {
                      if (p12 == null || prov == null) return;
                      setLocal(() => busy = true);
                      try {
                        final info = await signing.inspectIdentity(p12Path: p12!, password: pass.text, provisionPath: prov!);
                        final id = DateTime.now().microsecondsSinceEpoch.toString();
                        await signing.savePassword(id, pass.text);
                        final common = (info['commonName'] ?? '').toString();
                        final expiry = _profileExpiry(prov!);
                        await store.addIdentity(SigningIdentity(
                          id: id,
                          name: name.text.trim().isEmpty ? (common.isEmpty ? tr('شهادة توقيع', 'Signing Identity') : common) : name.text.trim(),
                          p12Path: p12!,
                          provisionPath: prov!,
                          createdAt: DateTime.now(),
                          expiresAt: expiry,
                        ));
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setLocal(() => busy = false);
                        if (ctx.mounted) showAppNotice(ctx, '${tr('فشل التحقق من الشهادة', 'Certificate validation failed')}: $e', type: AppNoticeType.error);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _date(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Future<void> _deleteIdentity(SigningIdentity id) async {
    final confirmed = await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(tr('حذف الشهادة؟', 'Delete certificate?')),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${tr('هل تريد حذف', 'Delete')} «${id.name}» ${tr('نهائياً؟', 'permanently?')}'),
            ),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: Text(tr('إلغاء', 'Cancel'))),
              CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(tr('حذف', 'Delete'))),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await signing.deletePassword(id.id);
    await store.removeIdentity(id.id);
  }


  DateTime? _automaticExpiry(Map<String, dynamic> state) {
    final raw = (state['expiresAt'] ?? '').toString();
    return raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
  }

  Widget _automaticCard(BuildContext context, Map<String, dynamic> state) {
    final expiry = _automaticExpiry(state);
    final valid = state['ready'] == true && (expiry == null || expiry.isAfter(DateTime.now()));
    final statusColor = valid ? Colors.green : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
            child: Icon(valid ? CupertinoIcons.checkmark_shield_fill : CupertinoIcons.xmark_shield_fill, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Booma', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                  child: Text(valid ? tr('صالحة', 'Valid') : tr('غير متاحة', 'Unavailable'), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    expiry == null ? tr('جاهزة للاستخدام', 'Ready to use') : '${tr('تنتهي', 'Expires')} ${_date(expiry)}',
                    style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5)),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 44),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => FutureBuilder<Map<String, dynamic>>(
          future: _automaticState,
          builder: (context, snapshot) {
            final runtime = snapshot.data ?? const <String, dynamic>{};
            final hasAutomatic = runtime['ready'] == true;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
              children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('الشهادات', 'Certificates'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    const SizedBox(height: 5),
                    Text(tr('P12 + ملفات provisioning', 'P12 + provisioning identities'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
                  ])),
                  NativeIOSButton(title: '', systemImage: 'plus', onPressed: _add, width: 44, height: 44),
                ]),
                const SizedBox(height: 22),
                if (hasAutomatic) _automaticCard(context, runtime),
                if (!hasAutomatic && store.identities.isEmpty)
                  GlassCard(child: Column(children: [
                    const Icon(CupertinoIcons.lock_shield, size: 42),
                    const SizedBox(height: 10),
                    Text(tr('لا توجد شهادات', 'No signing identities'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(tr('أضف شهادة P12 مع ملف mobileprovision الخاص بها.', 'Add a P12 certificate and its mobileprovision profile.'), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
                    const SizedBox(height: 14),
                    NativeIOSButton(title: tr('إضافة شهادة', 'Add Certificate'), systemImage: 'plus', onPressed: _add, prominent: true, width: 170),
                  ])),
                ...store.identities.map((id) {
                  final expiry = id.expiresAt ?? _profileExpiry(id.provisionPath);
                  final valid = expiry == null ? true : expiry.isAfter(DateTime.now());
                  final statusColor = valid ? Colors.green : Theme.of(context).colorScheme.error;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: statusColor.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
                          child: Icon(valid ? CupertinoIcons.checkmark_shield_fill : CupertinoIcons.xmark_shield_fill, color: statusColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(id.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: statusColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                              child: Text(valid ? tr('صالحة', 'Valid') : tr('منتهية', 'Expired'), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 7),
                            Expanded(child: Text(expiry == null ? tr('تاريخ الانتهاء غير متاح', 'Expiry date unavailable') : '${tr('تنتهي', 'Expires')} ${_date(expiry)}', style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5)))),
                          ]),
                          const SizedBox(height: 3),
                          Text('${p.basename(id.p12Path)} • ${p.basename(id.provisionPath)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .38))),
                        ])),
                        NativeCompatIconButton(onPressed: () => _deleteIdentity(id), icon: const Icon(CupertinoIcons.trash, size: 19)),
                      ]),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );
}
