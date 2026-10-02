import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../services/timetable_storage.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';
import '../utils/ics_parser.dart';
import '../utils/ics_generator.dart';
import '../widgets/download_timetable_screen.dart';
import '../widgets/empty_timetable_state.dart';
import '../widgets/weekly_calendar_view.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  final GlobalKey<WeeklyCalendarViewState> _weeklyKey = GlobalKey();

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的课表'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _openDownload,
            icon: const Icon(Icons.download_outlined),
            tooltip: '导入课表',
          ),
          IconButton(
            onPressed:
                _isLoading || _courses.isEmpty || _firstWeekMonday == null
                ? null
                : _exportIcs,
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: '导出 ICS',
          ),
          IconButton(
            onPressed: _isLoading ? null : _handleTodayClick,
            icon: const Icon(Icons.today_outlined),
          ),
          IconButton(
            onPressed: _isLoading || _courses.isEmpty || _firstWeekMonday == null
                ? null
                : _openAdjustmentModes,
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: '临时调课',
          ),
        ],
      ),
      body: Column(
        children: [
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
                : WeeklyCalendarView(
                    key: _weeklyKey,
                    courses: _courses,
                    firstWeekMonday: _firstWeekMonday!,
                    adjustments: _adjustments,
                    onCourseLongPress: _openAdjustmentModesForCourse,
                  ),
          ),
        ],
      ),
    );
  }

  void _handleTodayClick() {
    _weeklyKey.currentState?.jumpToToday();
  }

  Future<void> _loadLocalTimetable() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storage = TimetableStorage();
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

          setState(() {
            _courses = courses;
            _adjustments = adjustments;
            _firstWeekMonday = firstWeekMonday;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
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
    final selected = await showModalBottomSheet<_AdjustmentMode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdjustmentModeSheet(course: course),
    );
    if (!mounted || selected == null) return;

    if (selected == _AdjustmentMode.ai) {
      _showInfo('AI 智能调课', '把通知文字粘贴进来，后续可由 AI 帮你解析调课与放假安排。');
      return;
    }

    var selectedCourse = course;
    if (selectedCourse == null) {
      selectedCourse = await _pickCourse();
      if (!mounted || selectedCourse == null) return;
    }

    final suggestedWeek = weekNumber ??
        DateCalculator.getCurrentWeekNumber(_firstWeekMonday!).clamp(1, 20);
    final availableWeeks = WeekParser.parseWeeks(selectedCourse.weeks);
    final currentWeek = availableWeeks.contains(suggestedWeek)
        ? suggestedWeek
        : (availableWeeks.firstOrNull ?? suggestedWeek);
    await _openAdjustmentForm(
      selected,
      selectedCourse,
      currentWeek,
    );
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
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = _courses[index];
                return ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('周${item.dayOfWeek} · 第${item.periods}节 · ${item.classroom}'),
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
    _AdjustmentMode mode,
    CourseModel course,
    int sourceWeek,
  ) async {
    var targetDay = course.dayOfWeek;
    var targetWeek = sourceWeek;
    var targetStart = course.startPeriod;
    var targetEnd = course.endPeriod;
    var cancelled = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = Theme.of(context).colorScheme;
            final title = switch (mode) {
              _AdjustmentMode.date => '日期时间调课',
              _AdjustmentMode.singleWeek => '单周次调课',
              _AdjustmentMode.batchWeeks => '批量周次调课',
              _AdjustmentMode.batchCourses => '批量课程调课',
              _AdjustmentMode.ai => 'AI 智能调课',
            };
            final applies = switch (mode) {
              _AdjustmentMode.batchWeeks => '将应用到 ${WeekParser.parseWeeks(course.weeks).length} 个已有周次',
              _AdjustmentMode.batchCourses => '将应用到同一星期、相同开始节次的课程',
              _ => '只改变临时安排，原课表仍可随时恢复',
            };
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(course.name, style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(applies, style: TextStyle(color: colors.onSurfaceVariant)),
                      const SizedBox(height: 20),
                      if (mode == _AdjustmentMode.date || mode == _AdjustmentMode.singleWeek) ...[
                        _selector<int>(
                          label: '目标周次',
                          value: targetWeek,
                          values: List.generate(20, (index) => index + 1),
                          text: (value) => '第$value周',
                          onChanged: (value) => setSheetState(() => targetWeek = value),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _selector<int>(
                        label: '目标星期',
                        value: targetDay,
                        values: List.generate(7, (index) => index + 1),
                        text: (value) => '星期${['一', '二', '三', '四', '五', '六', '日'][value - 1]}',
                        onChanged: (value) => setSheetState(() => targetDay = value),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _selector<int>(
                            label: '开始节次', value: targetStart,
                            values: List.generate(12, (index) => index + 1),
                            text: (value) => '第$value节',
                            onChanged: (value) => setSheetState(() {
                              targetStart = value;
                              if (targetEnd < value) targetEnd = value;
                            }),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _selector<int>(
                            label: '结束节次', value: targetEnd,
                            values: List.generate(12, (index) => index + 1),
                            text: (value) => '第$value节',
                            onChanged: (value) => setSheetState(() => targetEnd = value),
                          )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('本次不上课'),
                        subtitle: const Text('保留记录，但在对应周次隐藏这节课'),
                        value: cancelled,
                        onChanged: (value) => setSheetState(() => cancelled = value),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('保存临时安排'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted || saved != true) return;

    final weeks = switch (mode) {
      _AdjustmentMode.batchWeeks => WeekParser.parseWeeks(course.weeks),
      _ => [sourceWeek],
    };
    final targets = mode == _AdjustmentMode.batchCourses
        ? _courses.where((item) => item.dayOfWeek == course.dayOfWeek && item.startPeriod == course.startPeriod).toList()
        : [course];
    final additions = <TimetableAdjustment>[];
    for (final item in targets) {
      final itemWeeks = mode == _AdjustmentMode.batchWeeks || mode == _AdjustmentMode.batchCourses
          ? WeekParser.parseWeeks(item.weeks)
          : weeks;
      for (final week in itemWeeks) {
        additions.add(TimetableAdjustment(
          id: '${item.id}_$week',
          courseId: item.id,
          sourceWeek: week,
          sourceDay: item.dayOfWeek,
          targetWeek: mode == _AdjustmentMode.batchWeeks || mode == _AdjustmentMode.batchCourses ? week : targetWeek,
          targetDay: targetDay,
          targetStartPeriod: targetStart,
          targetEndPeriod: targetEnd,
          cancelled: cancelled,
        ));
      }
    }

    final replaced = _adjustments.where((existing) => !additions.any(
      (item) => item.courseId == existing.courseId && item.sourceWeek == existing.sourceWeek,
    )).toList();
    setState(() => _adjustments = [...replaced, ...additions]);
    await TimetableStorage().saveAdjustments(_adjustments);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cancelled ? '已标记为不上课' : '临时调课已保存')),
      );
    }
  }

  Widget _selector<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) text,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: values.map((item) => DropdownMenuItem(value: item, child: Text(text(item)))).toList(),
      onChanged: (next) { if (next != null) onChanged(next); },
    );
  }

  void _showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
      ),
    );
  }
}

enum _AdjustmentMode { ai, date, singleWeek, batchWeeks, batchCourses }

class _AdjustmentModeSheet extends StatelessWidget {
  const _AdjustmentModeSheet({this.course});

  final CourseModel? course;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final modes = [
      (_AdjustmentMode.ai, Icons.auto_awesome_rounded, 'AI 智能调课', '粘贴通知或口述安排，快速整理调课与放假'),
      (_AdjustmentMode.date, Icons.event_repeat_rounded, '日期时间调课', '某一天调到另一天，或这几天不上课'),
      (_AdjustmentMode.singleWeek, Icons.calendar_today_rounded, '单周次调课', '只改变一门课的某一周，其它周次不动'),
      (_AdjustmentMode.batchWeeks, Icons.view_week_rounded, '批量周次调课', '一门课的多个周次改到同一星期和节次'),
      (_AdjustmentMode.batchCourses, Icons.library_books_rounded, '批量课程调课', '同一时间段的多门课一起调整，周次保留'),
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
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: colors.outlineVariant, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 20),
            Text('临时调课', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('选择方式', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              course == null ? '先选择一种调整方式，再指定课程。' : '长按课程卡片进入时，已自动带入当前课程。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ...modes.map((item) => _modeTile(context, item.$1, item.$2, item.$3, item.$4)),
          ],
        ),
      ),
    );
  }

  Widget _modeTile(BuildContext context, _AdjustmentMode mode, IconData icon, String title, String subtitle) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: colors.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.pop(context, mode),
    );
  }
}
