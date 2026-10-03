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
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(homeworkProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final homeworkState = ref.watch(homeworkProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('作业'),
      ),
      body: homeworkState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildErrorState(),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(List<HomeworkModel> homework) {
    final allPending = homework
        .where((item) => item.status == HomeworkStatus.pending)
        .toList();
    final allCompleted = homework
        .where((item) => item.status == HomeworkStatus.completed)
        .toList();
    final filteredHomework = _filterHomework(homework);
    final pending = filteredHomework
        .where((item) => item.status == HomeworkStatus.pending)
        .toList();
    final completed = filteredHomework
        .where((item) => item.status == HomeworkStatus.completed)
        .toList();
    final visibleItems = _selectedTab == 0 ? pending : completed;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            sliver: SliverToBoxAdapter(
              child: _buildOverview(
                allPending.length,
                allCompleted.length,
                matchingCount: filteredHomework.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _buildSearchField()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            sliver: SliverToBoxAdapter(child: _buildSegmentedControl()),
          ),
          if (visibleItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(
                isPending: _selectedTab == 0,
                hasSearch: _searchQuery.trim().isNotEmpty,
              ),
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
                separatorBuilder: (_, __) => const SizedBox(height: 12),
              ),
            ),
        ],
      ),
    );
  }

  List<HomeworkModel> _filterHomework(List<HomeworkModel> homework) {
    final terms = _searchQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return homework;

    return homework.where((item) {
      final searchable = [
        item.courseName,
        item.title,
        item.remarks,
        item.rawTimeStr,
        if (item.endTime != null)
          DateFormat('yyyy年MM月dd日 HH:mm').format(item.endTime!),
      ].join(' ').toLowerCase();
      return terms.every((term) => searchable.contains(term));
    }).toList();
  }

  Widget _buildOverview(
    int pendingCount,
    int completedCount, {
    required int matchingCount,
  }) {
    final colors = Theme.of(context).colorScheme;
    final total = pendingCount + completedCount;
    final completion = total == 0 ? 0.0 : completedCount / total;
    final hasSearch = _searchQuery.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [colors.primary, Color.lerp(colors.primary, colors.tertiary, .62)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: .22), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本周学习节奏', style: TextStyle(color: colors.onPrimary.withValues(alpha: .78), fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  hasSearch ? '找到 $matchingCount 项相关作业' : pendingCount == 0 ? '安排已清空' : '还有 $pendingCount 项待处理',
                  style: TextStyle(color: colors.onPrimary, fontSize: 24, height: 1.12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  hasSearch ? '可按课程名、标题或备注继续筛选' : total == 0 ? '下拉刷新以同步学习通作业' : '已完成 $completedCount / $total',
                  style: TextStyle(color: colors.onPrimary.withValues(alpha: .8), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: completion, strokeWidth: 7, backgroundColor: colors.onPrimary.withValues(alpha: .2), valueColor: AlwaysStoppedAnimation(colors.onPrimary)),
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .94),
                    shape: BoxShape.circle,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${(completion * 100).round()}%',
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索课程、作业或备注',
        prefixIcon: const Icon(Icons.search_rounded, size: 21),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildSegmentedControl() {
    final colors = Theme.of(context).colorScheme;
    const labels = ['待处理', '已完成'];
    return Row(
      children: List.generate(labels.length, (index) {
        final selected = _selectedTab == index;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 0 ? 8 : 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _selectedTab = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? colors.onSurface
                      : colors.surfaceContainerHighest.withValues(alpha: .62),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? colors.surface : colors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildEmptyState({
    required bool isPending,
    required bool hasSearch,
  }) {
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
              color: colors.primary,
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? '没有找到匹配的作业'
                  : isPending
                  ? '没有待完成的作业'
                  : '暂时没有已完成的作业',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch ? '换个关键词试试' : '下拉即可同步最新作业',
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
    final accent = completed ? colors.primary : urgent ? colors.error : colors.tertiary;

    return Material(
      color: colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: .8)),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.045),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 66,
                margin: const EdgeInsets.only(right: 13),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(99)),
              ),
              Expanded(
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
                            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (homework.isManual)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(99)),
                            child: Text('手动', style: TextStyle(color: colors.onSecondaryContainer, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      homework.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, height: 1.28, fontWeight: FontWeight.w800, color: completed ? colors.onSurfaceVariant : colors.onSurface, decoration: completed ? TextDecoration.lineThrough : null),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(completed ? Icons.check_circle_outline_rounded : Icons.schedule_rounded, size: 16, color: accent),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            deadline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: completed ? colors.onSurfaceVariant : accent),
                          ),
                        ),
                        const Icon(Icons.arrow_outward_rounded, size: 17),
                      ],
                    ),
                  ],
                ),
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
