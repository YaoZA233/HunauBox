import 'package:flutter/material.dart';
import '../models/sunshine_models.dart';
import '../services/sunshine_service.dart';

class SunshinePage extends StatefulWidget {
  const SunshinePage({super.key});
  @override State<SunshinePage> createState() => _SunshinePageState();
}

class _SunshinePageState extends State<SunshinePage> {
  final service = SunshineService();
  late Future<List<SunshineLetter>> future;
  SunshineStatistics? stats;
  @override void initState() { super.initState(); future = _load(); }
  Future<List<SunshineLetter>> _load() async {
    try { stats = await service.fetchStatistics(); } catch (_) {}
    return service.fetchLetters();
  }
  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('阳光服务'), actions: [IconButton(onPressed: () => setState(() => future = _load()), icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SunshineFormPage(service: service))),
        icon: const Icon(Icons.add_rounded), label: const Text('提交诉求'),
      ),
      body: FutureBuilder<List<SunshineLetter>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: FilledButton(onPressed: () => setState(() => future = _load()), child: const Text('重新加载')));
          final list = snapshot.data ?? <SunshineLetter>[];
          return RefreshIndicator(
            onRefresh: () async => setState(() => future = _load()),
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
              _hero(c), const SizedBox(height: 16), _stats(c), const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('我的诉求', style: Theme.of(context).textTheme.titleLarge), Text('${list.length} 条', style: TextStyle(color: c.primary))]),
              const SizedBox(height: 10),
              if (list.isEmpty) _empty(c) else ...list.map((e) => _card(c, e)),
            ]),
          );
        },
      ),
    );
  }
  Widget _hero(ColorScheme c) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(gradient: LinearGradient(colors: [c.primary, c.tertiary]), borderRadius: BorderRadius.circular(24)),
    child: const Row(children: [Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 32), SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('把建议送到校园', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('提交诉求、查询进度，推动校园服务变得更好', style: TextStyle(color: Colors.white70))]))]),
  );
  Widget _stats(ColorScheme c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: c.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
    child: Row(children: [_stat(c, '${stats?.total ?? '—'}', '全部'), _stat(c, '${stats?.processing ?? '—'}', '办理中'), _stat(c, '${stats?.completed ?? '—'}', '已办结')]),
  );
  Widget _stat(ColorScheme c, String value, String label) => Expanded(child: Column(children: [Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.primary)), const SizedBox(height: 4), Text(label, style: TextStyle(color: c.onSurfaceVariant, fontSize: 12))]));
  Widget _card(ColorScheme c, SunshineLetter e) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.all(14), leading: CircleAvatar(backgroundColor: c.primaryContainer, child: Icon(e.status == '2' ? Icons.check_rounded : Icons.pending_actions_rounded, color: c.onPrimaryContainer)),
      title: Text(e.title.isEmpty ? '未命名诉求' : e.title, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('${e.department.isEmpty ? '阳光服务' : e.department} · ${e.date}'), trailing: Text(e.statusLabel, style: TextStyle(color: e.status == '2' ? Colors.green : c.primary, fontSize: 12)),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SunshineDetailPage(service: service, letter: e))),
    ),
  );
  Widget _empty(ColorScheme c) => Padding(padding: const EdgeInsets.only(top: 60), child: Column(children: [Icon(Icons.mark_email_unread_outlined, size: 48, color: c.outline), const SizedBox(height: 12), const Text('还没有诉求记录'), Text('点击右下角提交第一条建议', style: TextStyle(color: c.onSurfaceVariant))]));
}

class SunshineDetailPage extends StatelessWidget {
  final SunshineService service; final SunshineLetter letter;
  const SunshineDetailPage({super.key, required this.service, required this.letter});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('诉求详情')),
    body: FutureBuilder<SunshineTicketDetail>(
      future: service.fetchTicketDetail(letter.id),
      builder: (context, s) {
        if (!s.hasData) return s.hasError ? const Center(child: Text('详情加载失败')) : const Center(child: CircularProgressIndicator());
        final d = s.data!; final c = Theme.of(context).colorScheme;
        return ListView(padding: const EdgeInsets.all(20), children: [Text(d.title, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 16), _info(c, '当前状态', d.statusLabel), _info(c, '受理单位', d.handlingDepartment.isEmpty ? d.expectedDepartment : d.handlingDepartment), _info(c, '提交人', d.submitter), _info(c, '内容', d.content), if (d.remark.isNotEmpty) _info(c, '处理备注', d.remark)]);
      },
    ),
  );
  Widget _info(ColorScheme c, String title, String value) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c.surfaceContainerLow, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: c.onSurfaceVariant, fontSize: 12)), const SizedBox(height: 6), Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 15, height: 1.4))]));
}

class SunshineFormPage extends StatefulWidget {
  final SunshineService service; const SunshineFormPage({super.key, required this.service});
  @override State<SunshineFormPage> createState() => _SunshineFormPageState();
}
class _SunshineFormPageState extends State<SunshineFormPage> {
  final title = TextEditingController(), content = TextEditingController(), phone = TextEditingController(), email = TextEditingController(); SunshineFormData? form; SunshineDepartment? department; bool busy = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final f = await widget.service.fetchForm(); if (mounted) setState(() { form = f; department = f.departments.first; phone.text = f.identity.phone; email.text = f.identity.email; }); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }
  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (form == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: const Text('提交诉求')), body: ListView(padding: const EdgeInsets.all(20), children: [Text('写下你想推动的改变', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 6), Text('我们会将诉求转交给对应单位处理', style: TextStyle(color: c.onSurfaceVariant)), const SizedBox(height: 24), TextField(controller: title, decoration: const InputDecoration(labelText: '诉求标题')), const SizedBox(height: 14), DropdownButtonFormField<SunshineDepartment>(initialValue: department, decoration: const InputDecoration(labelText: '受理单位'), items: form!.departments.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(), onChanged: (v) => setState(() => department = v)), const SizedBox(height: 14), TextField(controller: content, minLines: 5, maxLines: 8, decoration: const InputDecoration(labelText: '具体内容')), const SizedBox(height: 14), TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '联系电话')), const SizedBox(height: 14), TextField(controller: email, decoration: const InputDecoration(labelText: '电子邮箱（选填）')), const SizedBox(height: 26), FilledButton.icon(onPressed: busy ? null : _submit, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded), label: Text(busy ? '正在提交…' : '确认提交'))]));
  }
  Future<void> _submit() async { if (title.text.trim().isEmpty || content.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写标题和具体内容'))); return; } setState(() => busy = true); try { final result = await widget.service.submit(identity: form!.identity, department: department!, type: '2', title: title.text, content: content.text, phone: phone.text, email: email.text, finishTime: ''); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result == 'unknown' ? '已发送，请在列表核对状态' : '诉求提交成功'))); Navigator.pop(context); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } finally { if (mounted) setState(() => busy = false); } }
}
