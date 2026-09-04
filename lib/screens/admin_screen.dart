import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/admin_service.dart';
import '../services/ipa_library_service.dart';
import '../services/signing_service.dart';
import '../services/localized.dart';
import '../services/source_catalog_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/native_material_controls.dart';
import '../widgets/native_ios_controls.dart';

const Map<String, String> _adminCategoryAr = {
  'games': 'ألعاب',
  'game': 'ألعاب',
  'social': 'تواصل اجتماعي',
  'social networking': 'تواصل اجتماعي',
  'photo & video': 'صور وفيديو',
  'photo': 'صور',
  'video': 'فيديو',
  'music': 'موسيقى',
  'entertainment': 'ترفيه',
  'utilities': 'أدوات',
  'utility': 'أدوات',
  'tools': 'أدوات',
  'business': 'أعمال',
  'education': 'تعليم',
  'productivity': 'إنتاجية',
  'finance': 'مال وأعمال',
  'shopping': 'تسوق',
  'lifestyle': 'نمط حياة',
  'health & fitness': 'صحة ولياقة',
  'health': 'صحة ولياقة',
  'sports': 'رياضة',
  'travel': 'سفر',
  'navigation': 'ملاحة',
  'news': 'أخبار',
  'weather': 'طقس',
  'food & drink': 'طعام وشراب',
  'food': 'طعام وشراب',
  'books': 'كتب',
  'reference': 'مراجع',
  'medical': 'طب',
  'developer tools': 'أدوات المطور',
  'graphics & design': 'رسوم وتصميم',
};

String _adminCategoryDisplay(String category) =>
    _adminCategoryAr[category.trim().toLowerCase()] ?? category.trim();

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
                  NativeIOSTextField(controller: _user, placeholder: 'اسم مستخدم لوحة الخادم', leadingSystemImage: 'person.fill'),
                  const SizedBox(height: 12),
                  NativeIOSTextField(controller: _pass, obscureText: true, onSubmitted: (_) => _pair(), placeholder: 'كلمة المرور', leadingSystemImage: 'lock.fill'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
                ],
                const SizedBox(height: 18),
                NativeIOSButton(
                  title: _loading ? tr('جاري التحقق…', 'Verifying…') : (_paired ? tr('تحقق وافتح اللوحة', 'Verify & open') : tr('ربط هذا الجهاز', 'Pair this device')),
                  systemImage: _paired ? 'touchid' : 'link',
                  onPressed: _loading ? null : (_paired ? _enter : _pair),
                  prominent: true,
                  height: 54,
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
  final _queryController = TextEditingController();
  String? _error;
  List<String> _boomaCategories = const [];

  @override
  void initState() { super.initState(); _load(); _loadBoomaCategories(); }

  Future<void> _loadBoomaCategories() async {
    try {
      final values = await IpaLibraryService().fetchBoomaCategories();
      if (mounted) setState(() => _boomaCategories = values);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { _data = await AdminService.instance.dashboard(); }
    catch (e) { _error = e.toString().replaceFirst('Exception: ', ''); }
    if (mounted) setState(() => _loading = false);
  }

  List<String> get _availableCategories => _boomaCategories;

  Future<void> _openForm([AdminApp? app]) async {
    final changed = await Navigator.of(context).push<bool>(CupertinoPageRoute(
      builder: (_) => AdminAppFormScreen(app: app, categories: _availableCategories),
    ));
    if (changed == true) _load();
  }

  Future<void> _openSources() async {
    await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const AdminSourcesScreen()));
  }

  Future<void> _delete(AdminApp app) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('حذف التطبيق؟'), content: Text('سيتم حذف ${app.name} وملف IPA نهائيًا من الخادم.'),
      actions: [NativeCompatTextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), NativeCompatFilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))],
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
          actions: [NativeCompatIconButton(onPressed: _load, icon: const Icon(CupertinoIcons.refresh)), const SizedBox(width: 6)],
        ),
        floatingActionButton: NativeIOSButton(title: 'إضافة تطبيق', systemImage: 'plus', onPressed: () => _openForm(), prominent: true, width: 150, height: 50),
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
            _sourceManagementCard(context),
            const SizedBox(height: 14),
            NativeIOSTextField(controller: _queryController, onChanged: (v) => setState(() => _query = v), placeholder: 'ابحث بالاسم أو المطور أو Bundle ID', leadingSystemImage: 'magnifyingglass'),
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

  Widget _sourceManagementCard(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _openSources,
      child: GlassCard(
        padding: const EdgeInsets.all(15),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(CupertinoIcons.link, color: Theme.of(context).colorScheme.primary, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('مصادر التطبيقات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 3),
            Text('أضف وعدّل المصادر التي تظهر في مكتبة المصادر داخل بومة.', style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
          ])),
          Icon(CupertinoIcons.chevron_forward, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .4)),
        ]),
      ),
    ),
  );

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

class AdminSourcesScreen extends StatefulWidget {
  const AdminSourcesScreen({super.key});
  @override
  State<AdminSourcesScreen> createState() => _AdminSourcesScreenState();
}

class _AdminSourcesScreenState extends State<AdminSourcesScreen> {
  List<AdminSource> _sources = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _sources = await AdminService.instance.sourceCatalog();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm([AdminSource? source]) async {
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => AdminSourceFormScreen(source: source)),
    );
    if (changed == true) {
      SourceCatalogService.instance.invalidate();
      await _load();
    }
  }

  Future<void> _delete(AdminSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف المصدر؟'),
        content: Text('سيختفي «${source.name}» من مكتبة المصادر داخل بومة. لن يتم حذف التطبيقات من المصدر الخارجي.'),
        actions: [
          NativeCompatTextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          NativeCompatFilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminService.instance.deleteSource(source.id);
      SourceCatalogService.instance.invalidate();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('مصادر التطبيقات', style: TextStyle(fontWeight: FontWeight.w900)),
        Text('مكتبة المصادر العامة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actions: [NativeCompatIconButton(onPressed: _load, icon: const Icon(CupertinoIcons.refresh)), const SizedBox(width: 6)],
    ),
    floatingActionButton: NativeIOSButton(title: 'إضافة مصدر', systemImage: 'plus', onPressed: () => _openForm(), prominent: true, width: 145, height: 50),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(CupertinoIcons.square_stack_3d_up_fill, color: Theme.of(context).colorScheme.primary, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('مكتبة مصادر بومة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                const SizedBox(height: 4),
                Text('أي مصدر تحفظه هنا يظهر تلقائياً للمستخدمين داخل الإعدادات ويمكن إضافته بضغطة واحدة.', style: TextStyle(fontSize: 11.5, height: 1.45, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
              ])),
            ]),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.all(42), child: Center(child: CupertinoActivityIndicator(radius: 13)))
          else if (_error != null)
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .08), borderRadius: BorderRadius.circular(18)), child: Text(_error!, style: const TextStyle(color: Colors.red)))
          else if (_sources.isEmpty)
            GlassCard(padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18), child: const Column(children: [Icon(CupertinoIcons.link, size: 30), SizedBox(height: 9), Text('لا توجد مصادر بعد', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('اضغط «إضافة مصدر» لإنشاء أول مصدر.', style: TextStyle(fontSize: 11))]))
          else
            ..._sources.map((source) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _sourceCard(context, source))),
        ],
      ),
    ),
  );

  Widget _sourceCard(BuildContext context, AdminSource source) => GlassCard(
    padding: const EdgeInsets.all(12),
    child: Row(children: [
      Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(17),
        ),
        clipBehavior: Clip.antiAlias,
        child: source.imageUrl.isEmpty
            ? Icon(CupertinoIcons.link, color: Theme.of(context).colorScheme.primary, size: 28)
            : Image.network(source.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(CupertinoIcons.link, color: Theme.of(context).colorScheme.primary, size: 28)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: (source.enabled ? CupertinoColors.systemGreen : CupertinoColors.systemGrey).withValues(alpha: .10), borderRadius: BorderRadius.circular(9)),
            child: Text(source.enabled ? 'ظاهر' : 'مخفي', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: source.enabled ? CupertinoColors.systemGreen : CupertinoColors.systemGrey)),
          ),
        ]),
        const SizedBox(height: 3),
        Text(source.description.isEmpty ? source.url : source.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, height: 1.35, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5))),
      ])),
      PopupMenuButton<String>(
        onSelected: (v) => v == 'edit' ? _openForm(source) : _delete(source),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Row(children: [Icon(CupertinoIcons.pencil), SizedBox(width: 9), Text('تعديل')])),
          PopupMenuItem(value: 'delete', child: Row(children: [Icon(CupertinoIcons.trash, color: Colors.red), SizedBox(width: 9), Text('حذف', style: TextStyle(color: Colors.red))])),
        ],
      ),
    ]),
  );
}

class AdminSourceFormScreen extends StatefulWidget {
  final AdminSource? source;
  const AdminSourceFormScreen({super.key, this.source});
  @override
  State<AdminSourceFormScreen> createState() => _AdminSourceFormScreenState();
}

class _AdminSourceFormScreenState extends State<AdminSourceFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _description;
  late final TextEditingController _order;
  String? _imagePath;
  bool _enabled = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _name = TextEditingController(text: source?.name ?? '');
    _url = TextEditingController(text: source?.url ?? '');
    _description = TextEditingController(text: source?.description ?? '');
    _order = TextEditingController(text: '${source?.sortOrder ?? 0}');
    _enabled = source?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _description.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1200, maxHeight: 1200);
    if (x != null && mounted) setState(() => _imagePath = x.path);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) { setState(() => _error = 'اسم المصدر مطلوب.'); return; }
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _error = 'رابط المصدر غير صالح.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await AdminService.instance.saveSource(
        id: widget.source?.id ?? '',
        name: _name.text.trim(),
        url: _url.text.trim(),
        description: _description.text.trim(),
        enabled: _enabled,
        sortOrder: int.tryParse(_order.text.trim()) ?? 0,
        imagePath: _imagePath,
      );
      SourceCatalogService.instance.invalidate();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentImage = widget.source?.imageUrl ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(widget.source == null ? 'إضافة مصدر' : 'تعديل المصدر', style: const TextStyle(fontWeight: FontWeight.w900)), backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                GestureDetector(
                  onTap: _busy ? null : _pickImage,
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .08), borderRadius: BorderRadius.circular(22), border: Border.all(color: Theme.of(context).dividerColor)),
                    clipBehavior: Clip.antiAlias,
                    child: _imagePath != null
                        ? Image.file(File(_imagePath!), fit: BoxFit.cover)
                        : currentImage.isNotEmpty
                            ? Image.network(currentImage, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.photo_on_rectangle))
                            : const Icon(CupertinoIcons.photo_on_rectangle, size: 28),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('صورة المصدر', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text('اختيارية • يفضّل أن تكون مربعة وواضحة', style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
                  const SizedBox(height: 7),
                  CupertinoButton(padding: EdgeInsets.zero, minSize: 28, onPressed: _busy ? null : _pickImage, child: const Text('اختيار صورة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                ])),
              ]),
              const SizedBox(height: 16),
              CupertinoTextField(controller: _name, placeholder: 'اسم المصدر', padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
              const SizedBox(height: 10),
              Directionality(textDirection: TextDirection.ltr, child: CupertinoTextField(controller: _url, placeholder: 'https://example.com/apps.json', keyboardType: TextInputType.url, autocorrect: false, enableSuggestions: false, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13))),
              const SizedBox(height: 10),
              CupertinoTextField(controller: _description, placeholder: 'وصف المصدر (اختياري)', minLines: 3, maxLines: 5, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
              const SizedBox(height: 10),
              CupertinoTextField(controller: _order, placeholder: 'ترتيب الظهور', keyboardType: TextInputType.number, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('ظاهر في مكتبة المصادر', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('يمكن إخفاؤه مؤقتاً بدون حذفه.'), value: _enabled, onChanged: _busy ? null : (v) => setState(() => _enabled = v)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .08), borderRadius: BorderRadius.circular(13)), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11))),
              ],
              const SizedBox(height: 14),
              NativeIOSButton(title: _busy ? 'جاري الحفظ…' : (widget.source == null ? 'إضافة المصدر' : 'حفظ التعديلات'), systemImage: _busy ? 'hourglass' : 'checkmark.circle.fill', onPressed: _busy ? null : _save, prominent: true, height: 50),
            ]),
          ),
        ],
      ),
    );
  }
}

class AdminAppFormScreen extends StatefulWidget {
  final AdminApp? app;
  final List<String> categories;
  const AdminAppFormScreen({super.key, this.app, required this.categories});
  @override
  State<AdminAppFormScreen> createState() => _AdminAppFormScreenState();
}

class _AdminAppFormScreenState extends State<AdminAppFormScreen> {
  late final TextEditingController _name, _developer, _bundle, _version, _build, _description;
  String? _selectedCategory;
  String? _ipaPath, _iconPath, _extractedIconUrl, _iconSource;
  final SigningService _signing = SigningService();
  final List<String> _existingShots = [];
  int _inspectedSize = 0;
  final List<String> _shots = [];
  bool _busy = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState(); final a = widget.app;
    _name = TextEditingController(text: a?.name ?? ''); _developer = TextEditingController(text: a?.developer ?? ''); _bundle = TextEditingController(text: a?.bundleId ?? ''); _version = TextEditingController(text: a?.version ?? ''); _build = TextEditingController(text: a?.build ?? ''); _description = TextEditingController(text: a?.description ?? '');
    final currentCategory = a?.category.trim() ?? '';
    _selectedCategory = currentCategory.isEmpty ? null : currentCategory;
    _extractedIconUrl = (a?.iconUrl.trim().isNotEmpty ?? false) ? a!.iconUrl : null;
    _existingShots.addAll(a?.screenshots ?? const <String>[]);
  }

  Future<void> _pickIpa() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    final path = r?.files.single.path; if (path == null) return;
    if (!path.toLowerCase().endsWith('.ipa')) { setState(() => _error = 'اختر ملف IPA.'); return; }
    setState(() { _ipaPath = path; _iconPath = null; _extractedIconUrl = null; _iconSource = null; _inspectedSize = 0; _busy = true; _progress = 0; _error = null; });
    try {
      final local = await _signing.inspectIpa(path);
      _name.text = '${local['displayName'] ?? ''}'.trim();
      _bundle.text = '${local['bundleId'] ?? ''}'.trim();
      _version.text = '${local['version'] ?? ''}'.trim();
      _build.text = '${local['build'] ?? ''}'.trim();
      _inspectedSize = await File(path).length();
      final localIcon = '${local['iconPath'] ?? ''}'.trim();
      if (localIcon.isNotEmpty && File(localIcon).existsSync()) {
        _iconPath = localIcon;
        _extractedIconUrl = null;
        _iconSource = 'من ملف IPA';
      } else {
        final meta = await AdminService.instance.inspectIpa(path, onProgress: (p) { if (mounted) setState(() => _progress = p); });
        final m = Map<String, dynamic>.from(meta['meta'] is Map ? meta['meta'] as Map : const {});
        if (_name.text.isEmpty) _name.text = '${m['name'] ?? ''}'.trim();
        if (_bundle.text.isEmpty) _bundle.text = '${m['bundle_id'] ?? ''}'.trim();
        if (_version.text.isEmpty) _version.text = '${m['version'] ?? ''}'.trim();
        if (_build.text.isEmpty) _build.text = '${m['build'] ?? ''}'.trim();
        final extracted = '${m['icon_preview_url'] ?? ''}'.trim();
        _extractedIconUrl = extracted.isEmpty ? null : extracted;
        final source = '${m['icon_source'] ?? ''}'.trim();
        _iconSource = source.isEmpty ? null : source;
      }
      if (_name.text.isEmpty && _bundle.text.isEmpty && _version.text.isEmpty && _build.text.isEmpty) {
        _error = 'تم اختيار IPA، لكن لم يتمكن الخادم من قراءة Info.plist. تأكد أن الملف IPA صالح.';
      }
    } catch (e) { _error = e.toString().replaceFirst('Exception: ', ''); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickIcon() async { final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95); if (x != null) setState(() => _iconPath = x.path); }
  Future<void> _pickShots() async { final xs = await ImagePicker().pickMultiImage(imageQuality: 95); if (xs.isNotEmpty) setState(() { _shots.clear(); _shots.addAll(xs.map((e) => e.path)); }); }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) { setState(() => _error = 'اسم التطبيق مطلوب.'); return; }
    if (widget.app == null && _ipaPath == null) { setState(() => _error = 'اختر ملف IPA أولًا.'); return; }
    if (_selectedCategory == null || _selectedCategory!.trim().isEmpty) { setState(() => _error = 'اختر تصنيف التطبيق.'); return; }
    setState(() { _busy = true; _progress = 0; _error = null; });
    try {
      await AdminService.instance.saveApp(id: widget.app?.id ?? '', name: _name.text.trim(), developer: _developer.text.trim(), description: _description.text.trim(), bundleId: _bundle.text.trim(), version: _version.text.trim(), build: _build.text.trim(), category: _selectedCategory?.trim() ?? '', ipaPath: _ipaPath, iconPath: _iconPath, screenshotPaths: _shots, keepScreenshotUrls: _existingShots, onProgress: (p) { if (mounted) setState(() => _progress = p); });
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() { _busy = false; _error = e.toString().replaceFirst('Exception: ', ''); }); }
  }

  @override
  void dispose() { for (final c in [_name,_developer,_bundle,_version,_build,_description]) { c.dispose(); } super.dispose(); }

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
      _categorySelector(), const SizedBox(height: 10),
      NativeIOSTextField(controller: _description, placeholder: 'الوصف', maxLines: 6, height: 120), const SizedBox(height: 15),
      Row(children: [Expanded(child: _picker('أيقونة التطبيق', _iconPath != null ? 'صورة مخصصة ✓' : (_extractedIconUrl != null ? 'مستخرجة تلقائيًا • اضغط للتغيير' : 'اختيار صورة'), CupertinoIcons.photo_fill, _pickIcon)), const SizedBox(width: 10), Expanded(child: _picker('المعاينات', (_shots.isEmpty && _existingShots.isEmpty) ? 'اختيار صور' : '${_shots.length + _existingShots.length} صور ✓', CupertinoIcons.rectangle_stack_fill, _pickShots))]),
      if (_iconPath != null || _extractedIconUrl != null) ...[
        const SizedBox(height: 12),
        Center(child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(22), child: _iconPath != null
              ? Image.file(File(_iconPath!), width: 104, height: 104, fit: BoxFit.cover)
              : Image.network(_extractedIconUrl!, width: 104, height: 104, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 104, height: 104, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: Theme.of(context).colorScheme.surfaceContainerHighest), child: const Icon(CupertinoIcons.photo, size: 34)))),
          const SizedBox(height: 7),
          Text(_iconPath != null ? 'سيتم استخدام الصورة المخصصة' : 'تم استخراج الأيقونة تلقائيًا${_iconSource == null ? '' : ' • $_iconSource'}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
          if (_inspectedSize > 0) Padding(padding: const EdgeInsets.only(top: 3), child: Text('حجم IPA: ${_formatBytes(_inspectedSize)}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .45)))),
        ])),
      ],
      if (_shots.isNotEmpty || _existingShots.isNotEmpty) ...[const SizedBox(height: 12), SizedBox(height: 150, child: ListView(scrollDirection: Axis.horizontal, children: [
        ..._existingShots.map((url) => Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(url, width: 84, height: 145, fit: BoxFit.cover)), Positioned(top: 5, right: 5, child: InkWell(onTap: () => setState(() => _existingShots.remove(url)), child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 14))))]))),
        ..._shots.map((path) => Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(path), width: 84, height: 145, fit: BoxFit.cover)), Positioned(top: 5, right: 5, child: InkWell(onTap: () => setState(() => _shots.remove(path)), child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 14))))]))),
      ]))],
      if (_error != null) ...[const SizedBox(height: 14), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: Text(_error!, style: const TextStyle(color: Colors.red)))],
      const SizedBox(height: 18),
      NativeIOSButton(title: widget.app == null ? 'رفع وإضافة التطبيق' : 'حفظ التعديلات', systemImage: 'icloud.and.arrow.up.fill', onPressed: _busy ? null : _save, prominent: true, height: 56),
    ]),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  Widget _categorySelector() {
    final categories = <String>[...widget.categories];
    final current = _selectedCategory?.trim();
    if (current != null && current.isNotEmpty && !categories.contains(current)) {
      categories.add(current);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 3, bottom: 8),
          child: Row(
            children: [
              const Text('التصنيف', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
              const SizedBox(width: 7),
              Text('اختر من التصنيفات الموجودة', style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48))),
            ],
          ),
        ),
        if (categories.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('لا توجد تصنيفات حالياً في المكتبة.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          )
        else
          SizedBox(
            height: 45,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsetsDirectional.only(start: 1, end: 1),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final raw = categories[index];
                final selected = _selectedCategory?.trim().toLowerCase() == raw.trim().toLowerCase();
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _busy ? null : () => setState(() => _selectedCategory = raw),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.primary.withValues(alpha: .10),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selected) ...[
                            Icon(CupertinoIcons.checkmark_alt, size: 14, color: Theme.of(context).colorScheme.onPrimary),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _adminCategoryDisplay(raw),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: .76),
                            ),
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
    );
  }

  Widget _field(TextEditingController c, String h) => NativeIOSTextField(controller: c, placeholder: h);
  InputDecoration _dec(String h) => InputDecoration(labelText: h, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none));
  Widget _picker(String t, String s, IconData i, VoidCallback tap) => Material(color: Colors.transparent, child: InkWell(onTap: _busy ? null : tap, borderRadius: BorderRadius.circular(20), child: GlassCard(padding: const EdgeInsets.all(14), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(i, color: Theme.of(context).colorScheme.primary)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w900)), Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5)))])), const Icon(CupertinoIcons.chevron_forward, size: 16)]))));
}
