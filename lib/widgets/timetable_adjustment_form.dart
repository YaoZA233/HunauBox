import 'package:flutter/material.dart';

import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../services/timetable_adjustment_service.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';

enum AdjustmentMode {
  ai('AI 智能调课'),
  date('日期时间调课'),
  singleWeek('单周次调课'),
  batchWeeks('批量周次调课'),
  batchCourses('批量课程调课');

  const AdjustmentMode(this.title);
  final String title;
}

class TimetableAdjustmentForm extends StatefulWidget {
  const TimetableAdjustmentForm({
    super.key,
    required this.mode,
    required this.courses,
    required this.adjustments,
    required this.firstWeekMonday,
    required this.initialWeek,
    this.course,
  });

  final AdjustmentMode mode;
  final List<CourseModel> courses;
  final List<TimetableAdjustment> adjustments;
  final DateTime firstWeekMonday;
  final int initialWeek;
  final CourseModel? course;

  @override
  State<TimetableAdjustmentForm> createState() =>
      _TimetableAdjustmentFormState();
}

class _TimetableAdjustmentFormState extends State<TimetableAdjustmentForm> {
  late int _sourceWeek;
  late int _targetWeek;
  late int _targetDay;
  late int _start;
  late int _end;
  late DateTime _sourceDate;
  late DateTime _endDate;
  late DateTime _targetDate;
  late Set<int> _selectedWeeks;
  late Set<String> _selectedCourses;
  bool _cancelled = false;

  CourseModel get _course => widget.course!;
  List<int> get _weeks => WeekParser.parseWeeks(_course.weeks);
  List<CourseModel> get _matching =>
      TimetableAdjustmentService.matchingCourses(widget.courses, _course);
  int get _maxWeek => [
    20,
    widget.initialWeek,
    for (final c in widget.courses) ...WeekParser.parseWeeks(c.weeks),
    for (final a in widget.adjustments) a.targetWeek,
  ].reduce((a, b) => a > b ? a : b);
  DateTime get _firstDate =>
      DateCalculator.getWeekMonday(widget.firstWeekMonday, 1);
  DateTime get _lastDate =>
      DateCalculator.getWeekSunday(widget.firstWeekMonday, _maxWeek);

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    _sourceWeek = widget.initialWeek;
    if (course != null && !_weeks.contains(_sourceWeek)) {
      _sourceWeek = _weeks.first;
    }
    _targetWeek = _sourceWeek;
    _targetDay = course?.dayOfWeek ?? DateTime.now().weekday;
    _start = course?.startPeriod ?? 1;
    _end = course?.endPeriod ?? 2;
    if (course != null) _loadSourcePosition();
    _sourceDate = DateCalculator.calculateDate(
      firstWeekMonday: widget.firstWeekMonday,
      weekNumber: _targetWeek,
      dayOfWeek: _targetDay,
    );
    _endDate = _sourceDate;
    _targetDate = _sourceDate;
    _selectedWeeks = course == null ? {} : _weeks.toSet();
    _selectedCourses = course == null ? {} : _matching.map((c) => c.id).toSet();
  }

  void _loadSourcePosition() {
    final adjustment = widget.adjustments
        .where((a) => a.courseId == _course.id && a.sourceWeek == _sourceWeek)
        .lastOrNull;
    _targetWeek = adjustment?.targetWeek ?? _sourceWeek;
    _targetDay = adjustment?.targetDay ?? _course.dayOfWeek;
    _start = adjustment?.targetStartPeriod ?? _course.startPeriod;
    _end = adjustment?.targetEndPeriod ?? _course.endPeriod;
  }

  List<TimetableAdjustment> _preview() => switch (widget.mode) {
    AdjustmentMode.date => TimetableAdjustmentService.forDates(
      courses: widget.courses,
      adjustments: widget.adjustments,
      firstWeekMonday: widget.firstWeekMonday,
      sourceStart: _sourceDate,
      sourceEnd: _cancelled ? _endDate : null,
      targetDate: _cancelled ? null : _targetDate,
      cancelled: _cancelled,
    ),
    AdjustmentMode.singleWeek => TimetableAdjustmentService.forWeeks(
      course: _course,
      sourceWeeks: {_sourceWeek},
      targetWeek: _targetWeek,
      targetDay: _targetDay,
      start: _start,
      end: _end,
      cancelled: _cancelled,
    ),
    AdjustmentMode.batchWeeks =>
      _selectedWeeks.isEmpty
          ? []
          : TimetableAdjustmentService.forWeeks(
              course: _course,
              sourceWeeks: _selectedWeeks,
              targetDay: _targetDay,
              start: _start,
              end: _end,
              cancelled: _cancelled,
            ),
    AdjustmentMode.batchCourses =>
      _selectedCourses.isEmpty
          ? []
          : TimetableAdjustmentService.forCourses(
              courses: widget.courses,
              anchor: _course,
              selectedIds: _selectedCourses,
              targetDay: _targetDay,
              start: _start,
              end: _end,
              cancelled: _cancelled,
            ),
    AdjustmentMode.ai => [],
  };

  @override
  Widget build(BuildContext context) {
    final additions = _preview();
    final colors = Theme.of(context).colorScheme;
    final description = switch (widget.mode) {
      AdjustmentMode.date => '整天调课会迁移来源日期的全部课程，保留各课节次；停课可以选择连续多天。',
      AdjustmentMode.singleWeek => '选择这门课的来源周次，只修改该次上课安排，其他周次保持不变。',
      AdjustmentMode.batchWeeks => '勾选要修改的多个周次，统一修改星期和节次，每次上课仍留在原周次。',
      AdjustmentMode.batchCourses => '勾选同一星期、相同节次范围内的课程，统一修改时间，各门课原有周次保留。',
      AdjustmentMode.ai => '',
    };
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.mode.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (widget.mode == AdjustmentMode.date)
                ..._dateFields()
              else
                ..._courseFields(),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.mode == AdjustmentMode.date ? '这些日期不上课' : '所选安排不上课',
                ),
                subtitle: const Text('停课范围以所选日期、周次或课程为准'),
                value: _cancelled,
                onChanged: (value) => setState(() => _cancelled = value),
              ),
              const SizedBox(height: 12),
              Text(
                '将影响 ${additions.length} 次上课安排',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (additions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('当前范围内没有可调整的课程，请重新选择。'),
                ),
              for (final entry in _previewEntries(additions))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    entry,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: additions.isEmpty
                      ? null
                      : () => Navigator.pop(context, additions),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('保存临时安排'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _dateFields() => [
    _dateButton('来源日期', _sourceDate, (date) {
      _sourceDate = date;
      if (_endDate.isBefore(date)) _endDate = date;
    }),
    const SizedBox(height: 12),
    if (_cancelled)
      _dateButton(
        '停课结束日期',
        _endDate,
        (date) => _endDate = date,
        firstDate: _sourceDate,
      )
    else
      _dateButton('目标日期', _targetDate, (date) => _targetDate = date),
  ];

  List<Widget> _courseFields() => [
    Text(
      _course.name,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    const SizedBox(height: 12),
    if (widget.mode == AdjustmentMode.singleWeek) ...[
      _selector('来源周次', _sourceWeek, _weeks, (v) => '第$v周', (v) {
        _sourceWeek = v;
        _loadSourcePosition();
      }),
      const SizedBox(height: 12),
    ],
    if (widget.mode == AdjustmentMode.batchWeeks) ...[
      const Text('选择要调整的周次'),
      Wrap(
        spacing: 8,
        children: [
          for (final week in _weeks)
            FilterChip(
              label: Text('第$week周'),
              selected: _selectedWeeks.contains(week),
              onSelected: (value) => setState(() {
                if (value) {
                  _selectedWeeks.add(week);
                } else {
                  _selectedWeeks.remove(week);
                }
              }),
            ),
        ],
      ),
      TextButton(
        onPressed: () => setState(() {
          _selectedWeeks = _selectedWeeks.length == _weeks.length
              ? {}
              : _weeks.toSet();
        }),
        child: Text(_selectedWeeks.length == _weeks.length ? '取消全选周次' : '全选周次'),
      ),
    ],
    if (widget.mode == AdjustmentMode.batchCourses) ...[
      Text(
        '同一时间段：${_day(_course.dayOfWeek)} 第${_course.startPeriod}-${_course.endPeriod}节',
      ),
      for (final course in _matching)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(course.name),
          subtitle: Text(
            '${WeekParser.formatWeeks(WeekParser.parseWeeks(course.weeks))} · ${course.classroom}',
          ),
          value: _selectedCourses.contains(course.id),
          onChanged: (value) => setState(() {
            if (value == true) {
              _selectedCourses.add(course.id);
            } else {
              _selectedCourses.remove(course.id);
            }
          }),
        ),
    ],
    if (!_cancelled) ...[
      if (widget.mode == AdjustmentMode.singleWeek) ...[
        _selector(
          '目标周次',
          _targetWeek,
          List.generate(_maxWeek, (i) => i + 1),
          (v) => '第$v周',
          (v) => _targetWeek = v,
        ),
        const SizedBox(height: 12),
      ],
      _selector(
        '目标星期',
        _targetDay,
        List.generate(7, (i) => i + 1),
        _day,
        (v) => _targetDay = v,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _selector(
              '开始节次',
              _start,
              List.generate(12, (i) => i + 1),
              (v) => '第$v节',
              (v) {
                _start = v;
                if (_end < v) _end = v;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _selector(
              '结束节次',
              _end,
              List.generate(13 - _start, (i) => _start + i),
              (v) => '第$v节',
              (v) => _end = v,
            ),
          ),
        ],
      ),
    ],
  ];

  Widget _selector(
    String label,
    int value,
    List<int> values,
    String Function(int) text,
    ValueChanged<int> change,
  ) => DropdownButtonFormField<int>(
    key: ValueKey((label, value)),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final item in values)
        DropdownMenuItem(value: item, child: Text(text(item))),
    ],
    onChanged: (v) {
      if (v != null) setState(() => change(v));
    },
  );

  Widget _dateButton(
    String label,
    DateTime date,
    ValueChanged<DateTime> change, {
    DateTime? firstDate,
  }) => OutlinedButton.icon(
    icon: const Icon(Icons.calendar_month_outlined),
    label: Text('$label：${_dateText(date)}'),
    onPressed: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: firstDate ?? _firstDate,
        lastDate: _lastDate,
      );
      if (mounted && picked != null) {
        setState(() => change(picked));
      }
    },
  );

  List<String> _previewEntries(List<TimetableAdjustment> additions) {
    final courses = {for (final c in widget.courses) c.id: c};
    if (widget.mode == AdjustmentMode.date) {
      final slots = {
        for (final slot in TimetableAdjustmentService.slots(
          widget.courses,
          widget.adjustments,
        ))
          (slot.course.id, slot.sourceWeek): slot,
      };
      return [
        for (final a in additions)
          '${courses[a.courseId]!.name} · ${_dateText(DateCalculator.calculateDate(firstWeekMonday: widget.firstWeekMonday, weekNumber: slots[(a.courseId, a.sourceWeek)]!.week, dayOfWeek: slots[(a.courseId, a.sourceWeek)]!.day))}'
              ' → ${a.cancelled ? '停课' : _dateText(_targetDate)} · 第${a.targetStartPeriod}-${a.targetEndPeriod}节',
      ];
    }
    return [
      for (final id in additions.map((a) => a.courseId).toSet())
        '${courses[id]!.name} · ${WeekParser.formatWeeks(additions.where((a) => a.courseId == id).map((a) => a.sourceWeek).toList())}'
            ' → ${_cancelled ? '停课' : '${widget.mode == AdjustmentMode.singleWeek ? '第$_targetWeek周 ' : ''}${_day(_targetDay)} 第$_start-$_end节'}',
    ];
  }

  String _day(int day) => '星期${['一', '二', '三', '四', '五', '六', '日'][day - 1]}';
  String _dateText(DateTime date) => '${date.year}年${date.month}月${date.day}日';
}
