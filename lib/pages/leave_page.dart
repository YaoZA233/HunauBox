import 'package:flutter/material.dart';
import '../models/leave_models.dart';
import '../services/leave_service.dart';
import 'leave_apply_page.dart';
export 'leave_apply_page.dart';

class LeavePage extends StatefulWidget {
  final LeaveService? service;
  const LeavePage({super.key, this.service});
  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  late final service = widget.service ?? LeaveService();
  late Future<List<LeaveRecord>> future;
  @override
  void initState() {
    super.initState();
    future = service.fetchList();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('请假申请'),
        actions: [
          IconButton(
            onPressed: () => setState(() => future = service.fetchList()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => LeaveApplyPage(service: service)),
          );
          if (changed == true && mounted) {
            setState(() => future = service.fetchList());
          }
        },
        icon: const Icon(Icons.edit_calendar_rounded),
        label: const Text('申请请假'),
      ),
      body: FutureBuilder<List<LeaveRecord>>(
        future: future,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return Center(child: Text('加载失败：${s.error}'));
          final list = s.data ?? <LeaveRecord>[];
          return RefreshIndicator(
            onRefresh: () async {
              final request = service.fetchList();
              setState(() => future = request);
              await request;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
              children: [
                _banner(c),
                const SizedBox(height: 18),
                if (list.isEmpty)
                  _empty(c)
                else
                  ...list.map((e) => _card(c, e)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _banner(ColorScheme c) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: c.primaryContainer,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Icon(
          Icons.event_available_rounded,
          size: 35,
          color: c.onPrimaryContainer,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '行程有变，提前报备',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: c.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '填写时间与事由，提交后可随时查看审核进度',
                style: TextStyle(
                  color: c.onPrimaryContainer.withValues(alpha: .78),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _card(ColorScheme c, LeaveRecord e) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: CircleAvatar(
        backgroundColor: c.primaryContainer,
        child: Icon(Icons.event_note_rounded, color: c.onPrimaryContainer),
      ),
      title: Row(
        children: [
          Expanded(child: Text(e.typeName.isEmpty ? '请假申请' : e.typeName)),
          Text(e.statusLabel, style: TextStyle(color: c.primary, fontSize: 12)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '${e.startTime}  至  ${e.endTime}\n${e.reason}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => LeaveDetailPage(record: e, service: service),
          ),
        );
        if (changed == true && mounted) {
          setState(() => future = service.fetchList());
        }
      },
    ),
  );
  Widget _empty(ColorScheme c) => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(
      children: [
        Icon(Icons.event_note_outlined, size: 52, color: c.outline),
        const SizedBox(height: 12),
        const Text('暂无请假记录'),
        Text('点击右下角开始申请', style: TextStyle(color: c.onSurfaceVariant)),
      ],
    ),
  );
}

class LeaveDetailPage extends StatefulWidget {
  final LeaveRecord record;
  final LeaveService service;
  const LeaveDetailPage({
    super.key,
    required this.record,
    required this.service,
  });
  @override
  State<LeaveDetailPage> createState() => _LeaveDetailPageState();
}

class _LeaveDetailPageState extends State<LeaveDetailPage> {
  late Future<LeaveDetail> _future;
  bool _deleting = false;
  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchRecord(widget.record.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final record = widget.record;
    return Scaffold(
      appBar: AppBar(
        title: const Text('请假详情'),
        actions: [
          if (record.canDelete)
            IconButton(
              tooltip: '撤销申请',
              onPressed: _deleting ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: FutureBuilder<LeaveDetail>(
        future: _future,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('详情加载失败：${s.error}'),
                    TextButton(
                      onPressed: () => setState(
                        () => _future = widget.service.fetchRecord(record.id),
                      ),
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }
          final detail = s.data!;
          String value(String key, [String fallback = '']) {
            final v = detail.get(key);
            return v.isEmpty ? fallback : v;
          }

          final rows = <String, String>{
            '审核状态': record.statusLabel,
            '请假类型': value('qjlx', record.typeName),
            '开始时间': value('kssj', record.startTime),
            '结束时间': value('jssj', record.endTime),
            '请假时长':
                '${value('ts', '${record.days}')}天 ${value('hour', '${record.hours}')}小时',
            '请假事由': value('qjsy', record.reason),
            '紧急联系人': value('lxr'),
            '紧急联系人电话': value('lxrdh'),
            '同行人员': value('txry'),
            '是否离校': value('lxInd') == '1' ? '是' : '否',
            '离校去向': value('lxqx', value('lxqx1')),
            '离校详细地址': value('lxMdd'),
            '是否返宿': value('huisusheInd') == '1' ? '是' : '否',
            '离校备注': value('lxBz'),
            '是否出市': value('chushiInd') == '1' ? '是' : '否',
            '是否出省': value('chushengInd') == '1' ? '是' : '否',
            '实践指导老师': value('sjhdlsM'),
            '证明附件': value('fileList'),
          };
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final row in rows.entries)
                if (row.value.isNotEmpty) _item(c, row.key, row.value),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销申请？'),
        content: const Text('撤销后将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.service.delete(widget.record.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _item(ColorScheme c, String t, String v) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t, style: TextStyle(color: c.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 6),
        Text(v, style: const TextStyle(fontSize: 15, height: 1.4)),
      ],
    ),
  );
}
