import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/admin_service.dart';
import '../services/localized.dart';
import '../widgets/glass_card.dart';

class AdminGateScreen extends StatefulWidget {
  const AdminGateScreen({super.key});
  @override
  State<AdminGateScreen> createState() => _AdminGateScreenState();
}

class _AdminGateScreenState extends State<AdminGateScreen> {
  bool _loading = true;
  bool _paired = false;
  String? _error;
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = await AdminService.instance.deviceId;
    if (!mounted) return;
    _paired = id?.isNotEmpty == true;
    _loading = false;
    setState(() {});
    if (_paired) _enter();
  }

  Future<void> _enter() async {
    setState(() { _loading = true; _error = null; });
    try {
      await AdminService.instance.loginWithDevice();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (_) => const AdminDashboardScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _clean(e); });
    }
  }

  Future<void> _pair() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة مرور لوحة الخادم.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await AdminService.instance.pair(username: _user.text, password: _pass.text);
      _pass.clear();
      _paired = true;
      await _enter();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _clean(e); });
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').replaceFirst('PlatformException(AUTH_CANCELLED, ', '').split(', null, null)').first;

  @override
  void dispose() { _user.dispose(); _pass.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('لوحة الأدمن', 'Admin')), backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary.withValues(alpha: .14)),
                  child: Icon(CupertinoIcons.lock_shield_fill, size: 38, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 18),
                Text(_paired ? tr('جهاز الأدمن الموثوق', 'Trusted admin device') : tr('ربط جهاز الأدمن', 'Pair admin device'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  _paired
                      ? tr('الدخول محمي بهوية هذا الجهاز وSecure Enclave ويتطلب Face ID أو رمز قفل الجهاز.', 'Access is protected by this device identity and Secure Enclave.')
                      : tr('هذه الخطوة تتم مرة واحدة فقط. بعد الربط لن يستطيع جهاز آخر تسجيل نفسه كأدمن من التطبيق.', 'This one-time pairing locks admin access to this device.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58), height: 1.5),
                ),
                if (!_paired) ...[
                  const SizedBox(height: 22),
                  TextField(controller: _user, textInputAction: TextInputAction.next, decoration: _dec('اسم مستخدم لوحة الخادم', CupertinoIcons.person_fill)),
                  const SizedBox(height: 12),
                  TextField(controller: _pass, obscureText: true, onSubmitted: (_) => _pair(), decoration: _dec('كلمة المرور', CupertinoIcons.lock_fill)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _loading ? null : (_paired ? _enter : _pair),
                  icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_paired ? Icons.fingerprint : CupertinoIcons.link),
                  label: Text(_paired ? tr('تحقق وافتح اللوحة', 'Verify & open') : tr('ربط هذا الجهاز', 'Pair this device')),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
    prefixIcon: Icon(icon), hintText: hint, filled: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
  );
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminDashboardData? _data;
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { _data = await AdminService.instance.dashboard(); }
    catch (e) { _error = e.toString().replaceFirst('Exception: ', ''); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm([AdminApp? app]) async {
    final changed = await Navigator.of(context).push<bool>(CupertinoPageRoute(builder: (_) => AdminAppFormScreen(app: app)));
    if (changed == true) _load();
  }

  Future<void> _delete(AdminApp app) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('حذف التطبيق؟'), content: Text('سيتم حذف ${app.name} وملف IPA نهائيًا من الخادم.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))],
    ));
    if (ok != true) return;
    try { await AdminService.instance.deleteApp(app.id); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
  }

  @override
  Widget build(BuildContext context) {
    final all = _data?.apps ?? const <AdminApp>[];
    final q = _query.trim().toLowerCase();
    final apps = q.isEmpty ? all : all.where((a) => '${a.name} ${a.developer} ${a.bundleId}'.toLowerCase().contains(q)).toList();
    return PopScope(
      onPopInvokedWithResult: (_, __) => AdminService.instance.lock(),
      child: Scaffold(
        appBar: AppBar(
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مكتبة السراي', style: TextStyle(fontWeight: FontWeight.w900)), Text('لوحة الإدارة الآمنة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500))]),
          backgroundColor: Colors.transparent, scrolledUnderElevation: 0,
          actions: [IconButton(onPressed: _load, icon: const Icon(CupertinoIcons.refresh)), const SizedBox(width: 6)],
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _openForm(), icon: const Icon(CupertinoIcons.add), label: const Text('إضافة تطبيق')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), children: [
            _hero(context),
            const SizedBox(height: 14),
            if (_data != null) Row(children: [
              Expanded(child: _stat('التطبيقات', '${_data!.appCount}', CupertinoIcons.square_grid_2x2_fill)), const SizedBox(width: 10),
              Expanded(child: _stat('المساحة', _size(_data!.bytes), Icons.storage_rounded)),
            ]),
            const SizedBox(height: 14),
            TextField(onChanged: (v) => setState(() => _query = v), decoration: InputDecoration(prefixIcon: const Icon(CupertinoIcons.search), hintText: 'ابحث بالاسم أو المطور أو Bundle ID', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
            const SizedBox(height: 14),
            if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null) _errorCard(_error!)
            else if (apps.isEmpty) const Padding(padding: EdgeInsets.all(35), child: Center(child: Text('لا توجد تطبيقات')))
            else ...apps.map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _appCard(a))),
          ]),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary.withValues(alpha: .24), Theme.of(context).colorScheme.primary.withValues(alpha: .04)], begin: Alignment.topRight, end: Alignment.bottomLeft)),
    child: const Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ALSARAY ADMIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4)), SizedBox(height: 7), Text('تحكم كامل بالمكتبة من جهازك.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), SizedBox(height: 5), Text('رفع • تعديل • حذف • إدارة IPA والمعاينات', style: TextStyle(fontSize: 12))])), Icon(CupertinoIcons.shield_lefthalf_fill, size: 44)]),
  );

  Widget _stat(String t, String v, IconData i) => GlassCard(child: Row(children: [Icon(i), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5), fontSize: 12)), Text(v, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))]))]));

  Widget _appCard(AdminApp a) => GlassCard(
    padding: const EdgeInsets.all(12),
    child: Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(17), child: a.iconUrl.isEmpty ? Container(width: 62, height: 62, color: Colors.grey.withValues(alpha: .15), child: const Icon(CupertinoIcons.app)) : Image.network(a.iconUrl, width: 62, height: 62, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 62, height: 62, color: Colors.grey.withValues(alpha: .15), child: const Icon(CupertinoIcons.app)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.name.isEmpty ? 'بدون اسم' : a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 2), Text(a.bundleId, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))), const SizedBox(height: 7), Wrap(spacing: 6, children: [_chip('v${a.version.isEmpty ? '—' : a.version}'), _chip(_size(a.size))])])),
      PopupMenuButton<String>(onSelected: (v) => v == 'edit' ? _openForm(a) : _delete(a), itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Row(children: [Icon(CupertinoIcons.pencil), SizedBox(width: 9), Text('تعديل')])), PopupMenuItem(value: 'delete', child: Row(children: [Icon(CupertinoIcons.trash, color: Colors.red), SizedBox(width: 9), Text('حذف', style: TextStyle(color: Colors.red))]))]),
    ]),
  );

  Widget _chip(String s) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(9)), child: Text(s, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)));
  Widget _errorCard(String s) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .1), borderRadius: BorderRadius.circular(18)), child: Text(s, style: const TextStyle(color: Colors.red)));
  String _size(int b) { if (b < 1024) return '$b B'; if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB'; if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB'; return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'; }
}

class AdminAppFormScreen extends StatefulWidget {
  final AdminApp? app;
  const AdminAppFormScreen({super.key, this.app});
  @override
  State<AdminAppFormScreen> createState() => _AdminAppFormScreenState();
}

class _AdminAppFormScreenState extends State<AdminAppFormScreen> {
  late final TextEditingController _name, _developer, _bundle, _version, _build, _category, _description;
  String? _ipaPath, _iconPath;
  final List<String> _shots = [];
  bool _busy = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState(); final a = widget.app;
    _name = TextEditingController(text: a?.name ?? ''); _developer = TextEditingController(text: a?.developer ?? ''); _bundle = TextEditingController(text: a?.bundleId ?? ''); _version = TextEditingController(text: a?.version ?? ''); _build = TextEditingController(text: a?.build ?? ''); _category = TextEditingController(text: a?.category ?? ''); _description = TextEditingController(text: a?.description ?? '');
  }

  Future<void> _pickIpa() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    final path = r?.files.single.path; if (path == null) return;
    if (!path.toLowerCase().endsWith('.ipa')) { setState(() => _error = 'اختر ملف IPA.'); return; }
    setState(() { _ipaPath = path; _busy = true; _progress = 0; _error = null; });
    try {
      final meta = await AdminService.instance.inspectIpa(path, onProgress: (p) { if (mounted) setState(() => _progress = p); });
      final m = Map<String, dynamic>.from(meta['meta'] is Map ? meta['meta'] as Map : const {});
      if ('${m['name'] ?? ''}'.isNotEmpty) _name.text = '${m['name']}';
      if ('${m['bundle_id'] ?? ''}'.isNotEmpty) _bundle.text = '${m['bundle_id']}';
      if ('${m['version'] ?? ''}'.isNotEmpty) _version.text = '${m['version']}';
      if ('${m['build'] ?? ''}'.isNotEmpty) _build.text = '${m['build']}';
    } catch (e) { _error = e.toString().replaceFirst('Exception: ', ''); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickIcon() async { final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95); if (x != null) setState(() => _iconPath = x.path); }
  Future<void> _pickShots() async { final xs = await ImagePicker().pickMultiImage(imageQuality: 95); if (xs.isNotEmpty) setState(() { _shots.clear(); _shots.addAll(xs.map((e) => e.path)); }); }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) { setState(() => _error = 'اسم التطبيق مطلوب.'); return; }
    if (widget.app == null && _ipaPath == null) { setState(() => _error = 'اختر ملف IPA أولًا.'); return; }
    setState(() { _busy = true; _progress = 0; _error = null; });
    try {
      await AdminService.instance.saveApp(id: widget.app?.id ?? '', name: _name.text.trim(), developer: _developer.text.trim(), description: _description.text.trim(), bundleId: _bundle.text.trim(), version: _version.text.trim(), build: _build.text.trim(), category: _category.text.trim(), ipaPath: _ipaPath, iconPath: _iconPath, screenshotPaths: _shots, onProgress: (p) { if (mounted) setState(() => _progress = p); });
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() { _busy = false; _error = e.toString().replaceFirst('Exception: ', ''); }); }
  }

  @override
  void dispose() { for (final c in [_name,_developer,_bundle,_version,_build,_category,_description]) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.app == null ? 'إضافة تطبيق' : 'تعديل التطبيق'), backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
      _picker('ملف IPA', _ipaPath == null ? (widget.app == null ? 'اختيار ملف IPA' : 'استبدال IPA الحالي') : _ipaPath!.split(Platform.pathSeparator).last, CupertinoIcons.archivebox_fill, _pickIpa),
      if (_busy) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null, borderRadius: BorderRadius.circular(30))),
      const SizedBox(height: 15),
      Row(children: [Expanded(child: _field(_name, 'اسم التطبيق')), const SizedBox(width: 10), Expanded(child: _field(_developer, 'المطور'))]), const SizedBox(height: 10),
      _field(_bundle, 'Bundle ID'), const SizedBox(height: 10),
      Row(children: [Expanded(child: _field(_version, 'الإصدار')), const SizedBox(width: 10), Expanded(child: _field(_build, 'Build'))]), const SizedBox(height: 10),
      _field(_category, 'التصنيف'), const SizedBox(height: 10),
      TextField(controller: _description, minLines: 4, maxLines: 7, decoration: _dec('الوصف')), const SizedBox(height: 15),
      Row(children: [Expanded(child: _picker('أيقونة التطبيق', _iconPath == null ? 'اختيار صورة' : 'تم اختيار الصورة ✓', CupertinoIcons.photo_fill, _pickIcon)), const SizedBox(width: 10), Expanded(child: _picker('المعاينات', _shots.isEmpty ? 'اختيار صور' : '${_shots.length} صور ✓', CupertinoIcons.rectangle_stack_fill, _pickShots))]),
      if (_iconPath != null) ...[const SizedBox(height: 12), Center(child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.file(File(_iconPath!), width: 94, height: 94, fit: BoxFit.cover)))],
      if (_shots.isNotEmpty) ...[const SizedBox(height: 12), SizedBox(height: 140, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _shots.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(_shots[i]), width: 80, height: 140, fit: BoxFit.cover))))],
      if (_error != null) ...[const SizedBox(height: 14), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: Text(_error!, style: const TextStyle(color: Colors.red)))],
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(CupertinoIcons.cloud_upload_fill), label: Text(widget.app == null ? 'رفع وإضافة التطبيق' : 'حفظ التعديلات'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)))),
    ]),
  );

  Widget _field(TextEditingController c, String h) => TextField(controller: c, decoration: _dec(h));
  InputDecoration _dec(String h) => InputDecoration(labelText: h, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none));
  Widget _picker(String t, String s, IconData i, VoidCallback tap) => Material(color: Colors.transparent, child: InkWell(onTap: _busy ? null : tap, borderRadius: BorderRadius.circular(20), child: GlassCard(padding: const EdgeInsets.all(14), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(i, color: Theme.of(context).colorScheme.primary)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w900)), Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5)))])), const Icon(CupertinoIcons.chevron_forward, size: 16)]))));
}
