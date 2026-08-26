import 'dart:io';
import 'dart:math';
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

class SignScreen extends StatefulWidget {
  final ImportedFile? preparedFile;
  const SignScreen({super.key, this.preparedFile});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  final store = AppStore.instance;
  final importer = FileImportService();
  final signing = SigningService();
  final _random = Random.secure();

  String? ipaPath;
  String? identityId;
  String? iconPath;
  String? replacementIconPath;
  bool busy = false;
  bool removeDevices = false;
  bool multipleCopies = false;
  double progress = 0;
  String? _copySuffix;
  String? _bundleBeforeCopies;
  String? _loadedPreparedPath;

  final bundle = TextEditingController();
  final name = TextEditingController();
  final version = TextEditingController();
  final buildCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [bundle, name, version, buildCtrl]) {
      c.addListener(_persistDraft);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.preparedFile != null) {
        await _loadImportedFile(widget.preparedFile!);
      } else {
        await _restoreDraft();
      }
    });
  }

  Future<void> _restoreDraft() async {
    final draft = store.signDraft;
    if (draft == null || !mounted) return;
    final path = (draft['ipaPath'] ?? '').toString();
    if (path.isEmpty || !File(path).existsSync()) return;
    setState(() {
      ipaPath = path;
      identityId = (draft['identityId'] ?? '').toString().isEmpty ? null : draft['identityId'].toString();
      iconPath = (draft['iconPath'] ?? '').toString().isEmpty ? null : draft['iconPath'].toString();
      replacementIconPath = (draft['replacementIconPath'] ?? '').toString().isEmpty ? null : draft['replacementIconPath'].toString();
      bundle.text = (draft['bundle'] ?? '').toString();
      name.text = (draft['name'] ?? '').toString();
      version.text = (draft['version'] ?? '').toString();
      buildCtrl.text = (draft['build'] ?? '').toString();
      removeDevices = draft['removeDevices'] == true;
      multipleCopies = draft['multipleCopies'] == true;
      _copySuffix = draft['copySuffix']?.toString();
      _bundleBeforeCopies = draft['bundleBeforeCopies']?.toString();
      _loadedPreparedPath = path;
    });
  }

  void _persistDraft() {
    final path = ipaPath;
    if (path == null || path.isEmpty) return;
    store.saveSignDraft({
      'ipaPath': path,
      'identityId': identityId,
      'iconPath': iconPath,
      'replacementIconPath': replacementIconPath,
      'bundle': bundle.text,
      'name': name.text,
      'version': version.text,
      'build': buildCtrl.text,
      'removeDevices': removeDevices,
      'multipleCopies': multipleCopies,
      'copySuffix': _copySuffix,
      'bundleBeforeCopies': _bundleBeforeCopies,
    });
  }

  @override
  void didUpdateWidget(covariant SignScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.preparedFile;
    if (next != null && next.path != _loadedPreparedPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadImportedFile(next));
    }
  }

  @override
  void dispose() {
    for (final c in [bundle, name, version, buildCtrl]) {
      c.removeListener(_persistDraft);
    }
    bundle.dispose();
    name.dispose();
    version.dispose();
    buildCtrl.dispose();
    super.dispose();
  }

  SigningIdentity? get selectedIdentity {
    if (store.identities.isEmpty) return null;
    identityId ??= store.identities.first.id;
    for (final item in store.identities) {
      if (item.id == identityId) return item;
    }
    identityId = store.identities.first.id;
    return store.identities.first;
  }

  void _resetCopies() {
    multipleCopies = false;
    _copySuffix = null;
    _bundleBeforeCopies = null;
  }

  Future<void> _loadImportedFile(ImportedFile file) async {
    if (!mounted) return;
    _loadedPreparedPath = file.path;
    setState(() {
      _resetCopies();
      ipaPath = file.path;
      replacementIconPath = null;
      iconPath = file.iconPath;
      bundle.text = file.bundleId ?? '';
      name.text = file.name;
      version.text = file.version ?? '';
      buildCtrl.clear();
    });

    try {
      final info = await signing.inspectIpa(file.path);
      if (!mounted || ipaPath != file.path) return;
      final appName = (info['displayName'] ?? '').toString().trim();
      setState(() {
        bundle.text = (info['bundleId'] ?? file.bundleId ?? '').toString();
        name.text = appName.isEmpty ? file.name : appName;
        version.text = (info['version'] ?? file.version ?? '').toString();
        buildCtrl.text = (info['build'] ?? '').toString();
        iconPath = (info['iconPath'] ?? file.iconPath ?? '').toString();
      });
    } catch (_) {
      // Keep the metadata already stored with the imported file.
    }
    _persistDraft();
  }

  Future<void> _chooseIpa() async {
    final v = await importer.pickFiles(extensions: ['ipa']);
    if (v.isEmpty) return;
    final f = v.first;
    setState(() {
      _resetCopies();
      ipaPath = f.path;
      replacementIconPath = null;
      iconPath = f.iconPath;
    });
    try {
      final info = await signing.inspectIpa(f.path);
      if (!mounted) return;
      final appName = (info['displayName'] ?? '').toString().trim();
      final updated = f.copyWith(
        name: appName.isEmpty ? f.name : appName,
        bundleId: (info['bundleId'] ?? '').toString(),
        version: (info['version'] ?? '').toString(),
        iconPath: (info['iconPath'] ?? '').toString(),
      );
      await store.addFiles([updated]);
      setState(() {
        bundle.text = (info['bundleId'] ?? '').toString();
        name.text = appName;
        version.text = (info['version'] ?? '').toString();
        buildCtrl.text = (info['build'] ?? '').toString();
        iconPath = (info['iconPath'] ?? '').toString();
      });
    } catch (_) {
      await store.addFiles([f]);
    }
    _persistDraft();
  }

  Future<void> _chooseReplacementIcon() async {
    final items = await importer.pickFiles(extensions: ['png', 'jpg', 'jpeg']);
    if (items.isEmpty) return;
    setState(() => replacementIconPath = items.first.path);
    _persistDraft();
  }

  Future<void> _chooseIdentity() async {
    if (store.identities.length <= 1) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassCard(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('اختيار شهادة', 'Choose certificate'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ...store.identities.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    e.id == selectedIdentity?.id ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(e.name),
                  subtitle: Text(p.basename(e.p12Path), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(ctx, e.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) { setState(() => identityId = chosen); _persistDraft(); }
  }

  String _makeRandomSuffix([int length = 7]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  void _toggleMultipleCopies(bool value) {
    if (value) {
      final current = bundle.text.trim();
      if (current.isEmpty) {
        showAppNotice(
          context,
          tr('يجب أن يكون للتطبيق Bundle ID أولاً.', 'The app needs a Bundle ID first.'),
          type: AppNoticeType.warning,
        );
        return;
      }
      final suffix = _makeRandomSuffix();
      _bundleBeforeCopies = current;
      _copySuffix = suffix;
      setState(() {
        multipleCopies = true;
        bundle.text = '$current.$suffix';
      });
    } else {
      final original = _bundleBeforeCopies;
      setState(() {
        multipleCopies = false;
        if (original != null) bundle.text = original;
        _copySuffix = null;
        _bundleBeforeCopies = null;
      });
    }
    _persistDraft();
  }

  Future<void> _sign() async {
    final id = selectedIdentity;
    if (ipaPath == null || id == null) {
      showAppNotice(
        context,
        tr('اختر تطبيق IPA وأضف شهادة توقيع أولاً.', 'Choose an IPA and add a signing identity first.'),
        type: AppNoticeType.warning,
      );
      return;
    }
    setState(() {
      busy = true;
      progress = .18;
    });
    try {
      final storedPassword = await signing.loadPassword(id.id);
      final out = await signing.sign(
        ipaPath: ipaPath!,
        p12Path: id.p12Path,
        p12Password: storedPassword,
        provisionPath: id.provisionPath,
        options: SignOptions(
          bundleId: bundle.text.trim(),
          displayName: name.text.trim(),
          version: version.text.trim(),
          build: buildCtrl.text.trim(),
          removeSupportedDevices: removeDevices,
          iconPath: replacementIconPath ?? '',
        ),
      );
      setState(() => progress = .90);
      final info = await signing.inspectIpa(out);
      final file = File(out);
      final appName = (info['displayName'] ?? name.text).toString().trim();
      final model = ImportedFile(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: appName.isEmpty ? p.basenameWithoutExtension(out) : appName,
        path: out,
        kind: 'Signed IPA',
        size: await file.length(),
        importedAt: DateTime.now(),
        bundleId: (info['bundleId'] ?? '').toString(),
        version: (info['version'] ?? '').toString(),
        iconPath: (info['iconPath'] ?? iconPath ?? '').toString(),
      );
      await store.addSignedOutput(model);
      if (!mounted) return;
      setState(() => progress = 1);
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: GlassCard(
              radius: 30,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(CupertinoIcons.checkmark_shield_fill, color: Theme.of(context).colorScheme.primary, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('تم التوقيع بنجاح', 'Signed successfully'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                          const SizedBox(height: 3),
                          Text(appName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
                        ]),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(CupertinoIcons.xmark_circle_fill)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final ok = await signing.install(out);
                      if (mounted && !ok) {
                        showAppNotice(context, tr('تعذر فتح مثبت iOS.', 'iOS did not open the installer.'), type: AppNoticeType.error);
                      }
                    },
                    icon: const Icon(CupertinoIcons.arrow_down_circle),
                    label: Text(tr('تثبيت', 'Install')),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () async { Navigator.pop(ctx); await signing.share(out); },
                    icon: const Icon(CupertinoIcons.share),
                    label: Text(tr('مشاركة', 'Share')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        String message;
        if (raw.contains('P12 certificate file is missing')) {
          message = tr('ملف شهادة P12 غير موجود. أعد إضافة الشهادة من قسم الشهادات.', 'The P12 certificate file is missing. Re-add the certificate from Certificates.');
        } else if (raw.contains('Provisioning profile file is missing')) {
          message = tr('ملف mobileprovision غير موجود. أعد إضافة الشهادة مع ملف provisioning.', 'The mobileprovision file is missing. Re-add the signing identity with its provisioning profile.');
        } else if (raw.contains('IPA file is missing')) {
          message = tr('ملف التطبيق IPA غير موجود. أعد تنزيله أو استيراده.', 'The IPA file is missing. Download or import it again.');
        } else {
          message = '${tr('فشل التوقيع', 'Signing failed')}: $raw';
        }
        showAppNotice(context, message, type: AppNoticeType.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = 0;
        });
      }
    }
  }

  Widget _signButton(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: busy ? null : _sign,
        icon: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(CupertinoIcons.signature),
        label: Text(
          busy ? tr('جاري التوقيع…', 'Signing…') : tr('بدء التوقيع', 'Start Signing'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final identity = selectedIdentity;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              Text(tr('توقيع تطبيق', 'Sign App'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 6),
              Text(
                tr('اختر التطبيق ثم وقّعه بشهادتك', 'IPA → certificate → signed IPA'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55)),
              ),
              const SizedBox(height: 20),
              GlassCard(
                child: Column(
                  children: [
                    if (ipaPath != null) ...[
                      _applicationHeader(context),
                      const Divider(height: 28),
                    ],
                    _picker(
                      CupertinoIcons.app_badge,
                      tr('التطبيق', 'Application'),
                      ipaPath == null
                          ? tr('اختر ملف IPA', 'Select an IPA')
                          : name.text.isEmpty
                              ? p.basename(ipaPath!)
                              : name.text,
                      _chooseIpa,
                    ),
                    const Divider(height: 28),
                    if (identity == null)
                      Row(
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(tr('لا توجد شهادة. أضف شهادة من قسم الشهادات أولاً.', 'No certificate found. Add one from Certificates first.')),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(CupertinoIcons.checkmark_shield_fill, color: Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('الشهادة المختارة', 'Selected certificate'),
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5)),
                                ),
                                Text(identity.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (store.identities.length > 1)
                            TextButton(onPressed: _chooseIdentity, child: Text(tr('تغيير', 'Change'))),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (ipaPath != null) ...[
                if (busy) ...[
                  LinearProgressIndicator(value: progress == 0 ? null : progress),
                  const SizedBox(height: 12),
                ],
                _signButton(context),
                const SizedBox(height: 10),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: multipleCopies,
                    onChanged: busy ? null : _toggleMultipleCopies,
                    secondary: Icon(CupertinoIcons.square_on_square, color: Theme.of(context).colorScheme.primary),
                    title: Text(tr('نسخ متعددة', 'Multiple copies'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      multipleCopies && _copySuffix != null
                          ? tr('تمت إضافة .$_copySuffix إلى Bundle ID لإنشاء نسخة مستقلة', 'Added .$_copySuffix to the Bundle ID for a separate copy')
                          : tr('يضيف حروفاً وأرقاماً عشوائية إلى Bundle ID', 'Adds random letters and numbers to the Bundle ID'),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr('أيقونة التطبيق', 'App Icon'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _iconPreview(context, iconPath, tr('الأيقونة السابقة', 'Original icon'))),
                          const SizedBox(width: 12),
                          Expanded(child: _iconPreview(context, replacementIconPath, tr('الأيقونة الجديدة', 'New icon'), isReplacement: true)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _chooseReplacementIcon,
                        icon: const Icon(CupertinoIcons.photo),
                        label: Text(replacementIconPath == null ? tr('تغيير أيقونة التطبيق', 'Change App Icon') : tr('اختيار أيقونة أخرى', 'Choose Another Icon')),
                      ),
                      if (replacementIconPath != null)
                        TextButton(
                          onPressed: () { setState(() => replacementIconPath = null); _persistDraft(); },
                          child: Text(tr('استخدام الأيقونة السابقة', 'Use Original Icon')),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (ipaPath != null)
                GlassCard(
                  child: Column(
                    children: [
                      TextField(
                        controller: bundle,
                      decoration: InputDecoration(
                        labelText: tr('معرّف الحزمة Bundle ID', 'Bundle Identifier'),
                        hintText: tr('اتركه كما هو إن لم ترد تغييره', 'Leave unchanged if blank'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: tr('اسم التطبيق', 'Display Name'),
                        hintText: tr('اسم التطبيق بعد التوقيع', 'App name after signing'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: version, decoration: InputDecoration(labelText: tr('الإصدار', 'Version')))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: buildCtrl, decoration: InputDecoration(labelText: tr('البناء', 'Build')))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: removeDevices,
                      onChanged: (v) { setState(() => removeDevices = v); _persistDraft(); },
                      title: Text(tr('إزالة قيود UIDeviceFamily', 'Remove UIDeviceFamily restrictions')),
                      subtitle: Text(tr('خيار توافق إضافي', 'Optional compatibility tweak')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          );
        },
      );

  Widget _iconPreview(BuildContext context, String? path, String label, {bool isReplacement = false}) => Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(
                color: isReplacement && path != null ? Theme.of(context).colorScheme.primary : Colors.white.withValues(alpha: .08),
                width: isReplacement && path != null ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(7),
            child: path != null && path.isNotEmpty && File(path).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _iconFallback(context)),
                  )
                : _iconFallback(context),
          ),
          const SizedBox(height: 7),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58))),
        ],
      );

  Widget _applicationHeader(BuildContext context) {
    final path = iconPath;
    return Row(
      children: [
        if (path != null && path.isNotEmpty && File(path).existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Image.file(File(path), width: 68, height: 68, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _iconFallback(context)),
          )
        else
          _iconFallback(context),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.text.isEmpty ? tr('تطبيق', 'Application') : name.text,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(bundle.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
              if (version.text.isNotEmpty)
                Text(
                  '${tr('الإصدار', 'Version')} ${version.text} (${buildCtrl.text})',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .42)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _iconFallback(BuildContext context) => Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Icon(CupertinoIcons.app_badge, size: 32, color: Theme.of(context).colorScheme.primary),
      );

  Widget _picker(IconData icon, String title, String subtitle, VoidCallback action) => Row(
        children: [
          Icon(icon),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48), fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton.tonal(onPressed: action, child: Text(tr('اختيار', 'Choose'))),
        ],
      );
}
