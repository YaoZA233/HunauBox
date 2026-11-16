import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/homework_model.dart';
import '../providers/homework_provider.dart';
import '../services/app_cookie_manager.dart';
import '../widgets/campus_loading_mark.dart';
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
        loading: () => const Center(child: CampusLoadingMark(size: 38)),
        error: (_, _) => _buildErrorState(),
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
    final allArchived = homework
        .where((item) => item.status == HomeworkStatus.archived)
        .toList();
    final filteredHomework = _filterHomework(homework);
    final pending = filteredHomework
        .where((item) => item.status == HomeworkStatus.pending)
        .toList();
    final completed = filteredHomework
        .where((item) => item.status == HomeworkStatus.completed)
        .toList();
    final archived = filteredHomework
        .where((item) => item.status == HomeworkStatus.archived)
        .toList();
    final visibleItems = switch (_selectedTab) {
      0 => pending,
      1 => completed,
      _ => archived,
    };

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            sliver: SliverToBoxAdapter(
              child: _buildOverview(
                allPending.length,
                allCompleted.length,
                archivedCount: allArchived.length,
                matchingCount: filteredHomework.length,
                totalCount: homework.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _buildSearchField()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            sliver: SliverToBoxAdapter(
              child: _buildSegmentedControl(
                pending.length,
                completed.length,
                archived.length,
              ),
            ),
          ),
          if (visibleItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(
                selectedTab: _selectedTab,
                hasSearch: _searchQuery.trim().isNotEmpty,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverList.builder(
                itemCount: visibleItems.length,
                itemBuilder: (context, index) => _HomeworkItem(
                  homework: visibleItems[index],
                  onTap: () => _openHomework(visibleItems[index]),
                ),
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
    required int archivedCount,
    required int matchingCount,
    required int totalCount,
  }) {
    final colors = Theme.of(context).colorScheme;
    final activeTotal = pendingCount + completedCount;
    final completion = activeTotal == 0 ? 0.0 : completedCount / activeTotal;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('作业', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 13),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$totalCount',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('项记录', style: TextStyle(color: colors.onSurfaceVariant)),
            ),
            const Spacer(),
            Text(
              '$pendingCount 项待完成',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: completion),
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 850),
                  curve: Curves.easeInOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(completion * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _searchQuery.trim().isNotEmpty
              ? '当前匹配 $matchingCount 项'
              : '已完成 $completedCount · 已归档 $archivedCount',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
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
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildSegmentedControl(
    int pendingCount,
    int completedCount,
    int archivedCount,
  ) {
    final colors = Theme.of(context).colorScheme;
    return SegmentedButton<int>(
      segments: [
        ButtonSegment(value: 0, label: Text('待处理 $pendingCount')),
        ButtonSegment(value: 1, label: Text('已完成 $completedCount')),
        ButtonSegment(value: 2, label: Text('已归档 $archivedCount')),
      ],
      selected: {_selectedTab},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      onSelectionChanged: (selection) =>
          setState(() => _selectedTab = selection.first),
    );
  }

  Widget _buildEmptyState({
    required int selectedTab,
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
              selectedTab == 0
                  ? Icons.task_alt_rounded
                  : selectedTab == 1
                  ? Icons.done_all_rounded
                  : Icons.inventory_2_outlined,
              size: 42,
              color: colors.primary,
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? '没有找到匹配的作业'
                  : selectedTab == 0
                  ? '没有待处理作业'
                  : selectedTab == 1
                  ? '没有已完成作业'
                  : '没有已归档作业',
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
    final archived = homework.status == HomeworkStatus.archived;
    final deadline = _deadlineText();
    final urgent = !completed && !archived && _isUrgent();
    final accent = completed
        ? colors.primary
        : archived
        ? colors.outline
        : urgent
        ? colors.error
        : colors.tertiary;
    final status = completed ? '已完成' : archived ? '已归档' : urgent ? '即将截止' : '待处理';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Icon(
                  completed
                      ? Icons.check_circle_outline
                      : archived
                      ? Icons.inventory_2_outlined
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: accent,
                ),
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
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (homework.isManual) ...[
                          const SizedBox(width: 8),
                          Text(
                            '手动',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      homework.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: completed || archived
                            ? colors.onSurfaceVariant
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '$status · $deadline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right, size: 18, color: colors.outline),
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
