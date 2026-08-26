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
import '../widgets/glass_card.dart';

class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});
  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  final store = AppStore.instance;
  final importer = FileImportService();
  final signing = SigningService();

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
                  TextField(controller: name, decoration: InputDecoration(labelText: tr('اسم الشهادة', 'Name'), hintText: tr('شهادة المطور', 'My Developer Certificate'))),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () async { final x = await importer.pickAndPersistOne('p12'); if (x != null) setLocal(() => p12 = x); },
                    icon: const Icon(CupertinoIcons.lock_shield),
                    label: Text(p12 == null ? tr('اختيار ملف P12', 'Choose P12') : p.basename(p12!)),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: tr('كلمة مرور P12', 'P12 Password'))),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () async { final x = await importer.pickAndPersistOne('mobileprovision'); if (x != null) setLocal(() => prov = x); },
                    icon: const Icon(CupertinoIcons.doc_text),
                    label: Text(prov == null ? tr('اختيار mobileprovision', 'Choose mobileprovision') : p.basename(prov!)),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
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
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${tr('فشل التحقق من الشهادة', 'Certificate validation failed')}: $e')));
                      }
                    },
                    child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('حفظ الشهادة', 'Save Identity')),
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


  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
          children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('الشهادات', 'Certificates'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                const SizedBox(height: 5),
                Text(tr('P12 + ملفات provisioning', 'P12 + provisioning identities'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
              ])),
              IconButton.filledTonal(onPressed: _add, icon: const Icon(CupertinoIcons.add)),
            ]),
            const SizedBox(height: 22),
            if (store.identities.isEmpty)
              GlassCard(child: Column(children: [
                const Icon(CupertinoIcons.lock_shield, size: 42),
                const SizedBox(height: 10),
                Text(tr('لا توجد شهادات', 'No signing identities'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(tr('أضف شهادة P12 مع ملف mobileprovision الخاص بها.', 'Add a P12 certificate and its mobileprovision profile.'), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
                const SizedBox(height: 14),
                FilledButton(onPressed: _add, child: Text(tr('إضافة شهادة', 'Add Certificate'))),
              ]))
            else
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
                      IconButton(onPressed: () => _deleteIdentity(id), icon: const Icon(CupertinoIcons.trash, size: 19)),
                    ]),
                  ),
                );
              }),
          ],
        ),
      );
}
