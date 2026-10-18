import 'package:flutter/material.dart';

import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../utils/course_color_utils.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';

class SemesterCoursesPage extends StatefulWidget {
  const SemesterCoursesPage({
    super.key,
    required this.courses,
    this.adjustments = const [],
    this.firstWeekMonday,
  });

  final List<CourseModel> courses;
  final List<TimetableAdjustment> adjustments;
  final DateTime? firstWeekMonday;

  @override
  State<SemesterCoursesPage> createState() => _SemesterCoursesPageState();
}

class _SemesterCoursesPageState extends State<SemesterCoursesPage> {
  final _search = TextEditingController();
  late List<MapEntry<String, List<CourseModel>>> _groups;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _groupCourses();
  }

  @override
  void didUpdateWidget(covariant SemesterCoursesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courses != widget.courses) _groupCourses();
  }

  void _groupCourses() {
    final grouped = <String, List<CourseModel>>{};
    for (final course in widget.courses) {
      final name = _value(course.name, '未命名课程');
      (grouped[name] ??= []).add(course);
    }
    _groups = grouped.entries.toList();
    for (final group in _groups) {
      group.value.sort((a, b) {
        final day = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (day != 0) return day;
        return a.startPeriod.compareTo(b.startPeriod);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final groups = _groups
        .where(
          (group) =>
              _query.isEmpty ||
              group.key.toLowerCase().contains(_query) ||
              group.value.any(
                (course) =>
                    course.teacher.toLowerCase().contains(_query) ||
                    course.classroom.toLowerCase().contains(_query),
              ),
        )
        .toList();
    final monday = widget.firstWeekMonday;
    return Scaffold(
      appBar: AppBar(title: const Text('本学期课程')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '共 ${_groups.length} 门课程 · ${widget.courses.length} 条上课安排',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (monday != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '学期起始：${_date(DateCalculator.getWeekMonday(monday, 1))}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: '搜索课程、老师或教室',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.courses.isEmpty
                              ? '导入课表后，可在这里查看本学期全部课程。'
                              : '没有找到相关课程，试试其他课程名、老师或教室。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _courseCard(groups[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courseCard(MapEntry<String, List<CourseModel>> group) {
    final colors = Theme.of(context).colorScheme;
    final courseIds = group.value.map((course) => course.id).toSet();
    final changes =
        widget.adjustments
            .where((change) => courseIds.contains(change.courseId))
            .toList()
          ..sort((a, b) => a.sourceWeek.compareTo(b.sourceWeek));
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 24,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: CourseColorUtils.getColorForCourse(group.key),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            for (final course in group.value) ...[
              const SizedBox(height: 12),
              if (course != group.value.first) ...[
                const Divider(height: 1),
                const SizedBox(height: 12),
              ],
              _info(Icons.schedule_rounded, '时间', _time(course)),
              _info(Icons.date_range_outlined, '周次', _weeks(course)),
              if (widget.firstWeekMonday != null &&
                  WeekParser.parseWeeks(course.weeks).isNotEmpty)
                _info(Icons.event_outlined, '日期', _dateRange(course)),
              _info(
                Icons.person_outline_rounded,
                '老师',
                _value(course.teacher, '暂未提供'),
              ),
              _info(
                Icons.room_outlined,
                '教室',
                _value(course.classroom, '暂未提供'),
              ),
            ],
            if (changes.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '临时安排（${changes.length} 次）',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: colors.primary),
              ),
              for (final change in changes)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _changeText(change),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$label：$value', style: const TextStyle(height: 1.4)),
        ),
      ],
    ),
  );

  String _time(CourseModel course) =>
      '${_day(course.dayOfWeek)} · 第${course.startPeriod}-${course.endPeriod}节 · ${_clockRange(course.startPeriod, course.endPeriod)}';

  String _clockRange(int start, int end) {
    if (start < 1 || end > 12 || start > end) return '时间待确认';
    final from = DateCalculator.getSectionTime(start)['start']!;
    final to = DateCalculator.getSectionTime(end)['end']!;
    String format(TimeOfDay value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '${format(from)}–${format(to)}';
  }

  String _weeks(CourseModel course) {
    final weeks = WeekParser.parseWeeks(course.weeks);
    return weeks.isEmpty
        ? _value(course.weeks, '暂未提供')
        : WeekParser.formatWeeks(weeks);
  }

  String _dateRange(CourseModel course) {
    final weeks = WeekParser.parseWeeks(course.weeks);
    DateTime date(int week) => DateCalculator.calculateDate(
      firstWeekMonday: widget.firstWeekMonday!,
      weekNumber: week,
      dayOfWeek: course.dayOfWeek,
    );
    final start = _date(date(weeks.first));
    return weeks.length == 1
        ? start
        : '$start 至 ${_date(date(weeks.last))}（按上述周次上课）';
  }

  String _changeText(TimetableAdjustment change) {
    String position(int week, int day) {
      final monday = widget.firstWeekMonday;
      return monday == null
          ? '第$week周 ${_day(day)}'
          : '${_date(DateCalculator.calculateDate(firstWeekMonday: monday, weekNumber: week, dayOfWeek: day))}（第$week周 ${_day(day)}）';
    }

    final source = position(change.sourceWeek, change.sourceDay);
    if (change.cancelled) return '$source → 停课';
    return '$source → ${position(change.targetWeek, change.targetDay)}\n'
        '第${change.targetStartPeriod}-${change.targetEndPeriod}节 · ${_clockRange(change.targetStartPeriod, change.targetEndPeriod)}';
  }

  String _day(int day) => day >= 1 && day <= 7
      ? '星期${['一', '二', '三', '四', '五', '六', '日'][day - 1]}'
      : '星期待确认';
  String _date(DateTime date) => '${date.year}年${date.month}月${date.day}日';
  String _value(String value, String fallback) =>
      value.trim().isEmpty ? fallback : value.trim();
}
