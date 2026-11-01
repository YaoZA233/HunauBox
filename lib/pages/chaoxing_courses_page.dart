import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chaoxing_course.dart';
import '../providers/chaoxing_course_provider.dart';
import '../services/app_cookie_manager.dart';
import '../services/chaoxing_course_service.dart';
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(chaoxingCoursesProvider);
    try {
      await ref.read(chaoxingCoursesProvider.future);
    } catch (_) {
      // The provider presents the error and retry action.
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
    if (mounted) await _refresh();
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
            onPressed: state.isLoading ? null : _refresh,
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
        child: state.when(
          loading: () => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
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
                    error is ChaoxingCourseException
                        ? error.message
                        : '课程暂时无法同步，请稍后重试',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _refresh, child: const Text('重新同步')),
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
    final folders = courses.map((c) => c.folder).toSet().toList();
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
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '我学的课 · ${courses.length} 门',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '包含课程文件夹中的课程，点击卡片进入学习通。',
                          style: TextStyle(color: colors.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      labelText: '搜索课程、教师或学校',
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
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (folders.any((f) => f.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('全部课程'),
                          selected: selectedFolder == null,
                          onSelected: (_) => setState(() => _folder = null),
                        ),
                        for (final folder in folders)
                          ChoiceChip(
                            label: Text(folder.isEmpty ? '未分组' : folder),
                            selected: selectedFolder == folder,
                            onSelected: (_) => setState(() => _folder = folder),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '显示 ${visible.length} 门课程',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
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
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) => _CourseCard(
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

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onTap});
  final ChaoxingCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = course.progress;
    final imageFallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          color: colors.onSecondaryContainer,
          size: 32,
        ),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 80,
                        height: 64,
                        child: course.coverUrl.isEmpty
                            ? imageFallback
                            : Image.network(
                                course.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => imageFallback,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (course.teacher.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            course.teacher,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (course.school.isNotEmpty || course.folder.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    course.school,
                    course.folder,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
              if (course.schedule.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  course.schedule,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                progress == null
                    ? '暂无任务点进度'
                    : '任务点 ${course.finishedJobs}/${course.totalJobs} · ${(progress * 100).floor()}%',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                  semanticsLabel: '任务点完成进度',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
