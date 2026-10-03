import 'package:flutter/material.dart';
import '../models/leave_models.dart';
import '../services/leave_service.dart';

class LeavePage extends StatefulWidget {
  const LeavePage({super.key});
  @override State<LeavePage> createState() => _LeavePageState();
}
class _LeavePageState extends State<LeavePage> {
  final service = LeaveService(); late Future<List<LeaveRecord>> future; bool ongoing = true;
  @override void initState() { super.initState(); future = service.fetchList(); }
  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('请假申请'), actions: [IconButton(onPressed: () => setState(() => future = service.fetchList()), icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveApplyPage(service: service))).then((_) => setState(() => future = service.fetchList())), icon: const Icon(Icons.edit_calendar_rounded), label: const Text('申请请假')),
      body: FutureBuilder<List<LeaveRecord>>(
        future: future,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return Center(child: Text('加载失败：${s.error}'));
          final list = s.data ?? <LeaveRecord>[];
          return RefreshIndicator(onRefresh: () async => setState(() => future = service.fetchList()), child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 100), children: [_banner(c), const SizedBox(height: 18), if (list.isEmpty) _empty(c) else ...list.map((e) => _card(c, e))]));
        },
      ),
    );
  }
  Widget _banner(ColorScheme c) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(22)), child: Row(children: [Icon(Icons.event_available_rounded, size: 35, color: c.onPrimaryContainer), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('行程有变，提前报备', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.onPrimaryContainer)), const SizedBox(height: 4), Text('填写时间与事由，提交后可随时查看审核进度', style: TextStyle(color: c.onPrimaryContainer.withValues(alpha: .78)))]))]));
  Widget _card(ColorScheme c, LeaveRecord e) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(contentPadding: const EdgeInsets.all(14), leading: CircleAvatar(backgroundColor: c.primaryContainer, child: Icon(Icons.event_note_rounded, color: c.onPrimaryContainer)), title: Row(children: [Expanded(child: Text(e.typeName.isEmpty ? '请假申请' : e.typeName)), Text(e.statusLabel, style: TextStyle(color: c.primary, fontSize: 12))]), subtitle: Padding(padding: const EdgeInsets.only(top: 8), child: Text('${e.startTime}  至  ${e.endTime}\n${e.reason}', maxLines: 3, overflow: TextOverflow.ellipsis)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveDetailPage(record: e, service: service)))));
  Widget _empty(ColorScheme c) => Padding(padding: const EdgeInsets.only(top: 60), child: Column(children: [Icon(Icons.event_note_outlined, size: 52, color: c.outline), const SizedBox(height: 12), const Text('暂无请假记录'), Text('点击右下角开始申请', style: TextStyle(color: c.onSurfaceVariant))]));
}

class LeaveDetailPage extends StatelessWidget {
  final LeaveRecord record; final LeaveService service;
  const LeaveDetailPage({super.key, required this.record, required this.service});
  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(title: const Text('请假详情'), actions: [if (record.canDelete) IconButton(onPressed: () => _delete(context), icon: const Icon(Icons.delete_outline_rounded))]), body: ListView(padding: const EdgeInsets.all(20), children: [Text(record.typeName, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 18), _item(c, '审核状态', record.statusLabel), _item(c, '请假时间', '${record.startTime} 至 ${record.endTime}'), _item(c, '请假时长', record.durationLabel), _item(c, '请假事由', record.reason)]));
  }
  Future<void> _delete(BuildContext context) async { final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('撤销申请？'), content: const Text('撤销后将无法恢复。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('保留')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('撤销'))])); if (ok != true) return; try { await service.delete(record.id); if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已撤销'))); Navigator.pop(context); } } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }
  Widget _item(ColorScheme c, String t, String v) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c.surfaceContainerLow, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(color: c.onSurfaceVariant, fontSize: 12)), const SizedBox(height: 6), Text(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 15, height: 1.4))]));
}

class LeaveApplyPage extends StatefulWidget {
  final LeaveService service; const LeaveApplyPage({super.key, required this.service});
  @override State<LeaveApplyPage> createState() => _LeaveApplyPageState();
}
class _LeaveApplyPageState extends State<LeaveApplyPage> {
  final start = TextEditingController(), end = TextEditingController(), reason = TextEditingController(), phone = TextEditingController(); List<LeaveDictItem> types = []; LeaveDictItem? type; LeaveDuration? duration; bool busy = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final data = await widget.service.fetchTypes(); if (mounted) setState(() { types = data; type = data.isEmpty ? null : data.first; }); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('申请请假')), body: ListView(padding: const EdgeInsets.all(20), children: [Text('安排好行程，再提交申请', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 20), DropdownButtonFormField<LeaveDictItem>(initialValue: type, decoration: const InputDecoration(labelText: '请假类型'), items: types.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(), onChanged: (v) => setState(() => type = v)), const SizedBox(height: 14), TextField(controller: start, readOnly: true, decoration: const InputDecoration(labelText: '开始时间', suffixIcon: Icon(Icons.calendar_month_rounded)), onTap: () => _pick(true)), const SizedBox(height: 14), TextField(controller: end, readOnly: true, decoration: const InputDecoration(labelText: '结束时间', suffixIcon: Icon(Icons.event_rounded)), onTap: () => _pick(false)), if (duration != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('预计时长：${duration!.label}')), const SizedBox(height: 14), TextField(controller: reason, minLines: 4, maxLines: 7, decoration: const InputDecoration(labelText: '请假事由')), const SizedBox(height: 14), TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '紧急联系人电话（选填）')), const SizedBox(height: 26), FilledButton.icon(onPressed: busy ? null : _submit, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded), label: Text(busy ? '正在提交…' : '提交申请'))]));
  }
  Future<void> _pick(bool isStart) async { final now = DateTime.now(); final date = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 365)), initialDate: now); if (date == null || !mounted) return; final time = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (time == null) return; final value = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${time.format(context)}'; setState(() { if (isStart) start.text = value; else end.text = value; }); if (start.text.isNotEmpty && end.text.isNotEmpty) { try { final d = await widget.service.calculate(start.text, end.text); if (mounted) setState(() => duration = d); } catch (_) {} } }
  Future<void> _submit() async { if (type == null || start.text.isEmpty || end.text.isEmpty || reason.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请完整填写类型、时间和事由'))); return; } setState(() => busy = true); try { await widget.service.submit(fields: {'qjlxM.dm': type!.id, 'qjlx': type!.name, 'kssj': start.text, 'jssj': end.text, 'qjsy': reason.text, 'lxrdh': phone.text, 'operationType': 'add'}); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请假申请已提交'))); Navigator.pop(context); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } finally { if (mounted) setState(() => busy = false); } }
}
