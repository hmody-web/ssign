import 'dart:io';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/file_import_service.dart';
import '../services/signing_service.dart';
import '../services/localized.dart';
import '../widgets/app_notice.dart';
import '../widgets/glass_card.dart';
import 'signed_files_screen.dart';

class SignScreen extends StatefulWidget {
  final ImportedFile? preparedFile;
  final Key? topKey;
  final VoidCallback? onSelectionCleared;
  const SignScreen({super.key, this.preparedFile, this.topKey, this.onSelectionCleared});

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
  bool installAfterSigning = false;
  double progress = 0;
  String? _copySuffix;
  String? _bundleBeforeCopies;
  String? _loadedPreparedPath;
  String? _ignoredPreparedPath;
  bool _automaticReady = false;

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
      await _refreshAutomaticState();
      if (widget.preparedFile != null) {
        await _loadImportedFile(widget.preparedFile!);
      } else {
        await _restoreDraft();
      }
    });
  }

  Future<void> _refreshAutomaticState() async {
    final state = await signing.automaticSigningState();
    if (!mounted) return;
    setState(() => _automaticReady = state['ready'] == true);
  }

  bool get _usingAutomatic => _automaticReady && identityId == null;

  Future<void> _restoreDraft() async {
    final draft = store.signDraft;
    if (draft == null || !mounted) return;
    final path = (draft['ipaPath'] ?? '').toString();
    if (path.isEmpty || (!File(path).existsSync() && !Directory(path).existsSync())) return;
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
      installAfterSigning = draft['installAfterSigning'] == true;
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
      'installAfterSigning': installAfterSigning,
      'copySuffix': _copySuffix,
      'bundleBeforeCopies': _bundleBeforeCopies,
    });
  }

  @override
  void didUpdateWidget(covariant SignScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.preparedFile;
    if (next != null &&
        next.path != _loadedPreparedPath &&
        next.path != _ignoredPreparedPath) {
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
    if (_automaticReady && identityId == null) return null;
    if (store.identities.isEmpty) {
      if (_automaticReady) identityId = null;
      return null;
    }
    if (identityId != null) {
      for (final item in store.identities) {
        if (item.id == identityId) return item;
      }
      identityId = null;
      if (_automaticReady) return null;
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
    _ignoredPreparedPath = null;
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


  Future<void> _clearSelectedApp() async {
    final selectedPath = ipaPath;
    // If this file was supplied by another tab, remember that the user explicitly
    // dismissed it. Otherwise a parent rebuild can feed the same preparedFile back
    // into this screen immediately, which caused the old "flash then reappears" bug.
    if (selectedPath != null && widget.preparedFile?.path == selectedPath) {
      _ignoredPreparedPath = selectedPath;
    }
    setState(() {
      ipaPath = null;
      iconPath = null;
      replacementIconPath = null;
      _loadedPreparedPath = null;
      _resetCopies();
      bundle.clear();
      name.clear();
      version.clear();
      buildCtrl.clear();
    });
    widget.onSelectionCleared?.call();
    await store.clearSignDraft();
  }

  Future<void> _chooseIpa() async {
    final v = await importer.pickFiles();
    if (v.isEmpty) return;
    final appFiles = v.where((e) {
      final lower = e.path.toLowerCase();
      return lower.endsWith('.ipa') || lower.endsWith('.app') || e.kind == 'APP';
    }).toList();
    if (appFiles.isEmpty) {
      if (mounted) showAppNotice(context, tr('اختر ملف IPA أو APP للتوقيع.', 'Choose an IPA or APP file to sign.'), type: AppNoticeType.error);
      return;
    }
    final f = appFiles.first;
    _ignoredPreparedPath = null;
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
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'ReplacementIcons'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
    final dest = p.join(dir.path, 'icon_${DateTime.now().microsecondsSinceEpoch}$ext');
    await File(picked.path).copy(dest);
    if (!mounted) return;
    setState(() => replacementIconPath = dest);
    _persistDraft();
  }

  Future<void> _chooseIdentity() async {
    final optionCount = store.identities.length + (_automaticReady ? 1 : 0);
    if (optionCount <= 1) return;
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
              Text(tr('طريقة التوقيع', 'Signing Method'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (_automaticReady)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _usingAutomatic ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(tr('تلقائي', 'Automatic')),
                  subtitle: Text(tr('جاهز للاستخدام مباشرة', 'Ready to use')),
                  onTap: () => Navigator.pop(ctx, '__automatic__'),
                ),
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
    if (chosen != null) {
      setState(() => identityId = chosen == '__automatic__' ? null : chosen);
      _persistDraft();
    }
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

  Future<void> _showSignedActions(ImportedFile model, {bool watchExistingInstall = false}) async {
    if (!mounted) return;

    BuildContext? sheetContext;
    var sheetOpen = true;
    var watchingInstall = false;

    Future<void> watchForInstallStart() async {
      if (watchingInstall) return;
      watchingInstall = true;
      while (sheetOpen && mounted) {
        final started = await signing.installDownloadStarted();
        if (started) {
          final ctx = sheetContext;
          if (sheetOpen && ctx != null && ctx.mounted) {
            Navigator.of(ctx).pop();
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      watchingInstall = false;
    }

    final sheetFuture = showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        sheetContext = ctx;
        if (watchExistingInstall) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            watchForInstallStart();
          });
        }
        return PopScope(
          canPop: false,
          child: SafeArea(
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: model.iconPath != null && model.iconPath!.isNotEmpty && File(model.iconPath!).existsSync()
                              ? Image.file(File(model.iconPath!), width: 54, height: 54, fit: BoxFit.cover)
                              : Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: Theme.of(ctx).colorScheme.primary.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(CupertinoIcons.app_badge, color: Theme.of(ctx).colorScheme.primary),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(tr('تم التوقيع بنجاح', 'Signed successfully'), style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: .5), fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await signing.install(model.path);
                        if (ok) {
                          watchForInstallStart();
                        } else if (mounted) {
                          showAppNotice(context, tr('تعذر فتح مثبت iOS.', 'iOS did not open the installer.'), type: AppNoticeType.error);
                        }
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(CupertinoIcons.arrow_down_circle_fill),
                      label: Text(tr('تثبيت', 'Install'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(76, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(tr('لاحقاً', 'Later'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    await sheetFuture;
    sheetOpen = false;
  }

  Future<void> _sign() async {
    final automatic = _usingAutomatic;
    final id = selectedIdentity;
    if (ipaPath == null || (!automatic && id == null)) {
      showAppNotice(
        context,
        ipaPath == null
            ? tr('اختر تطبيق IPA أولاً.', 'Choose an IPA first.')
            : tr('بيانات التوقيع غير متاحة حالياً.', 'Signing data is not available right now.'),
        type: AppNoticeType.warning,
      );
      return;
    }
    setState(() {
      busy = true;
      progress = .18;
    });
    try {
      final options = SignOptions(
        bundleId: bundle.text.trim(),
        displayName: name.text.trim(),
        version: version.text.trim(),
        build: buildCtrl.text.trim(),
        removeSupportedDevices: removeDevices,
        iconPath: replacementIconPath ?? '',
      );
      final out = automatic
          ? await signing.signAutomatic(ipaPath: ipaPath!, options: options)
          : await signing.sign(
              ipaPath: ipaPath!,
              p12Path: id!.p12Path,
              p12Password: await signing.loadPassword(id.id),
              provisionPath: id.provisionPath,
              options: options,
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
      showAppNotice(
        context,
        '${tr('تم توقيع', 'Signed')} $appName',
        type: AppNoticeType.success,
        imagePath: model.iconPath,
        duration: const Duration(seconds: 4),
        onTap: () {
          Navigator.of(context).push(CupertinoPageRoute(
            builder: (_) => SignedFilesScreen(
              highlightFileId: model.id,
              onSignRequested: (file) {
                Navigator.of(context).pop();
                _loadImportedFile(file);
              },
            ),
          ));
        },
      );
      var autoInstallOpened = false;
      if (installAfterSigning) {
        autoInstallOpened = await signing.install(model.path);
        if (!autoInstallOpened && mounted) {
          showAppNotice(context, tr('تعذر فتح مثبت iOS.', 'iOS did not open the installer.'), type: AppNoticeType.error);
        }
      }
      await _showSignedActions(model, watchExistingInstall: autoInstallOpened);
      if (mounted) {
        await _clearSelectedApp();
      }
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        String message;
        if (raw.contains('Automatic signing data is unavailable') || raw.contains('Runtime configuration')) {
          message = tr('تعذر تجهيز التوقيع المحلي حالياً.', 'Local signing could not be prepared right now.');
        } else if (raw.contains('Automatic signing configuration does not permit this app identifier')) {
          message = tr('إعداد التوقيع الحالي لا يدعم معرّف هذا التطبيق.', 'The current signing setup does not support this app identifier.');
        } else if (raw.contains('P12 certificate file is missing')) {
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
              Text(tr('توقيع تطبيق', 'Sign App'), key: widget.topKey, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 6),
              Text(
                tr('اختر التطبيق ثم ابدأ التوقيع', 'Choose an IPA and start signing'),
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
                      CupertinoIcons.doc_fill,
                      tr('التطبيق', 'Application'),
                      ipaPath == null
                          ? tr('اختر ملف IPA', 'Select an IPA')
                          : name.text.isEmpty
                              ? p.basename(ipaPath!)
                              : name.text,
                      _chooseIpa,
                      selected: ipaPath != null,
                      onClear: ipaPath != null && !busy ? _clearSelectedApp : null,
                    ),
                    const Divider(height: 28),
                    if (_usingAutomatic)
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
                                Text(tr('جاهز للتوقيع', 'Ready to sign'), style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(tr('يتم تجهيز المتطلبات تلقائياً', 'Requirements are prepared automatically'), style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
                              ],
                            ),
                          ),
                          if (store.identities.isNotEmpty)
                            TextButton(onPressed: _chooseIdentity, child: Text(tr('خيارات', 'Options'))),
                        ],
                      )
                    else if (identity == null)
                      Row(
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle),
                          const SizedBox(width: 12),
                          Expanded(child: Text(tr('بيانات التوقيع غير متاحة حالياً.', 'Signing data is not available right now.'))),
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
                                Text(tr('الشهادة المختارة', 'Selected certificate'), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
                                Text(identity.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (store.identities.length + (_automaticReady ? 1 : 0) > 1)
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
                const SizedBox(height: 10),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: installAfterSigning,
                    onChanged: busy ? null : (value) {
                      setState(() => installAfterSigning = value);
                      _persistDraft();
                    },
                    secondary: Icon(CupertinoIcons.arrow_down_circle_fill, color: Theme.of(context).colorScheme.primary),
                    title: Text(tr('تثبيت بعد التوقيع', 'Install after signing'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(tr('يبدأ تثبيت هذا التطبيق تلقائياً فور اكتمال التوقيع', 'Automatically starts installing this app as soon as signing finishes')),
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
                      title: Text(tr('إزالة قائمة الأجهزة المقيدة', 'Remove restricted-device list')),
                      subtitle: Text(tr('يحافظ على UIDeviceFamily وخصائص العرض لمنع مشاكل أبعاد الشاشة', 'Keeps UIDeviceFamily and display metadata intact to avoid screen-size issues')),
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

  Widget _picker(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action, {
    bool selected = false,
    Future<void> Function()? onClear,
  }) => Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .18)
                  : const Color(0xFFD8C29D).withValues(alpha: .18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFFD8C29D)),
          ),
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
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: selected ? Theme.of(context).colorScheme.primary : const Color(0xFFD8C29D),
              foregroundColor: selected ? Theme.of(context).colorScheme.onPrimary : Colors.black87,
            ),
            onPressed: action,
            icon: Icon(selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.folder_fill, size: 18),
            label: Text(selected ? tr('تم الاختيار', 'Selected') : tr('اختيار', 'Choose')),
          ),
          if (selected && onClear != null) ...[
            const SizedBox(width: 7),
            SizedBox(
              width: 42,
              height: 42,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: .09),
                  foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: .78),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                onPressed: () => onClear(),
                child: const Icon(CupertinoIcons.xmark, size: 18),
              ),
            ),
          ],
        ],
      );
}
