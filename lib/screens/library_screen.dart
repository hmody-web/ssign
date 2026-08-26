import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/file_import_service.dart';
import '../services/signing_service.dart';
import '../services/localized.dart';
import '../widgets/glass_card.dart';
import 'signed_files_screen.dart';

class LibraryScreen extends StatefulWidget {
  final ValueChanged<ImportedFile>? onSignRequested;
  const LibraryScreen({super.key, this.onSignRequested});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final importer = FileImportService();
  final store = AppStore.instance;
  final signer = SigningService();
  bool selecting = false;
  final Set<String> selected = {};

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
    try { await File(file.path).delete(); } catch (_) {}
    await store.removeFile(file.id);
  }

  Future<void> _deleteSelected() async {
    final targets = store.files.where((f) => selected.contains(f.id)).toList();
    if (targets.isEmpty || !await _confirmDelete(count: targets.length)) return;
    for (final f in targets) {
      try { await File(f.path).delete(); } catch (_) {}
    }
    await store.removeFiles(selected);
    if (mounted) setState(() { selected.clear(); selecting = false; });
  }

  Future<void> _import() async {
    final picked = await importer.pickFiles();
    if (picked.isEmpty) return;
    final enriched = <ImportedFile>[];
    for (final f in picked) {
      if (f.kind == 'IPA') {
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

  Future<void> _showFileActions(ImportedFile file) async {
    final isIpa = _isIpa(file);
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
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (isIpa) ...[
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('تعذر فتح مثبت iOS.', 'iOS did not open the installer.'))),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                ],
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
                          const Text('Booma | بومة', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                        
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
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
                      FilledButton(onPressed: _import, child: Text(tr('استيراد', 'Import'))),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                child: Row(
                  children: [
                    Expanded(child: Text(tr('الملفات', 'Library'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
                    if (store.files.isNotEmpty)
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
                        child: FilledButton.tonalIcon(
                          onPressed: () => setState(() {
                            if (selected.length == store.files.length) selected.clear();
                            else selected.addAll(store.files.map((e) => e.id));
                          }),
                          icon: Icon(selected.length == store.files.length ? CupertinoIcons.clear_circled : CupertinoIcons.checkmark_alt_circle),
                          label: Text(selected.length == store.files.length ? tr('إلغاء تحديد الكل', 'Clear all') : tr('تحديد الكل', 'Select all')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                        onPressed: selected.isEmpty ? null : _deleteSelected,
                        icon: const Icon(CupertinoIcons.trash),
                        label: Text(selected.isEmpty ? tr('حذف', 'Delete') : '${tr('حذف', 'Delete')} (${selected.length})'),
                      ),
                    ],
                  ),
                ),
              ),
            if (store.files.isEmpty)
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
                  itemCount: store.files.length,
                  itemBuilder: (_, i) {
                    final f = store.files.reversed.toList()[i];
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
                                FilledButton(
                                  onPressed: () => _showFileActions(f),
                                  style: FilledButton.styleFrom(
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
        'Signed IPA' => CupertinoIcons.checkmark_shield_fill,
        'Certificate' => CupertinoIcons.lock_shield,
        'Provision' => CupertinoIcons.doc_text,
        _ => CupertinoIcons.doc,
      };

  String _size(int b) => b > 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';
}
