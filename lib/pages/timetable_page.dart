import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../services/course_notification_service.dart';
import '../services/timetable_adjustment_service.dart';
import '../services/timetable_storage.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';
import '../utils/ics_parser.dart';
import '../utils/ics_generator.dart';
import '../widgets/download_timetable_screen.dart';
import '../widgets/empty_timetable_state.dart';
import '../widgets/weekly_calendar_view.dart';
import '../widgets/daily_calendar_view.dart';
import '../widgets/app_motion.dart';
import '../widgets/timetable_adjustment_form.dart';
import 'agent_page.dart';
import 'semester_courses_page.dart';

enum _TimetableAction {
  semesterCourses,
  adjustment,
  today,
  importTimetable,
  exportIcs,
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, this.storage});

  final TimetableStorage? storage;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  final GlobalKey<WeeklyCalendarViewState> _weeklyKey = GlobalKey();
  final GlobalKey<DailyCalendarViewState> _dailyKey = GlobalKey();
  bool _dailyView = false;
  late final _storage = widget.storage ?? TimetableStorage();

  List<CourseModel> _courses = [];
  List<TimetableAdjustment> _adjustments = [];
  DateTime? _firstWeekMonday;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLocalTimetable();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTimetable = _courses.isNotEmpty && _firstWeekMonday != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的课表'),
        actions: [
          PopupMenuButton<_TimetableAction>(
            tooltip: '课表功能',
            enabled: !_isLoading,
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: _handleAction,
            itemBuilder: (_) => [
              _menuItem(
                _TimetableAction.semesterCourses,
                Icons.library_books_outlined,
                '本学期课程',
                enabled: _courses.isNotEmpty,
              ),
              _menuItem(
                _TimetableAction.adjustment,
                Icons.swap_horiz_rounded,
                '临时调课',
                enabled: hasTimetable,
              ),
              _menuItem(
                _TimetableAction.today,
                Icons.today_outlined,
                _dailyView ? '回到今天' : '回到本周',
                enabled: hasTimetable,
              ),
              const PopupMenuDivider(),
              _menuItem(
                _TimetableAction.importTimetable,
                Icons.download_outlined,
                '导入课表',
              ),
              _menuItem(
                _TimetableAction.exportIcs,
                Icons.ios_share_outlined,
                '导出 ICS',
                enabled: hasTimetable,
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (hasTimetable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.calendar_view_week_outlined),
                    label: Text('周视图'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.view_agenda_outlined),
                    label: Text('日视图'),
                  ),
                ],
                selected: {_dailyView},
                onSelectionChanged: (selection) =>
                    setState(() => _dailyView = selection.single),
              ),
            ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),
          Expanded(
            child: _courses.isEmpty || _firstWeekMonday == null
                ? EmptyTimetableState(onDownload: _openDownload)
                : AppMotionIndexedStack(
                    index: _dailyView ? 1 : 0,
                    children: [
                      WeeklyCalendarView(
                        key: _weeklyKey,
                        courses: _courses,
                        firstWeekMonday: _firstWeekMonday!,
                        adjustments: _adjustments,
                        onCourseLongPress: _openAdjustmentModesForCourse,
                      ),
                      DailyCalendarView(
                        key: _dailyKey,
                        courses: _courses,
                        firstWeekMonday: _firstWeekMonday!,
                        adjustments: _adjustments,
                        active: _dailyView,
                        onCourseLongPress: _openAdjustmentModesForCourse,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_TimetableAction> _menuItem(
    _TimetableAction action,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => PopupMenuItem(
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );

  void _handleAction(_TimetableAction action) {
    switch (action) {
      case _TimetableAction.semesterCourses:
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SemesterCoursesPage(
              courses: _courses,
              adjustments: _adjustments,
              firstWeekMonday: _firstWeekMonday,
            ),
          ),
        );
      case _TimetableAction.adjustment:
        _openAdjustmentModes();
      case _TimetableAction.today:
        _handleTodayClick();
      case _TimetableAction.importTimetable:
        _openDownload();
      case _TimetableAction.exportIcs:
        _exportIcs();
    }
  }

  void _handleTodayClick() {
    if (_dailyView) {
      _dailyKey.currentState?.jumpToToday();
    } else {
      _weeklyKey.currentState?.jumpToToday();
    }
  }

  Future<void> _loadLocalTimetable() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storage = _storage;
      final hasTimetable = await storage.hasLocalTimetable();

      if (hasTimetable) {
        final icsContent = await storage.readTimetable();
        final metadata = await storage.readMetadata();

        if (icsContent != null) {
          final storedCourses = await storage.readCourseList();
          final courses = storedCourses.isEmpty
              ? IcsParser.parse(icsContent)
              : storedCourses;
          final adjustments = await storage.readAdjustments();
          DateTime? firstWeekMonday;
          if (metadata != null && metadata['firstWeekMonday'] != null) {
            firstWeekMonday = DateTime.parse(
              metadata['firstWeekMonday'] as String,
            );
          }

          if (!mounted) return;
          setState(() {
            _courses = courses;
            _adjustments = adjustments;
            _firstWeekMonday = firstWeekMonday;
            _isLoading = false;
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openDownload() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await Navigator.of(context).push<TimetableImportResult>(
      MaterialPageRoute(builder: (_) => const DownloadTimetableScreen()),
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _courses = result.courses;
        _adjustments = [];
        _firstWeekMonday = result.firstWeekMonday;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportIcs() async {
    final firstWeekMonday = _firstWeekMonday;
    if (_courses.isEmpty || firstWeekMonday == null) return;

    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/hunau_timetable.ics');
      final ics = IcsGenerator.generate(_courses, firstWeekMonday);
      await file.writeAsString(ics, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/calendar')],
          subject: '湖南农业大学课表',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出课表失败：$e')));
    }
  }

  void _openAdjustmentModes() {
    _showAdjustmentModes();
  }

  void _openAdjustmentModesForCourse(CourseModel course, int weekNumber) {
    _showAdjustmentModes(course: course, weekNumber: weekNumber);
  }

  Future<void> _showAdjustmentModes({
    CourseModel? course,
    int? weekNumber,
  }) async {
    final selected = await showModalBottomSheet<AdjustmentMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SingleChildScrollView(
          child: _AdjustmentModeSheet(course: course),
        ),
      ),
    );
    if (!mounted || selected == null) return;

    if (selected == AdjustmentMode.ai) {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const AgentPage()));
      if (mounted) await _loadLocalTimetable();
      return;
    }

    var selectedCourse = _courses
        .where((item) => item.id == course?.id)
        .firstOrNull;
    if (selected != AdjustmentMode.date && selectedCourse == null) {
      selectedCourse = await _pickCourse();
      if (!mounted || selectedCourse == null) return;
    }

    final suggestedWeek =
        weekNumber ??
        (_dailyView
            ? _dailyKey.currentState?.currentWeekNumber
            : _weeklyKey.currentState?.currentWeekNumber) ??
        DateCalculator.getCurrentWeekNumber(_firstWeekMonday!).clamp(1, 20);
    final availableWeeks = selectedCourse == null
        ? <int>[]
        : WeekParser.parseWeeks(selectedCourse.weeks);
    final currentWeek = availableWeeks.contains(suggestedWeek)
        ? suggestedWeek
        : (availableWeeks.firstOrNull ?? suggestedWeek);
    await _openAdjustmentForm(selected, selectedCourse, currentWeek);
  }

  Future<CourseModel?> _pickCourse() {
    return showModalBottomSheet<CourseModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: _courses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = _courses[index];
                return ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '周${item.dayOfWeek} · 第${item.periods}节 · ${item.classroom}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAdjustmentForm(
    AdjustmentMode mode,
    CourseModel? course,
    int sourceWeek,
  ) async {
    final additions = await showModalBottomSheet<List<TimetableAdjustment>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TimetableAdjustmentForm(
        mode: mode,
        courses: _courses,
        adjustments: _adjustments,
        firstWeekMonday: _firstWeekMonday!,
        initialWeek: sourceWeek,
        course: course,
      ),
    );
    if (!mounted || additions == null || additions.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final latest = await _storage.readAdjustments();
      final merged = TimetableAdjustmentService.merge(latest, additions);
      await _storage.saveAdjustments(merged);
      if (!mounted) return;
      setState(() => _adjustments = merged);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            additions.every((a) => a.cancelled)
                ? '已将 ${additions.length} 次上课安排标记为停课'
                : '已保存 ${additions.length} 次临时调课',
          ),
        ),
      );
      try {
        await CourseNotificationService.instance.rescheduleIfEnabled();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('调课已保存，课程提醒更新失败，请在设置中重试')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存调课失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _AdjustmentModeSheet extends StatelessWidget {
  const _AdjustmentModeSheet({this.course});

  final CourseModel? course;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final modes = [
      (
        AdjustmentMode.ai,
        Icons.auto_awesome_rounded,
        'AI 智能调课',
        '粘贴通知或口述安排，快速整理调课与放假',
      ),
      (
        AdjustmentMode.date,
        Icons.event_repeat_rounded,
        '日期时间调课',
        '某一天调到另一天，或这几天不上课',
      ),
      (
        AdjustmentMode.singleWeek,
        Icons.calendar_today_rounded,
        '单周次调课',
        '只改变一门课的某一周，其它周次不动',
      ),
      (
        AdjustmentMode.batchWeeks,
        Icons.view_week_rounded,
        '批量周次调课',
        '一门课的多个周次改到同一星期和节次',
      ),
      (
        AdjustmentMode.batchCourses,
        Icons.library_books_rounded,
        '批量课程调课',
        '同一时间段的多门课一起调整，周次保留',
      ),
    ];
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '临时调课',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '选择方式',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              course == null ? '按日期调整整天安排，或选择课程与周次。' : '长按课程卡片进入时，已自动带入当前课程。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ...modes.map(
              (item) => _modeTile(context, item.$1, item.$2, item.$3, item.$4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext context,
    AdjustmentMode mode,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: colors.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.pop(context, mode),
    );
  }
}
