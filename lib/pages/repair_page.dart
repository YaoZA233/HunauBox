import 'package:flutter/material.dart';
import '../models/repair_models.dart';
import '../services/repair_service.dart';
import 'repair_form_page.dart';
export 'repair_form_page.dart';

class RepairPage extends StatefulWidget {
  final RepairService? service;
  const RepairPage({super.key, this.service});
  @override
  State<RepairPage> createState() => _RepairPageState();
}

class _RepairPageState extends State<RepairPage> {
  late final service = widget.service ?? RepairService();
  late Future<List<RepairOrder>> future;
  bool ongoing = true;
  @override
  void initState() {
    super.initState();
    future = service.fetchOrders();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('报修平台'),
        actions: [
          IconButton(
            onPressed: () =>
                setState(() => future = service.fetchOrders(ongoing: ongoing)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newRepair,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建报修'),
      ),
      body: FutureBuilder<List<RepairOrder>>(
        future: future,
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
                    Text('${s.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(
                        () => future = service.fetchOrders(ongoing: ongoing),
                      ),
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }
          final list = s.data ?? <RepairOrder>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
            children: [
              _header(c),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('处理中')),
                  ButtonSegment(value: false, label: Text('已完成')),
                ],
                selected: {ongoing},
                onSelectionChanged: (v) => setState(() {
                  ongoing = v.first;
                  future = service.fetchOrders(ongoing: ongoing);
                }),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty) _empty(c) else ...list.map((e) => _card(c, e)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _newRepair() async {
    final catalog = await showModalBottomSheet<RepairCatalog>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('选择报修类型', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ...RepairService.catalogs.map(
              (item) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: item.color.withValues(alpha: .14),
                    child: Icon(item.icon, color: item.color),
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.subtitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, item),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (catalog != null && mounted) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RepairFormPage(service: service, catalog: catalog),
        ),
      );
      if (changed == true && mounted) {
        setState(() {
          ongoing = true;
          future = service.fetchOrders();
        });
      }
    }
  }

  Widget _header(ColorScheme c) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [c.secondary, c.primary]),
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Row(
      children: [
        Icon(Icons.build_circle_rounded, color: Colors.white, size: 32),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '校园问题，一键报修',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 5),
              Text('进度全程可查，服务更及时', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _card(ColorScheme c, RepairOrder e) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: CircleAvatar(
        backgroundColor: c.primaryContainer,
        child: Icon(Icons.handyman_outlined, color: c.onPrimaryContainer),
      ),
      title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${e.catalog.isEmpty ? '校园服务' : e.catalog}\n${e.description}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        e.status.isEmpty ? '处理中' : e.status,
        style: TextStyle(color: c.primary, fontSize: 12),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RepairDetailPage(order: e, service: service),
        ),
      ),
    ),
  );
  Widget _empty(ColorScheme c) => Padding(
    padding: const EdgeInsets.only(top: 50),
    child: Column(
      children: [
        Icon(Icons.checklist_rounded, size: 52, color: c.outline),
        const SizedBox(height: 12),
        Text(ongoing ? '暂无进行中的工单' : '暂无已完成工单'),
        Text('在功能页选择报修类型即可提交', style: TextStyle(color: c.onSurfaceVariant)),
      ],
    ),
  );
}

class RepairDetailPage extends StatefulWidget {
  final RepairOrder order;
  final RepairService service;
  const RepairDetailPage({
    super.key,
    required this.order,
    required this.service,
  });
  @override
  State<RepairDetailPage> createState() => _RepairDetailPageState();
}

class _RepairDetailPageState extends State<RepairDetailPage> {
  late Future<RepairOrder> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchDetail(widget.order);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('工单详情')),
      body: FutureBuilder<RepairOrder>(
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
                        () =>
                            _future = widget.service.fetchDetail(widget.order),
                      ),
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }
          final order = s.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                order.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              _item(c, '工单编号', order.code),
              _item(c, '当前状态', order.status),
              _item(c, '服务类型', order.catalog),
              _item(c, '问题描述', order.description),
              _item(c, '补充说明 / 地点', order.supplement),
              _item(c, '处理部门', order.department),
              _item(c, '处理人', order.handler),
              _item(c, '联系电话', order.phone),
            ],
          );
        },
      ),
    );
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
        Text(
          v.isEmpty ? '—' : v,
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
      ],
    ),
  );
}
