import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/sign_models.dart';
import '../models/remote_app.dart';
import '../services/app_store.dart';
import '../services/app_download_manager.dart';
import '../services/folder_workspace_service.dart';
import '../services/file_import_service.dart';
import '../services/signing_service.dart';
import '../services/localized.dart';
import '../services/persistent_path_service.dart';
import '../widgets/app_notice.dart';
import '../widgets/glass_card.dart';
import '../widgets/native_material_controls.dart';
import 'signed_files_screen.dart';
import 'folders_screen.dart';

class LibraryScreen extends StatefulWidget {
  final ValueChanged<ImportedFile>? onSignRequested;
  final ScrollController? scrollController;
  final Key? topKey;
  const LibraryScreen({super.key, this.onSignRequested, this.scrollController, this.topKey});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final importer = FileImportService();
  final store = AppStore.instance;
  final signer = SigningService();
  final downloads = AppDownloadManager.instance;
  final folders = FolderWorkspaceService.instance;
  bool selecting = false;
  final Set<String> selected = {};

  @override
  void initState() {
    super.initState();
    downloads.addListener(_downloadsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _backfillIpaMetadata());
  }

  void _downloadsChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    downloads.removeListener(_downloadsChanged);
    super.dispose();
  }

  Future<void> _backfillIpaMetadata() async {
    // Repair paths saved by older builds first. This is important on iOS because
    // the application-container prefix can change after an app update.
    final snapshot = List<ImportedFile>.from(store.files);
    for (final f in snapshot) {
      if (!_isSignableApp(f)) continue;

      final repairedIpa = await PersistentPathService.instance.resolveDataFile(f.path);
      final repairedIcon = await PersistentPathService.instance.resolveIcon(
        storedPath: f.iconPath,
        bundleId: f.bundleId,
      );

      var current = f;
      final pathChanged = repairedIpa != null && repairedIpa != f.path;
      final iconChanged = repairedIcon != null && repairedIcon != f.iconPath;
      if (pathChanged || iconChanged) {
        current = f.copyWith(
          path: repairedIpa ?? f.path,
          iconPath: repairedIcon ?? f.iconPath ?? '',
        );
        await store.replaceFile(current);
      }

      // If there is still no icon, re-extract it from the IPA automatically.
      final iconReady = current.iconPath != null &&
          current.iconPath!.isNotEmpty &&
          File(current.iconPath!).existsSync();
      final ipaPath = await PersistentPathService.instance.resolveDataFile(current.path);
      if (iconReady || ipaPath == null || (!File(ipaPath).existsSync() && !Directory(ipaPath).existsSync())) continue;

      try {
        final info = await signer.inspectIpa(ipaPath);
        final appName = (info['displayName'] ?? '').toString().trim();
        final extractedIcon = (info['iconPath'] ?? '').toString().trim();
        final updated = current.copyWith(
          path: ipaPath,
          name: appName.isEmpty ? current.name : appName,
          bundleId: (info['bundleId'] ?? current.bundleId ?? '').toString(),
          version: (info['version'] ?? current.version ?? '').toString(),
          iconPath: extractedIcon.isEmpty ? (current.iconPath ?? '') : extractedIcon,
        );
        await store.replaceFile(updated);
      } catch (_) {}
    }
  }

  void _toggleSelection(ImportedFile file) {
    setState(() {
      selecting = true;
      if (!selected.add(file.id)) selected.remove(file.id);
      if (selected.isEmpty) selecting = false;
    });
  }

  Future<bool> _confirmDelete({String? itemName, int? count}) async {
    final title = count != null && count > 1 ? tr('حذف الملفات؟', 'Delete files?') : tr('تأكيد الحذف', 'Confirm delete');
    final message = count != null && count > 1
        ? '${tr('سيتم حذف', 'This will delete')} $count ${tr('ملفات نهائياً.', 'files permanently.')}'
        : itemName == null
            ? tr('هل تريد حذف هذا العنصر نهائياً؟', 'Delete this item permanently?')
            : '${tr('هل تريد حذف', 'Delete')} «$itemName» ${tr('نهائياً؟', 'permanently?')}';
    return await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(title),
            content: Padding(padding: const EdgeInsets.only(top: 8), child: Text(message)),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: Text(tr('إلغاء', 'Cancel'))),
              CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(tr('حذف', 'Delete'))),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteOne(ImportedFile file) async {
    if (!await _confirmDelete(itemName: file.name)) return;
    try {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(file.path).delete(recursive: true);
      } else {
        await File(file.path).delete();
      }
    } catch (_) {}
    await store.removeFile(file.id);
  }

  Future<void> _deleteSelected() async {
    final targets = store.importedFiles.where((f) => selected.contains(f.id)).toList();
    if (targets.isEmpty || !await _confirmDelete(count: targets.length)) return;
    for (final f in targets) {
      try {
        final type = await FileSystemEntity.type(f.path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await Directory(f.path).delete(recursive: true);
        } else {
          await File(f.path).delete();
        }
      } catch (_) {}
    }
    await store.removeFiles(selected);
    if (mounted) setState(() { selected.clear(); selecting = false; });
  }

  Future<void> _import() async {
    final picked = await importer.pickFiles();
    if (picked.isEmpty) return;
    final enriched = <ImportedFile>[];
    for (final f in picked) {
      if (f.kind == 'IPA' || f.kind == 'APP' || f.path.toLowerCase().endsWith('.app')) {
        try {
          final info = await signer.inspectIpa(f.path);
          final appName = (info['displayName'] ?? '').toString().trim();
          enriched.add(
            f.copyWith(
              name: appName.isEmpty ? f.name : appName,
              bundleId: (info['bundleId'] ?? '').toString(),
              version: (info['version'] ?? '').toString(),
              iconPath: (info['iconPath'] ?? '').toString(),
            ),
          );
        } catch (_) {
          enriched.add(f);
        }
      } else {
        enriched.add(f);
      }
    }
    await store.addFiles(enriched);
  }

  bool _isIpa(ImportedFile file) => file.kind == 'IPA' || file.kind == 'Signed IPA' || file.path.toLowerCase().endsWith('.ipa');
  bool _isAppBundle(ImportedFile file) => file.kind == 'APP' || file.path.toLowerCase().endsWith('.app');
  bool _isSignableApp(ImportedFile file) => _isIpa(file) || _isAppBundle(file);

  Future<void> _extractArchive(ImportedFile file) async {
    final dest = await showFolderDestinationPicker(context, title: tr('استخراج داخل المجلدات', 'Extract inside Folders'));
    if (dest == null) return;
    if (!mounted) return;
    showAppNotice(context, tr('سيتم استخراج الملف داخل كرت المجلدات فقط.', 'The archive will be extracted inside Folders only.'));
    try {
      await folders.extractZip(zipPath: file.path, relative: dest);
      if (mounted) showAppNotice(context, tr('تم استخراج الملف بنجاح.', 'Archive extracted successfully.'));
    } catch (_) {
      if (mounted) showAppNotice(context, tr('تعذر استخراج الملف المضغوط.', 'Could not extract the archive.'), type: AppNoticeType.error);
    }
  }

  Future<void> _copyOrMoveFiles(List<ImportedFile> files, {required bool move}) async {
    if (files.isEmpty) return;
    final dest = await showFolderDestinationPicker(context, title: move ? tr('نقل إلى مجلد', 'Move to folder') : tr('نسخ إلى مجلد', 'Copy to folder'));
    if (dest == null) return;
    for (final f in files) {
      try {
        if (move) {
          await folders.moveInto(sourcePath: f.path, relative: dest, name: p.basename(f.path));
          await store.removeFile(f.id);
        } else {
          await folders.copyInto(sourcePath: f.path, relative: dest, name: p.basename(f.path));
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() { selected.clear(); selecting = false; });
    showAppNotice(context, move ? tr('تم نقل الملفات إلى المجلدات.', 'Files moved to Folders.') : tr('تم نسخ الملفات إلى المجلدات.', 'Files copied to Folders.'));
  }

  Future<void> _showFileActions(ImportedFile file) async {
    final isIpa = _isIpa(file);
    final isAppBundle = _isAppBundle(file);
    final isSignable = isIpa || isAppBundle;
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
                    _appIcon(context, file),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _subtitle(file),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    NativeCompatIconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (isSignable) ...[
                  _actionTile(
                    context,
                    icon: CupertinoIcons.signature,
                    title: tr('توقيع التطبيق', 'Sign application'),
                    subtitle: tr('فتح الملف في صفحة التوقيع مع تعبئة بياناته', 'Open in Sign with app details filled in'),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onSignRequested?.call(file);
                    },
                  ),
                  const SizedBox(height: 10),
                  _actionTile(
                    context,
                    icon: CupertinoIcons.arrow_down_circle,
                    title: tr('تثبيت', 'Install'),
                    subtitle: tr('فتح مثبت iOS لهذا التطبيق', 'Open the iOS installer for this app'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await signer.install(file.path);
                      if (mounted && !ok) {
                        showAppNotice(
                          context,
                          tr('تعذر فتح مثبت iOS.', 'iOS did not open the installer.'),
                          type: AppNoticeType.error,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                if (file.kind == 'Archive' || file.path.toLowerCase().endsWith('.zip') || isIpa) ...[
                  _actionTile(
                    context,
                    icon: CupertinoIcons.archivebox,
                    title: isIpa ? tr('استخراج ملفات التطبيق', 'Extract application files') : tr('استخراج الملف', 'Extract archive'),
                    subtitle: isIpa ? tr('استخراج محتويات IPA بالكامل داخل المجلدات', 'Extract the complete IPA contents inside Folders') : tr('يتم الاستخراج داخل كرت المجلدات فقط', 'Extraction is available inside Folders only'),
                    onTap: () { Navigator.pop(ctx); _extractArchive(file); },
                  ),
                  const SizedBox(height: 10),
                ],
                _actionTile(
                  context,
                  icon: CupertinoIcons.arrow_right_arrow_left,
                  title: tr('نقل', 'Move'),
                  subtitle: tr('نقل الملف إلى كرت المجلدات', 'Move this file into Folders'),
                  onTap: () { Navigator.pop(ctx); _copyOrMoveFiles([file], move: true); },
                ),
                const SizedBox(height: 10),
                _actionTile(
                  context,
                  icon: CupertinoIcons.doc_on_doc,
                  title: tr('نسخ', 'Copy'),
                  subtitle: tr('نسخ الملف إلى كرت المجلدات', 'Copy this file into Folders'),
                  onTap: () { Navigator.pop(ctx); _copyOrMoveFiles([file], move: false); },
                ),
                const SizedBox(height: 10),
                _actionTile(
                  context,
                  icon: CupertinoIcons.share,
                  title: tr('مشاركة', 'Share'),
                  subtitle: tr('مشاركة أو تصدير الملف', 'Share or export this file'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await signer.share(file.path);
                  },
                ),
                const SizedBox(height: 10),
                _actionTile(
                  context,
                  icon: CupertinoIcons.trash,
                  title: tr('حذف', 'Delete'),
                  subtitle: tr('حذف الملف نهائياً من الجهاز', 'Permanently remove this file'),
                  destructive: true,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _deleteOne(file);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) => Material(
        color: (destructive ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary).withValues(alpha: .075),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (destructive ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: destructive ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_left, size: 16),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text('Booma | بومة', key: widget.topKey, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                        
                        ],
                      ),
                    ),
                    NativeCompatIconButton.filledTonal(
                      onPressed: _import,
                      icon: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverToBoxAdapter(
                child: GlassCard(
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.tray_arrow_down, size: 34, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('استيراد الملفات', 'Import files'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                            const SizedBox(height: 0),
                          
                          ],
                        ),
                      ),
                      NativeCompatFilledButton(onPressed: _import, child: Text(tr('استيراد', 'Import'))),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              sliver: SliverToBoxAdapter(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => SignedFilesScreen(
                          onSignRequested: (file) => widget.onSignRequested?.call(file),
                        ),
                      ),
                    ),
                    child: GlassCard(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
                            child: Icon(CupertinoIcons.checkmark_shield_fill, color: Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('الملفات الموقعة', 'Signed Files'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text('${store.signedFiles.length} ${tr('ملف موقع', 'signed files')}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
                              ],
                            ),
                          ),
                          const Icon(CupertinoIcons.chevron_left, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              sliver: SliverToBoxAdapter(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const FoldersScreen())),
                    child: GlassCard(
                      padding: const EdgeInsets.all(15),
                      child: Row(children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)), child: Icon(CupertinoIcons.folder_fill, color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('المجلدات', 'Folders'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 2), Text(tr('إنشاء مجلدات وتنظيم ونقل ونسخ واستخراج الملفات', 'Create folders, organize, move, copy and extract files'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48)))])),
                        const Icon(CupertinoIcons.chevron_left, size: 18),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                child: Row(
                  children: [
                    Expanded(child: Text(tr('الملفات', 'Library'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
                    if (store.importedFiles.isNotEmpty)
                      Tooltip(
                        message: selecting ? tr('إلغاء', 'Cancel') : tr('تحديد', 'Select'),
                        child: Material(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: selecting ? .20 : .12),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() { selecting = !selecting; selected.clear(); }),
                            child: SizedBox(
                              width: 42,
                              height: 38,
                              child: Icon(selecting ? CupertinoIcons.xmark : CupertinoIcons.checkmark_circle_fill, color: Theme.of(context).colorScheme.primary, size: 21),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (selecting)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: NativeCompatFilledButton.tonalIcon(
                          onPressed: () => setState(() {
                            if (selected.length == store.importedFiles.length) {
                              selected.clear();
                            } else {
                              selected.addAll(store.importedFiles.map((e) => e.id));
                            }
                          }),
                          icon: Icon(selected.length == store.importedFiles.length ? CupertinoIcons.clear_circled : CupertinoIcons.checkmark_alt_circle),
                          label: Text(selected.length == store.importedFiles.length ? tr('إلغاء تحديد الكل', 'Clear all') : tr('تحديد الكل', 'Select all')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      NativeCompatIconButton.filledTonal(
                        tooltip: tr('نقل', 'Move'),
                        onPressed: selected.isEmpty ? null : () => _copyOrMoveFiles(store.importedFiles.where((f) => selected.contains(f.id)).toList(), move: true),
                        icon: const Icon(CupertinoIcons.arrow_right_arrow_left),
                      ),
                      const SizedBox(width: 6),
                      NativeCompatIconButton.filledTonal(
                        tooltip: tr('نسخ', 'Copy'),
                        onPressed: selected.isEmpty ? null : () => _copyOrMoveFiles(store.importedFiles.where((f) => selected.contains(f.id)).toList(), move: false),
                        icon: const Icon(CupertinoIcons.doc_on_doc),
                      ),
                      const SizedBox(width: 8),
                      NativeCompatFilledButton.icon(
                        style: NativeCompatFilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                        onPressed: selected.isEmpty ? null : _deleteSelected,
                        icon: const Icon(CupertinoIcons.trash),
                        label: Text(selected.isEmpty ? tr('حذف', 'Delete') : '${tr('حذف', 'Delete')} (${selected.length})'),
                      ),
                    ],
                  ),
                ),
              ),
            if (store.importedFiles.isEmpty && downloads.activeDownloads.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    tr('لا توجد ملفات بعد\nاستورد تطبيق IPA أو ملف توقيع للبدء', 'No files yet\nImport an IPA or signing asset to begin'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .45)),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
                sliver: SliverList.builder(
                  itemCount: downloads.activeDownloads.length + store.importedFiles.length,
                  itemBuilder: (_, i) {
                    final active = downloads.activeDownloads;
                    if (i < active.length) {
                      final entry = active[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _downloadingAppCard(context, entry.key, entry.value),
                      );
                    }

                    final f = store.importedFiles.reversed.toList()[i - active.length];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () => _toggleSelection(f),
                        onTap: () {
                          if (selecting) { _toggleSelection(f); return; }
                          _showFileActions(f);
                        },
                        child: GlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              if (selecting) ...[
                                Icon(selected.contains(f.id) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: selected.contains(f.id) ? Theme.of(context).colorScheme.primary : null, size: 25),
                                const SizedBox(width: 10),
                              ],
                              _appIcon(context, f),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                                    const SizedBox(height: 3),
                                    Text(_subtitle(f), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48), fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (!selecting)
                                NativeCompatFilledButton(
                                  onPressed: () => _showFileActions(f),
                                  style: NativeCompatFilledButton.styleFrom(
                                    minimumSize: const Size(76, 34),
                                    padding: const EdgeInsets.symmetric(horizontal: 13),
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(tr('التفاصيل', 'Details'), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );

  Future<void> _showDownloadActions(RemoteApp app, AppDownloadSnapshot snap) async {
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: app.iconUrl.trim().isEmpty
                            ? _downloadIconFallback(context)
                            : Image.network(
                                app.iconUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _downloadIconFallback(context),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.displayName(store.isArabic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            snap.paused
                                ? tr('التنزيل متوقف مؤقتاً', 'Download paused')
                                : tr('جاري التنزيل', 'Downloading'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    NativeCompatIconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _actionTile(
                  context,
                  icon: snap.paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
                  title: snap.paused ? tr('استئناف التنزيل', 'Resume download') : tr('إيقاف مؤقت', 'Pause download'),
                  subtitle: snap.paused
                      ? tr('متابعة التنزيل من مكان توقفه', 'Continue this download')
                      : tr('إيقاف التنزيل مؤقتاً بدون إلغائه', 'Temporarily pause without cancelling'),
                  onTap: () {
                    downloads.togglePause(app);
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 10),
                _actionTile(
                  context,
                  icon: CupertinoIcons.xmark_circle,
                  title: tr('إلغاء التنزيل', 'Cancel download'),
                  subtitle: tr('إيقاف التنزيل وحذف الملف غير المكتمل', 'Stop downloading and remove the incomplete file'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await downloads.cancel(app);
                    if (mounted) {
                      showAppNotice(context, tr('تم إلغاء التنزيل.', 'Download cancelled.'));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _downloadingAppCard(BuildContext context, RemoteApp app, AppDownloadSnapshot snap) {
    final progress = snap.progress;
    final percent = progress == null ? null : (progress * 100).clamp(0, 100).round();
    final processing = snap.stage == 'signing' || snap.stage == 'installing';
    final statusText = snap.stage == 'signing'
        ? tr('جاري التوقيع', 'Signing')
        : snap.stage == 'installing'
            ? tr('جاري التثبيت', 'Installing')
            : null;
    final subtitle = processing
        ? statusText!
        : <String>[
            'IPA',
            if (app.version.trim().isNotEmpty) '${tr('الإصدار', 'v')} ${app.version.trim()}',
            if (app.size > 0) _size(app.size),
          ].join(' • ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: snap.downloading ? () => _showDownloadActions(app, snap) : null,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 52,
                height: 52,
                child: app.iconUrl.trim().isEmpty
                    ? _downloadIconFallback(context)
                    : Image.network(
                        app.iconUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _downloadIconFallback(context),
                        loadingBuilder: (context, child, loadingProgress) =>
                            loadingProgress == null ? child : _downloadIconFallback(context),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.displayName(store.isArabic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                  const SizedBox(height: 3),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: processing ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: .48),
                        fontSize: 12,
                        fontWeight: processing ? FontWeight.w800 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (processing)
              NativeCompatFilledButton(
                onPressed: null,
                style: NativeCompatFilledButton.styleFrom(
                  minimumSize: const Size(108, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 7),
                    Text(statusText ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ),
              )
            else
              SizedBox(
                width: 42,
                height: 42,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3.4,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
                    ),
                    if (percent != null)
                      Text('$percent%', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800))
                    else
                      Icon(CupertinoIcons.arrow_down, size: 17, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _downloadIconFallback(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(CupertinoIcons.app_badge, color: Theme.of(context).colorScheme.primary),
      );

  Widget _appIcon(BuildContext context, ImportedFile f) {
    final path = f.iconPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(File(path), width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(context, f)),
      );
    }
    return _fallback(context, f);
  }

  Widget _fallback(BuildContext context, ImportedFile f) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(_icon(f.kind), color: Theme.of(context).colorScheme.primary),
      );

  String _subtitle(ImportedFile f) {
    final kind = switch (f.kind) {
      'Signed IPA' => tr('IPA موقع', 'Signed IPA'),
      'APP' => tr('حزمة APP', 'APP Bundle'),
      'Certificate' => tr('شهادة', 'Certificate'),
      'Provision' => tr('ملف توفير', 'Provision'),
      'Archive' => tr('أرشيف', 'Archive'),
      _ => f.kind,
    };
    final bits = <String>[kind];
    if ((f.version ?? '').isNotEmpty) bits.add('${tr('الإصدار', 'v')} ${f.version}');
    bits.add(_size(f.size));
    return bits.join(' • ');
  }

  IconData _icon(String k) => switch (k) {
        'IPA' => CupertinoIcons.app_badge,
        'APP' => CupertinoIcons.app_badge,
        'Signed IPA' => CupertinoIcons.checkmark_shield_fill,
        'Certificate' => CupertinoIcons.lock_shield,
        'Provision' => CupertinoIcons.doc_text,
        _ => CupertinoIcons.doc,
      };

  String _size(int b) => b > 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';
}
