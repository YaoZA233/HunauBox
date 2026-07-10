import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/homework_model.dart';
import '../providers/homework_provider.dart';
import '../services/app_cookie_manager.dart';
import 'webview_detail_page.dart';

class HomeworkPage extends ConsumerStatefulWidget {
  const HomeworkPage({super.key});

  @override
  ConsumerState<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends ConsumerState<HomeworkPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 0: 未完成, 1: 已完成, 2: 存档
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeworkState = ref.watch(homeworkProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的作业'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          tabs: const [
            Tab(text: '未完成'),
            Tab(text: '已完成'),
            Tab(text: '存档'),
          ],
        ),
      ),
      body: homeworkState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败: $err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(homeworkProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (list) {
          final pendingList = list.where((e) => e.status == HomeworkStatus.pending).toList();
          final completedList = list.where((e) => e.status == HomeworkStatus.completed).toList();
          final archiveList = list.where((e) => e.status == HomeworkStatus.archived).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildList(pendingList, '没有未完成的作业'),
              _buildList(completedList, '没有已完成的作业'),
              _buildList(archiveList, '存档为空'),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ref.read(homeworkProvider.notifier).refresh();
        },
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        tooltip: '刷新',
        child: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onPrimaryContainer),
      ),
    );
  }

  Widget _buildList(List<HomeworkModel> items, String emptyMsg) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyMsg, style: const TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => ref.read(homeworkProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isCompleted = item.status == HomeworkStatus.completed;
          final isArchived = item.status == HomeworkStatus.archived;
          final titleColor = isCompleted
              ? Theme.of(context).colorScheme.onSurface.withOpacity(0.65)
              : Theme.of(context).colorScheme.onSurface;
          final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(
                item.title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                  decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                  decorationColor: titleColor,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    item.courseName,
                    style: TextStyle(
                      color: subtitleColor.withOpacity(isCompleted ? 0.75 : 1),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.endTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '截止时间: ' + DateFormat('MM-dd HH:mm').format(item.endTime!) + '', 
                      style: TextStyle(
                        color: isCompleted
                            ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)
                            : Theme.of(context).colorScheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                    ),
                  ] else if (item.rawTimeStr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.rawTimeStr, 
                      style: TextStyle(
                        color: isCompleted
                            ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)
                            : Theme.of(context).colorScheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                    ),
                  ],
                  if (isArchived) ...[
                    const SizedBox(height: 4),
                    Text(
                      '已存档',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]
                ],
              ),
              trailing: item.status == HomeworkStatus.pending
                  ? Icon(Icons.hourglass_empty_rounded, color: Colors.orange.shade400)
                  : item.status == HomeworkStatus.completed
                      ? Icon(Icons.check_circle_rounded, color: Colors.green.shade400)
                      : Icon(Icons.archive_rounded, color: Colors.grey.shade400),
                  onTap: () async {
                    if (item.isManual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('手动作业暂不支持跳转学习通')),
                      );
                      return;
                    }

                    if (item.dataUrl.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('未找到可打开的学习通作业链接')),
                      );
                      return;
                    }

                    await AppCookieManager().injectAllChaoxingCookies();

                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WebViewDetailPage(
                          title: '作业详情',
                          url: item.dataUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
            ),
          );
        },
      ),
    );
  }
}
