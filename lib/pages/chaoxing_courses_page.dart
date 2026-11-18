import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chaoxing_course.dart';
import '../providers/chaoxing_course_provider.dart';
import '../services/app_cookie_manager.dart';
import '../services/chaoxing_course_service.dart';
import '../widgets/campus_loading_mark.dart';
import '../widgets/campus_progress_bar.dart';
import 'webview_detail_page.dart';

class ChaoxingCoursesPage extends ConsumerStatefulWidget {
  const ChaoxingCoursesPage({super.key});

  @override
  ConsumerState<ChaoxingCoursesPage> createState() =>
      _ChaoxingCoursesPageState();
}

class _ChaoxingCoursesPageState extends ConsumerState<ChaoxingCoursesPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _folder;
  List<ChaoxingCourse>? _refreshed;
  bool _refreshing = false;
  String? _refreshError;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final cache = ref.read(chaoxingCacheProvider);
      final fetcher = ref.read(chaoxingCourseFetcherProvider);
      final owner = await cache.account();
      final result = await fetchAndCacheCourses(
        cache,
        fetcher,
      );
      final saved = await cache.read('courses');
      if (owner != await cache.account()) throw StateError('账号已切换');
      if (mounted) {
        setState(() => _refreshed = result);
        if (saved != null) ref.invalidate(chaoxingCoursesProvider);
      }
    } catch (_) {
      if (mounted) {
        final hasPrevious =
            _refreshed != null ||
            ref.read(chaoxingCoursesProvider).valueOrNull != null;
        setState(
          () => _refreshError = hasPrevious
              ? '刷新失败，正在显示上次的课程。'
              : '课程暂时无法同步，请检查网络或登录状态后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openWeb({ChaoxingCourse? course}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebViewDetailPage(
          title: course?.name ?? '学习通',
          url: course?.url ?? ChaoxingCourseService.portalUrl,
          userAgent: ChaoxingCourseService.desktopUserAgent,
          showWebBack: true,
        ),
      ),
    );
    if (!mounted) return;
    await AppCookieManager().syncMultiDomainCookiesFromWebView(null, [
      'https://passport2.chaoxing.com',
      ChaoxingCourseService.portalUrl,
      ChaoxingCourseService.origin,
      'https://mooc1.chaoxing.com',
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chaoxingCoursesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习通课程'),
        actions: [
          IconButton(
            tooltip: '刷新课程',
            onPressed: state.isLoading || _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '打开学习通网页',
            onPressed: () => _openWeb(),
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _refreshed != null
            ? _content(_refreshed!)
            : state.when(
                loading: () => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CampusLoadingMark(size: 36),
                      SizedBox(height: 16),
                      Text('正在同步学习通课程…'),
                    ],
                  ),
                ),
                error: (error, _) => Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _refreshError ??
                              (error is ChaoxingCourseException
                                  ? error.message
                                  : '课程暂时无法同步，请稍后重试'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        if (_refreshing) const CampusLoadingMark(size: 24),
                        FilledButton(
                          onPressed: _refreshing ? null : _refresh,
                          child: const Text('重新同步'),
                        ),
                        TextButton(
                          onPressed: () => _openWeb(),
                          child: const Text('打开学习通 / 登录'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: _content,
              ),
      ),
    );
  }

  Widget _content(List<ChaoxingCourse> courses) {
    final colors = Theme.of(context).colorScheme;
    final folders = courses.map((c) => c.folder).toSet().toList()..sort();
    final selectedFolder = folders.contains(_folder) ? _folder : null;
    final terms = _query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty);
    final visible = courses
        .where(
          (c) =>
              (selectedFolder == null || c.folder == selectedFolder) &&
              terms.every(
                (term) => '${c.name} ${c.teacher} ${c.school} ${c.folder}'
                    .toLowerCase()
                    .contains(term),
              ),
        )
        .toList();
    final knownCourses = courses.where((course) => course.progress != null);
    final finishedJobs = knownCourses.fold<int>(
      0,
      (sum, course) => sum + course.finishedJobs!,
    );
    final totalJobs = knownCourses.fold<int>(
      0,
      (sum, course) => sum + course.totalJobs!,
    );
    final overallProgress = totalJobs == 0 ? null : finishedJobs / totalJobs;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_refreshing) ...[
                    const CampusProgressBar(value: null, minHeight: 2),
                    const SizedBox(height: 12),
                  ],
                  if (_refreshError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _refreshError!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  Text(
                    '我学的课 · ${courses.length} 门',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (_refreshing) ...[
                    const SizedBox(height: 6),
                    Text(
                      '正在同步课程',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (overallProgress != null) ...[
                    const SizedBox(height: 16),
                    _CourseProgressSummary(
                      finished: finishedJobs,
                      total: totalJobs,
                      progress: overallProgress,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: '搜索课程、教师或学校',
                      filled: true,
                      fillColor: colors.surfaceContainerHighest.withValues(
                        alpha: 0.38,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                  if (folders.any((f) => f.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ChoiceChip(
                            label: const Text('全部'),
                            selected: selectedFolder == null,
                            onSelected: (_) => setState(() => _folder = null),
                          ),
                          const SizedBox(width: 8),
                          for (final folder in folders)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(folder.isEmpty ? '未分组' : folder),
                                selected: selectedFolder == folder,
                                onSelected: (_) =>
                                    setState(() => _folder = folder),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    courses.isEmpty ? '暂无课程，下拉刷新或打开学习通确认账号。' : '没有找到匹配的课程',
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) => _CourseRow(
                  course: visible[index],
                  onTap: () => _openWeb(course: visible[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.onTap});
  final ChaoxingCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = course.progress;
    final details = [
      course.teacher,
      course.school,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CourseCover(course: course),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            course.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (course.schedule.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        course.schedule,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    if (progress == null)
                      Text(
                        '任务点进度未知',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '任务点 ${course.finishedJobs}/${course.totalJobs} · ${(progress * 100).floor()}%',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: CampusProgressBar(
                          value: progress,
                          minHeight: 4,
                          semanticsLabel: '任务点完成进度',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseCover extends StatelessWidget {
  const _CourseCover({required this.course});
  final ChaoxingCourse course;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Container(
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book_outlined, color: colors.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 76,
        height: 68,
        child: course.coverUrl.isEmpty
            ? fallback
            : Image.network(
                course.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _CourseProgressSummary extends StatelessWidget {
  const _CourseProgressSummary({
    required this.finished,
    required this.total,
    required this.progress,
  });

  final int finished;
  final int total;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '课程任务点',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '已完成 $finished/$total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: CampusProgressBar(
              value: progress,
              minHeight: 4,
              backgroundColor: colors.surface.withValues(alpha: 0.7),
              color: colors.primary,
              semanticsLabel: '所有课程任务点完成进度',
            ),
          ),
        ],
      ),
    );
  }
}
