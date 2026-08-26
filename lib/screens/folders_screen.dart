import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/folder_workspace_service.dart';
import '../services/localized.dart';
import '../services/signing_service.dart';
import '../models/sign_models.dart';
import 'sign_screen.dart';
import '../widgets/app_notice.dart';
import '../widgets/glass_card.dart';

class FoldersScreen extends StatefulWidget {
  final String initialRelativePath;
  const FoldersScreen({super.key, this.initialRelativePath = ''});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  final service = FolderWorkspaceService.instance;
  final signing = SigningService();
  final Map<String, Future<Map<String, dynamic>>> _appInfoCache = {};
  late String relativePath;
  List<FileSystemEntity> items = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    relativePath = widget.initialRelativePath;
    _load();
  }

  Future<void> _load() async {
    final list = await service.list(relativePath);
    if (!mounted) return;
    setState(() { items = list; loading = false; });
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(tr('إنشاء مجلد', 'New folder')),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(controller: ctrl, placeholder: tr('اسم المجلد', 'Folder name'), autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('إنشاء', 'Create'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await service.createFolder(relativePath, name);
    await _load();
  }

  Future<void> _addFiles() async {
    final added = await service.pickAndAddFiles(relativePath);
    if (!mounted) return;
    if (added.isEmpty) {
      showAppNotice(context, tr('لم تتم إضافة ملفات. الصور والفيديو وPDF غير مسموحة هنا.', 'No files were added. Images, videos and PDFs are excluded.'));
    } else {
      showAppNotice(context, '${tr('تمت إضافة', 'Added')} ${added.length} ${tr('ملف', 'file(s)')}.');
      await _load();
    }
  }

  Future<void> _extract(File file) async {
    final dest = await showFolderDestinationPicker(context, title: tr('استخراج إلى مجلد', 'Extract to folder'));
    if (dest == null) return;
    try {
      await service.extractZip(zipPath: file.path, relative: dest);
      if (!mounted) return;
      showAppNotice(context, tr('تم استخراج الملف داخل كرت المجلدات فقط.', 'Archive extracted inside Folders only.'));
      await _load();
    } catch (_) {
      if (mounted) showAppNotice(context, tr('تعذر استخراج الملف المضغوط.', 'Could not extract the archive.'), type: AppNoticeType.error);
    }
  }

  Future<String?> _chooseDestination({String titleAr = 'اختيار المجلد', String titleEn = 'Choose folder'}) async {
    var current = '';
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => FutureBuilder<List<FileSystemEntity>>(
          future: service.list(current),
          builder: (ctx, snap) {
            final dirs = (snap.data ?? const <FileSystemEntity>[]).whereType<Directory>().toList();
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GlassCard(
                  radius: 28,
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * .58,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          if (current.isNotEmpty) IconButton(onPressed: () { current = p.dirname(current) == '.' ? '' : p.dirname(current); setSheetState((){}); }, icon: const Icon(CupertinoIcons.chevron_back)),
                          Expanded(child: Text(tr(titleAr, titleEn), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                          TextButton(onPressed: () => Navigator.pop(ctx, current), child: Text(tr('اختيار هنا', 'Choose here'))),
                        ]),
                        const SizedBox(height: 8),
                        Expanded(
                          child: dirs.isEmpty
                              ? Center(child: Text(tr('لا توجد مجلدات داخل هذا المكان', 'No folders here')))
                              : ListView.separated(
                                  itemCount: dirs.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, i) => ListTile(
                                    leading: const Icon(CupertinoIcons.folder_fill),
                                    title: Text(p.basename(dirs[i].path)),
                                    trailing: const Icon(CupertinoIcons.chevron_forward, size: 17),
                                    onTap: () { current = current.isEmpty ? p.basename(dirs[i].path) : p.join(current, p.basename(dirs[i].path)); setSheetState((){}); },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  bool _isAppBundle(FileSystemEntity entity) => entity is Directory && p.extension(entity.path).toLowerCase() == '.app';

  Future<Map<String, dynamic>> _appInfo(Directory app) =>
      _appInfoCache.putIfAbsent(app.path, () => signing.inspectIpa(app.path));

  Future<int> _directorySize(Directory dir) async {
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
    } catch (_) {}
    return total;
  }

  Future<void> _signApp(Directory app) async {
    Map<String, dynamic> info = const {};
    try { info = await _appInfo(app); } catch (_) {}
    final displayName = (info['displayName'] ?? '').toString().trim();
    final model = ImportedFile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: displayName.isEmpty ? p.basenameWithoutExtension(app.path) : displayName,
      path: app.path,
      kind: 'APP',
      size: await _directorySize(app),
      importedAt: DateTime.now(),
      bundleId: (info['bundleId'] ?? '').toString(),
      version: (info['version'] ?? '').toString(),
      iconPath: (info['iconPath'] ?? '').toString(),
    );
    if (!mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('التوقيع', 'Sign'))),
          body: SignScreen(preparedFile: model),
        ),
      ),
    );
  }

  Future<void> _installApp(Directory app) async {
    try {
      final ok = await signing.install(app.path);
      if (mounted && !ok) {
        showAppNotice(context, tr('تعذر فتح مثبت iOS.', 'iOS did not open the installer.'), type: AppNoticeType.error);
      }
    } catch (e) {
      if (mounted) showAppNotice(context, '${tr('تعذر تثبيت التطبيق', 'Could not install app')}: $e', type: AppNoticeType.error);
    }
  }

  Future<void> _actions(FileSystemEntity entity) async {
    final isDir = entity is Directory;
    final isApp = _isAppBundle(entity);
    final isZip = entity is File && p.extension(entity.path).toLowerCase() == '.zip';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GlassCard(
            radius: 28,
            padding: const EdgeInsets.all(14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: Icon(isDir ? CupertinoIcons.folder_fill : CupertinoIcons.doc_fill), title: Text(p.basename(entity.path), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (isZip) ListTile(leading: const Icon(CupertinoIcons.archivebox), title: Text(tr('استخراج إلى...', 'Extract to...')), onTap: () { Navigator.pop(ctx); _extract(entity); }),
              if (isApp) ListTile(leading: const Icon(CupertinoIcons.signature), title: Text(tr('توقيع', 'Sign')), onTap: () { Navigator.pop(ctx); _signApp(entity as Directory); }),
              if (isApp) ListTile(leading: const Icon(CupertinoIcons.arrow_down_circle), title: Text(tr('تثبيت', 'Install')), onTap: () { Navigator.pop(ctx); _installApp(entity as Directory); }),
              ListTile(leading: const Icon(CupertinoIcons.arrow_right_arrow_left), title: Text(tr('نقل', 'Move')), onTap: () async {
                Navigator.pop(ctx);
                final dest = await _chooseDestination(titleAr: 'نقل إلى', titleEn: 'Move to');
                if (dest == null) return;
                await service.moveEntity(entity, dest);
                await _load();
              }),
              ListTile(leading: const Icon(CupertinoIcons.doc_on_doc), title: Text(tr('نسخ', 'Copy')), onTap: () async {
                Navigator.pop(ctx);
                final dest = await _chooseDestination(titleAr: 'نسخ إلى', titleEn: 'Copy to');
                if (dest == null) return;
                await service.copyEntity(entity, dest);
                await _load();
              }),
              ListTile(leading: Icon(CupertinoIcons.trash, color: Theme.of(context).colorScheme.error), title: Text(tr('حذف', 'Delete')), onTap: () async { Navigator.pop(ctx); await service.deleteEntity(entity); await _load(); }),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(relativePath.isEmpty ? tr('المجلدات', 'Folders') : p.basename(relativePath)),
        actions: [
          IconButton(onPressed: _createFolder, icon: const Icon(CupertinoIcons.folder_badge_plus)),
          IconButton(onPressed: _addFiles, icon: const Icon(CupertinoIcons.add_circled)),
        ],
      ),
      body: loading
          ? const Center(child: CupertinoActivityIndicator())
          : items.isEmpty
              ? Center(child: Text(tr('هذا المجلد فارغ', 'This folder is empty'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final e = items[i];
                    final isDir = e is Directory;
                    final isApp = _isAppBundle(e);
                    Widget tile({String? appName, String? iconPath}) => ListTile(
                      leading: isApp && iconPath != null && iconPath.isNotEmpty && File(iconPath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(File(iconPath), width: 44, height: 44, fit: BoxFit.cover),
                            )
                          : Icon(isApp ? CupertinoIcons.app_badge : isDir ? CupertinoIcons.folder_fill : CupertinoIcons.doc_fill, color: Theme.of(context).colorScheme.primary),
                      title: Text(isApp && appName != null && appName.trim().isNotEmpty ? appName : p.basename(e.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: isApp ? Text(p.basename(e.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .45))) : null,
                      trailing: IconButton(icon: const Icon(CupertinoIcons.ellipsis), onPressed: () => _actions(e)),
                      onTap: isDir
                          ? () => Navigator.push(context, CupertinoPageRoute(builder: (_) => FoldersScreen(initialRelativePath: relativePath.isEmpty ? p.basename(e.path) : p.join(relativePath, p.basename(e.path)))))
                          : () => _actions(e),
                    );
                    return GlassCard(
                      padding: EdgeInsets.zero,
                      child: isApp
                          ? FutureBuilder<Map<String, dynamic>>(
                              future: _appInfo(e as Directory),
                              builder: (_, snap) => tile(
                                appName: snap.data?['displayName']?.toString(),
                                iconPath: snap.data?['iconPath']?.toString(),
                              ),
                            )
                          : tile(),
                    );
                  },
                ),
    );
  }
}

Future<String?> showFolderDestinationPicker(BuildContext context, {String? title}) async {
  final service = FolderWorkspaceService.instance;
  final signing = SigningService();
  final Map<String, Future<Map<String, dynamic>>> _appInfoCache = {};
  var current = '';
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => FutureBuilder<List<FileSystemEntity>>(
        future: service.list(current),
        builder: (ctx, snap) {
          final dirs = (snap.data ?? const <FileSystemEntity>[]).whereType<Directory>().toList();
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GlassCard(
                radius: 28,
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: MediaQuery.sizeOf(ctx).height * .58,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      if (current.isNotEmpty) IconButton(onPressed: () { current = p.dirname(current) == '.' ? '' : p.dirname(current); setSheetState(() {}); }, icon: const Icon(CupertinoIcons.chevron_back)),
                      Expanded(child: Text(title ?? tr('اختيار المجلد', 'Choose folder'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                      TextButton(onPressed: () => Navigator.pop(ctx, current), child: Text(tr('اختيار هنا', 'Choose here'))),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(child: dirs.isEmpty ? Center(child: Text(tr('لا توجد مجلدات داخل هذا المكان', 'No folders here'))) : ListView.separated(
                      itemCount: dirs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(CupertinoIcons.folder_fill),
                        title: Text(p.basename(dirs[i].path)),
                        trailing: const Icon(CupertinoIcons.chevron_forward, size: 17),
                        onTap: () { current = current.isEmpty ? p.basename(dirs[i].path) : p.join(current, p.basename(dirs[i].path)); setSheetState(() {}); },
                      ),
                    )),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
