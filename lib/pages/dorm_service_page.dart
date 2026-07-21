import 'package:flutter/material.dart';

import '../models/app_constants.dart';
import '../services/dorm_service.dart';
import 'webview_detail_page.dart';

class DormServicePage extends StatefulWidget {
  const DormServicePage({super.key});

  @override
  State<DormServicePage> createState() => _DormServicePageState();
}

class _DormServicePageState extends State<DormServicePage> {
  final DormService _service = DormService();
  late Future<DormInfo> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadInitialInfo();
  }

  Future<DormInfo> _loadInitialInfo() async {
    final cachedInfo = await _service.loadCachedDormInfo();
    return cachedInfo ?? _service.fetchDormInfo();
  }

  Future<void> _refresh() async {
    final nextFuture = _service.fetchDormInfo();
    setState(() {
      _future = nextFuture;
    });
    try {
      await nextFuture;
    } catch (_) {}
  }

  void _openWebFallback() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WebViewDetailPage(
          title: '学生公寓',
          url: AppConstants.dormServiceUrl,
          showWebBack: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学生公寓'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              _refresh();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<DormInfo>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return _buildError(snapshot.error?.toString() ?? '加载失败');
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _buildHeader(snapshot.data!),
                const SizedBox(height: 20),
                _InfoTile(
                  icon: Icons.apartment_outlined,
                  title: '宿舍楼',
                  value: snapshot.data!.dormBuilding,
                ),
                _InfoTile(
                  icon: Icons.layers_outlined,
                  title: '楼层',
                  value: snapshot.data!.floor,
                ),
                _InfoTile(
                  icon: Icons.meeting_room_outlined,
                  title: '房间',
                  value: snapshot.data!.room,
                ),
                _InfoTile(
                  icon: Icons.bed_outlined,
                  title: '床号',
                  value: snapshot.data!.bed,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _openWebFallback,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('打开网页核对'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(DormInfo info) {
    final fetchedAt =
        '${info.fetchedAt.hour.toString().padLeft(2, '0')}:${info.fetchedAt.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.home_work_outlined,
            size: 36,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '住宿信息',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '缓存时间 $fetchedAt',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                _refresh();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _openWebFallback,
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('打开网页核对'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = value.trim();
    final displayValue = normalizedValue.isEmpty
        ? '未获取到'
        : title == '床号' && RegExp(r'^\d+$').hasMatch(normalizedValue)
        ? '$normalizedValue号床'
        : normalizedValue;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Flexible(
            child: Text(
              displayValue,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: value.trim().isEmpty
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
