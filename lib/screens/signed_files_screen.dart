import 'dart:io';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/sign_models.dart';
import '../services/app_store.dart';
import '../services/localized.dart';
import '../services/signing_service.dart';
import '../services/persistent_path_service.dart';
import '../widgets/app_notice.dart';
import '../widgets/glass_card.dart';

class SignedFilesScreen extends StatefulWidget {
  final ValueChanged<ImportedFile> onSignRequested;
  final String? highlightFileId;
  const SignedFilesScreen({super.key, required this.onSignRequested, this.highlightFileId});

  @override
  State<SignedFilesScreen> createState() => _SignedFilesScreenState();
}

class _SignedFilesScreenState extends State<SignedFilesScreen> with SingleTickerProviderStateMixin {
  final store = AppStore.instance;
  final signer = SigningService();
  bool selecting = false;
  final Set<String> selected = {};
  bool _highlightActive = false;
  Timer? _highlightTimer;
  late final AnimationController _highlightController;

  List<ImportedFile> get items => store.signedFiles.reversed.toList();

  void _toggle(ImportedFile file) {
    setState(() {
      selecting = true;
      if (!selected.add(file.id)) selected.remove(file.id);
      if (selected.isEmpty) selecting = false;
    });
  }

  Future<bool> _confirmDelete({String? itemName, int? count}) async {
    final message = count != null && count > 1
        ? '${tr('سيتم حذف', 'This will delete')} $count ${tr('ملفات موقعة نهائياً.', 'signed files permanently.')}'
        : '${tr('هل تريد حذف', 'Delete')} «${itemName ?? tr('هذا الملف', 'this file')}» ${tr('نهائياً؟', 'permanently?')}';
    return await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(tr('تأكيد الحذف', 'Confirm delete')),
            content: Padding(padding: const EdgeInsets.only(top: 8), child: Text(message)),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: Text(tr('إلغاء', 'Cancel'))),
              CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(tr('حذف', 'Delete'))),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteSelected() async {
    final targets = items.where((e) => selected.contains(e.id)).toList();
    if (targets.isEmpty || !await _confirmDelete(count: targets.length)) return;
    for (final f in targets) {
      try { await File(f.path).delete(); } catch (_) {}
    }
    await store.removeFiles(selected);
    if (mounted) setState(() { selected.clear(); selecting = false; });
  }

  Future<void> _deleteOne(ImportedFile file) async {
    if (!await _confirmDelete(itemName: file.name)) return;
    try { await File(file.path).delete(); } catch (_) {}
    await store.removeFile(file.id);
  }

  Future<void> _showSideActions(ImportedFile file) async {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('إغلاق', 'Close'),
      barrierColor: Colors.black.withValues(alpha: .38),
      transitionDuration: const Duration(milliseconds: 330),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        child: Align(
          alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 312,
                child: GlassCard(
                  radius: 30,
                  padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _icon(context, file),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                Text(file.bundleId ?? tr('IPA موقع', 'Signed IPA'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(CupertinoIcons.xmark_circle_fill)),
                        ],
                      ),
                      const SizedBox(height: 17),
                      _sideAction(
                        dialogContext,
                        icon: CupertinoIcons.arrow_down_circle_fill,
                        title: tr('تثبيت', 'Install'),
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          final ok = await signer.install(file.path);
                          if (mounted && !ok) {
                            showAppNotice(context, tr('تعذر فتح مثبت iOS.', 'iOS did not open the installer.'), type: AppNoticeType.error);
                          }
                        },
                      ),
                      const SizedBox(height: 9),
                      _sideAction(
                        dialogContext,
                        icon: CupertinoIcons.signature,
                        title: tr('توقيع مرة أخرى', 'Sign again'),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          Navigator.of(context).pop();
                          widget.onSignRequested(file);
                        },
                      ),
                      const SizedBox(height: 9),
                      _sideAction(
                        dialogContext,
                        icon: CupertinoIcons.share,
                        title: tr('مشاركة', 'Share'),
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          await signer.share(file.path);
                        },
                      ),
                      const SizedBox(height: 9),
                      _sideAction(
                        dialogContext,
                        icon: CupertinoIcons.trash_fill,
                        title: tr('حذف', 'Delete'),
                        destructive: true,
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          await _deleteOne(file);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) {
        final begin = rtl ? const Offset(1.0, 0) : const Offset(-1.0, 0);
        final slide = Tween<Offset>(begin: begin, end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return SlideTransition(position: slide, child: FadeTransition(opacity: animation, child: child));
      },
    );
  }

  Widget _sideAction(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Material(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: destructive ? color : null))),
              Icon(CupertinoIcons.chevron_forward, size: 15, color: color.withValues(alpha: .8)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), lowerBound: .25, upperBound: 1);
    _highlightActive = widget.highlightFileId?.isNotEmpty == true;
    if (_highlightActive) {
      _highlightController.repeat(reverse: true);
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        _highlightController.stop();
        if (mounted) setState(() => _highlightActive = false);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _repairMissingIcons());
  }

  @override
  void dispose() { _highlightTimer?.cancel(); _highlightController.dispose(); super.dispose(); }

  Future<void> _repairMissingIcons() async {
    final snapshot = List<ImportedFile>.from(store.signedFiles);
    for (final f in snapshot) {
      final repairedIpa = await PersistentPathService.instance.resolveDataFile(f.path);
      final repairedIcon = await PersistentPathService.instance.resolveIcon(
        storedPath: f.iconPath,
        bundleId: f.bundleId,
      );
      var current = f;
      if ((repairedIpa != null && repairedIpa != f.path) ||
          (repairedIcon != null && repairedIcon != f.iconPath)) {
        current = f.copyWith(
          path: repairedIpa ?? f.path,
          iconPath: repairedIcon ?? f.iconPath ?? '',
        );
        await store.replaceFile(current);
      }
      final hasIcon = current.iconPath != null &&
          current.iconPath!.isNotEmpty &&
          File(current.iconPath!).existsSync();
      final ipaPath = await PersistentPathService.instance.resolveDataFile(current.path);
      if (hasIcon || ipaPath == null) continue;
      try {
        final info = await signer.inspectIpa(ipaPath);
        final icon = (info['iconPath'] ?? '').toString().trim();
        await store.replaceFile(current.copyWith(
          path: ipaPath,
          iconPath: icon.isEmpty ? (current.iconPath ?? '') : icon,
          bundleId: (info['bundleId'] ?? current.bundleId ?? '').toString(),
          version: (info['version'] ?? current.version ?? '').toString(),
        ));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          scrolledUnderElevation: 0,
          title: Text(tr('الملفات الموقعة', 'Signed Files')),
          actions: [
            if (items.isNotEmpty)
              IconButton.filledTonal(
                tooltip: selecting ? tr('إلغاء', 'Cancel') : tr('تحديد', 'Select'),
                onPressed: () => setState(() { selecting = !selecting; selected.clear(); }),
                icon: Icon(selecting ? CupertinoIcons.xmark : CupertinoIcons.checkmark_circle_fill),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final files = items;
            if (files.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.checkmark_shield, size: 48, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(tr('لا توجد ملفات موقعة بعد', 'No signed files yet'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 5),
                      Text(tr('ستظهر هنا كل ملفات IPA التي تقوم بتوقيعها.', 'Every IPA you sign will appear here.'), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
                    ],
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
              children: [
                if (selecting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => setState(() {
                              if (selected.length == files.length) selected.clear(); else selected.addAll(files.map((e) => e.id));
                            }),
                            icon: Icon(selected.length == files.length ? CupertinoIcons.clear_circled : CupertinoIcons.checkmark_alt_circle),
                            label: Text(selected.length == files.length ? tr('إلغاء تحديد الكل', 'Clear all') : tr('تحديد الكل', 'Select all')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                          onPressed: selected.isEmpty ? null : _deleteSelected,
                          icon: const Icon(CupertinoIcons.trash),
                          label: Text('${tr('حذف', 'Delete')} ${selected.isEmpty ? '' : '(${selected.length})'}'),
                        ),
                      ],
                    ),
                  ),
                ...files.map((f) {
                  final checked = selected.contains(f.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _toggle(f),
                      onTap: () {
                        if (selecting) { _toggle(f); return; }
                        _showSideActions(f);
                      },
                      child: AnimatedBuilder(
                        animation: _highlightController,
                        builder: (context, child) {
                          final active = _highlightActive && widget.highlightFileId == f.id;
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: active
                                  ? [BoxShadow(color: const Color(0xFF67C8FF).withValues(alpha: .12 + (.30 * _highlightController.value)), blurRadius: 18 + (10 * _highlightController.value), spreadRadius: 1 + _highlightController.value)]
                                  : const [],
                            ),
                            child: child,
                          );
                        },
                        child: GlassCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            if (selecting) ...[
                              Icon(checked ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: checked ? Theme.of(context).colorScheme.primary : null, size: 25),
                              const SizedBox(width: 10),
                            ],
                            _icon(context, f),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                                const SizedBox(height: 3),
                                Text(f.bundleId ?? tr('IPA موقع', 'Signed IPA'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
                              ]),
                            ),
                            if (!selecting) Icon(CupertinoIcons.chevron_left, size: 19, color: Theme.of(context).colorScheme.primary),
                          ],
                        ),
                      ),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );

  Widget _icon(BuildContext context, ImportedFile f) {
    final path = f.iconPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(path), width: 52, height: 52, fit: BoxFit.cover));
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
      child: Icon(CupertinoIcons.checkmark_shield_fill, color: Theme.of(context).colorScheme.primary),
    );
  }
}
