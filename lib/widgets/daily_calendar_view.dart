import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../services/timetable_adjustment_service.dart';
import '../utils/date_calculator.dart';
import 'app_motion.dart';

class DailyCalendarView extends StatefulWidget {
  const DailyCalendarView({
    super.key,
    required this.courses,
    required this.firstWeekMonday,
    this.adjustments = const [],
    this.onCourseLongPress,
    this.active = true,
    this.initialDate,
    this.now = DateTime.now,
  });

  final List<CourseModel> courses;
  final DateTime firstWeekMonday;
  final List<TimetableAdjustment> adjustments;
  final void Function(CourseModel course, int weekNumber)? onCourseLongPress;
  final bool active;
  final DateTime? initialDate;
  final DateTime Function() now;

  @override
  DailyCalendarViewState createState() => DailyCalendarViewState();
}

class DailyCalendarViewState extends State<DailyCalendarView>
    with WidgetsBindingObserver {
  final _selectedDateKey = GlobalKey();
  final _dateScroll = ScrollController();
  final _courseScroll = ScrollController();
  final _schedule = <DateTime, List<TimetableSlot>>{};
  late DateTime _selectedDate;
  late DateTime _now;
  late bool _followToday;
  Timer? _timer;

  int get currentWeekNumber => DateCalculator.getCurrentWeekNumber(
    widget.firstWeekMonday,
    _selectedDate,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.now();
    _selectedDate = DateUtils.dateOnly(widget.initialDate ?? _now);
    _followToday = DateUtils.isSameDay(_selectedDate, _now);
    _resolveSchedule();
    _scheduleClock();
    _revealSelectedDate();
  }

  @override
  void didUpdateWidget(covariant DailyCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveSchedule();
    _now = widget.now();
    if (_followToday) _selectedDate = DateUtils.dateOnly(_now);
    _scheduleClock();
    if (widget.active && !oldWidget.active) _revealSelectedDate();
  }

  void _resolveSchedule() {
    _schedule.clear();
    for (final slot in TimetableAdjustmentService.slots(
      widget.courses,
      widget.adjustments,
    )) {
      if (slot.cancelled) continue;
      final date = DateUtils.dateOnly(
        DateCalculator.calculateDate(
          firstWeekMonday: widget.firstWeekMonday,
          weekNumber: slot.week,
          dayOfWeek: slot.day,
        ),
      );
      (_schedule[date] ??= []).add(slot);
    }
    for (final slots in _schedule.values) {
      slots.sort((a, b) {
        final start = a.start.compareTo(b.start);
        if (start != 0) return start;
        final end = a.end.compareTo(b.end);
        return end != 0 ? end : a.course.name.compareTo(b.course.name);
      });
    }
  }

  void _scheduleClock() {
    _timer?.cancel();
    if (!widget.active) return;
    // Course boundaries are minute-aligned; also update the date at midnight.
    final delay = 60000 - _now.second * 1000 - _now.millisecond;
    _timer = Timer(Duration(milliseconds: delay), _refreshClock);
  }

  void _refreshClock() {
    if (!mounted) return;
    final previous = _selectedDate;
    setState(() {
      _now = widget.now();
      if (_followToday) _selectedDate = DateUtils.dateOnly(_now);
    });
    if (previous != _selectedDate) {
      _resetCourseScroll();
      _revealSelectedDate();
    }
    _scheduleClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshClock();
    if (state == AppLifecycleState.paused) _timer?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _dateScroll.dispose();
    _courseScroll.dispose();
    super.dispose();
  }

  void jumpToToday() => _selectDate(widget.now());

  void _selectDate(DateTime date) {
    setState(() {
      _now = widget.now();
      _selectedDate = DateUtils.dateOnly(date);
      _followToday = DateUtils.isSameDay(_selectedDate, _now);
    });
    _resetCourseScroll();
    _revealSelectedDate();
  }

  void _resetCourseScroll() {
    if (_courseScroll.hasClients) _courseScroll.jumpTo(0);
  }

  void _revealSelectedDate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _selectedDateKey.currentContext;
      if (!mounted || target == null || !_dateScroll.hasClients) return;
      _dateScroll.position.ensureVisible(
        target.findRenderObject()!,
        alignment: .5,
      );
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      currentDate: widget.now(),
      firstDate: DateTime(math.min(2000, _selectedDate.year)),
      lastDate: DateTime(math.max(2100, _selectedDate.year), 12, 31),
    );
    if (mounted && date != null) _selectDate(date);
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final monday = DateUtils.dateOnly(
      DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day - _selectedDate.weekday + 1,
      ),
    );
    final courses = _schedule[_selectedDate] ?? const <TimetableSlot>[];
    final isToday = DateUtils.isSameDay(_selectedDate, _now);
    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: CustomScrollView(
        controller: _courseScroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一周',
                      onPressed: () => _selectDate(
                        DateTime(
                          _selectedDate.year,
                          _selectedDate.month,
                          _selectedDate.day - 7,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _pickDate,
                        child: Column(
                          children: [
                            Text(
                              _dateLabel(_selectedDate),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              '${currentWeekNumber < 1 ? '学期开始前' : '第$currentWeekNumber周'} · 星期${_weekdays[_selectedDate.weekday - 1]}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '下一周',
                      onPressed: () => _selectDate(
                        DateTime(
                          _selectedDate.year,
                          _selectedDate.month,
                          _selectedDate.day + 7,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final width = math.max(
                      48.0 * scale,
                      (constraints.maxWidth - 48) / 7,
                    );
                    return SingleChildScrollView(
                      controller: _dateScroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          for (var day = 0; day < 7; day++)
                            Padding(
                              padding: EdgeInsets.only(right: day == 6 ? 0 : 4),
                              child: _dateButton(
                                DateTime(
                                  monday.year,
                                  monday.month,
                                  monday.day + day,
                                ),
                                width,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${isToday ? '今日课程' : '当天课程'} · ${courses.length}门',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (courses.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.free_breakfast_outlined,
                      size: 48,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isToday ? '今天没有课程' : '当天没有课程',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('好好安排属于自己的时间', textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList.builder(
                itemCount: courses.length,
                itemBuilder: (context, index) => _courseCard(courses[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateButton(DateTime date, double width) {
    final colors = Theme.of(context).colorScheme;
    final selected = date == _selectedDate;
    final today = DateUtils.isSameDay(date, _now);
    final count = _schedule[date]?.length ?? 0;
    final foreground = selected ? colors.onPrimary : colors.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      onTap: () => _selectDate(date),
      label:
          '${_dateLabel(date)}，星期${_weekdays[date.weekday - 1]}${today ? '，今天' : ''}，${count == 0 ? '无课' : '$count门课程'}',
      excludeSemantics: true,
      child: SizedBox(
        key: selected
            ? _selectedDateKey
            : ValueKey('day-${date.toIso8601String()}'),
        width: width,
        child: Material(
          color: selected ? colors.primary : colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: today && !selected ? colors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: AppPressable(
            onTap: () => _selectDate(date),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Text(
                    _weekdays[date.weekday - 1],
                    style: TextStyle(color: foreground, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    count == 0 ? '休' : '$count课',
                    style: TextStyle(color: foreground, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  TimeOfDay _start(TimetableSlot slot) =>
      DateCalculator.getSectionTime(slot.start)['start']!;
  TimeOfDay _end(TimetableSlot slot) =>
      DateCalculator.getSectionTime(slot.end)['end']!;
  String _time(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  String _period(TimetableSlot slot) =>
      slot.start == slot.end ? '${slot.start}节' : '${slot.start}-${slot.end}节';

  String _status(TimetableSlot slot) {
    DateTime at(TimeOfDay time) => DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      time.hour,
      time.minute,
    );
    if (!_now.isBefore(at(_end(slot)))) return '已结束';
    return _now.isBefore(at(_start(slot))) ? '未开始' : '上课中';
  }

  Widget _courseCard(TimetableSlot slot) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = _status(slot);
    final ended = status == '已结束';
    final accent = ended ? colors.onSurfaceVariant : colors.primary;
    final timeColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _time(_start(slot)),
          style: theme.textTheme.titleLarge?.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _time(_end(slot)),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _period(slot),
          style: theme.textTheme.labelLarge?.copyWith(color: accent),
        ),
      ],
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slot.course.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: ended ? colors.onSurfaceVariant : colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        _info(
          Icons.location_on_outlined,
          '教室：${slot.course.classroom.trim().isEmpty ? '暂未提供' : slot.course.classroom}',
        ),
        const SizedBox(height: 6),
        _info(
          Icons.person_outline_rounded,
          '老师：${slot.course.teacher.trim().isEmpty ? '暂未提供' : slot.course.teacher}',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _badge(
              status,
              status == '上课中'
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              status == '上课中'
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
            if (slot.adjustment != null)
              _badge(
                '已调课',
                colors.secondaryContainer,
                colors.onSecondaryContainer,
              ),
          ],
        ),
      ],
    );
    return Card(
      key: ValueKey('daily-course-${slot.course.id}-${slot.sourceWeek}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: ended ? colors.surfaceContainerLow : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppPressable(
        onTap: () => _showDetail(slot),
        onLongPress: widget.onCourseLongPress == null
            ? null
            : () => widget.onCourseLongPress!(slot.course, slot.sourceWeek),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              if (scale > 1.6 || (constraints.maxWidth < 270 && scale > 1.2)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [timeColumn, const Divider(height: 24), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 78 * scale, child: timeColumn),
                  Container(
                    width: 1,
                    height: 100 * scale,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: colors.outlineVariant,
                  ),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  Widget _badge(String text, Color background, Color foreground) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: foreground)),
  );

  void _showDetail(TimetableSlot slot) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slot.course.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('日期：${_dateLabel(_selectedDate)}'),
              Text(
                '时间：${_time(_start(slot))}–${_time(_end(slot))} · ${_period(slot)}',
              ),
              const SizedBox(height: 12),
              _info(
                Icons.location_on_outlined,
                '教室：${slot.course.classroom.trim().isEmpty ? '暂未提供' : slot.course.classroom}',
              ),
              const SizedBox(height: 8),
              _info(
                Icons.person_outline_rounded,
                '老师：${slot.course.teacher.trim().isEmpty ? '暂未提供' : slot.course.teacher}',
              ),
              if (slot.adjustment != null) ...[
                const SizedBox(height: 12),
                Text(
                  '已调课 · 原第${slot.sourceWeek}周星期${_weekdays[slot.course.dayOfWeek - 1]}',
                ),
                if (slot.adjustment!.note.trim().isNotEmpty)
                  Text('备注：${slot.adjustment!.note}'),
              ],
              if (widget.onCourseLongPress != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onCourseLongPress!(slot.course, slot.sourceWeek);
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('调整这次课程'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
