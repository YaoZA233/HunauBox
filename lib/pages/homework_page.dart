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

class _HomeworkPageState extends ConsumerState<HomeworkPage> {
  int _selectedTab = 0;

  Future<void> _refresh() => ref.read(homeworkProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final homeworkState = ref.watch(homeworkProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('作业'),
        centerTitle: false,
      ),
      body: homeworkState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildErrorState(),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(List<HomeworkModel> homework) {
    final pending = homework
        .where((item) => item.status == HomeworkStatus.pending)
        .toList();
    final completed = homework
        .where((item) => item.status == HomeworkStatus.completed)
        .toList();
    final visibleItems = _selectedTab == 0 ? pending : completed;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _buildOverview(pending.length, completed.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            sliver: SliverToBoxAdapter(child: _buildSegmentedControl()),
          ),
          if (visibleItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(isPending: _selectedTab == 0),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverList.separated(
                itemCount: visibleItems.length,
                itemBuilder: (context, index) => _HomeworkItem(
                  homework: visibleItems[index],
                  onTap: () => _openHomework(visibleItems[index]),
                ),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverview(int pendingCount, int completedCount) {
    final colors = Theme.of(context).colorScheme;
    final total = pendingCount + completedCount;
    final completion = total == 0 ? 0.0 : completedCount / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pendingCount == 0 ? '今天的安排已完成' : '还有 $pendingCount 项任务待处理',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          total == 0 ? '下拉刷新以同步学习通作业' : '已完成 $completedCount / $total',
          style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: completion),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(colors.secondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedControl() {
    final colors = Theme.of(context).colorScheme;
    const labels = ['待完成', '已完成'];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth - 6) / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: _selectedTab * segmentWidth,
                top: 0,
                width: segmentWidth,
                height: 38,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: List.generate(labels.length, (index) {
                  final selected = _selectedTab == index;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _selectedTab = index),
                      child: Center(
                        child: Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({required bool isPending}) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPending ? Icons.task_alt_rounded : Icons.done_all_rounded,
              size: 42,
              color: colors.secondary,
            ),
            const SizedBox(height: 14),
            Text(
              isPending ? '没有待完成的作业' : '暂时没有已完成的作业',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '下拉即可同步最新作业',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 44, color: colors.error),
                    const SizedBox(height: 14),
                    const Text(
                      '作业暂时无法同步',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '请检查登录状态后下拉重试',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHomework(HomeworkModel item) async {
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
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewDetailPage(
          title: '作业详情',
          url: item.dataUrl,
          showWebBack: true,
        ),
      ),
    );
  }
}

class _HomeworkItem extends StatelessWidget {
  final HomeworkModel homework;
  final VoidCallback onTap;

  const _HomeworkItem({required this.homework, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = homework.status == HomeworkStatus.completed;
    final deadline = _deadlineText();
    final urgent = !completed && _isUrgent();
    final accent = completed ? colors.secondary : urgent ? colors.error : colors.primary;

    return Material(
      color: colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      homework.courseName.isEmpty ? '课程作业' : homework.courseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    completed ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    size: 18,
                    color: accent,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                homework.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: completed ? colors.onSurfaceVariant : colors.onSurface,
                  decoration: completed ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 15, color: accent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      deadline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: completed ? colors.onSurfaceVariant : accent,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: colors.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _deadlineText() {
    if (homework.endTime != null) {
      return '截止 ${DateFormat('MM月dd日 HH:mm').format(homework.endTime!)}';
    }
    return homework.rawTimeStr.isNotEmpty ? homework.rawTimeStr : '截止时间待定';
  }

  bool _isUrgent() {
    final deadline = homework.endTime;
    if (deadline == null) return false;
    return deadline.difference(DateTime.now()).inHours <= 24;
  }
}
