import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';

/// One original occurrence, with its current temporary position resolved.
class TimetableSlot {
  const TimetableSlot(this.course, this.sourceWeek, this.adjustment);

  final CourseModel course;
  final int sourceWeek;
  final TimetableAdjustment? adjustment;
  int get week => adjustment?.targetWeek ?? sourceWeek;
  int get day => adjustment?.targetDay ?? course.dayOfWeek;
  int get start => adjustment?.targetStartPeriod ?? course.startPeriod;
  int get end => adjustment?.targetEndPeriod ?? course.endPeriod;
  bool get cancelled => adjustment?.cancelled ?? false;
}

class TimetableAdjustmentService {
  const TimetableAdjustmentService._();

  static List<TimetableSlot> slots(
    List<CourseModel> courses,
    List<TimetableAdjustment> adjustments,
  ) => [
    for (final course in courses)
      for (final week in WeekParser.parseWeeks(course.weeks))
        TimetableSlot(
          course,
          week,
          adjustments
              .where(
                (item) => item.courseId == course.id && item.sourceWeek == week,
              )
              .lastOrNull,
        ),
  ];

  static List<TimetableAdjustment> forDates({
    required List<CourseModel> courses,
    required List<TimetableAdjustment> adjustments,
    required DateTime firstWeekMonday,
    required DateTime sourceStart,
    DateTime? sourceEnd,
    DateTime? targetDate,
    bool cancelled = false,
  }) {
    final start = DateTime(
      sourceStart.year,
      sourceStart.month,
      sourceStart.day,
    );
    final last = sourceEnd ?? sourceStart;
    final end = DateTime(last.year, last.month, last.day);
    if (end.isBefore(start)) throw ArgumentError('结束日期不能早于开始日期');
    if (!cancelled && (targetDate == null || start != end)) {
      throw ArgumentError('整天调课需要一个来源日期和一个目标日期');
    }
    final targetWeek = targetDate == null
        ? null
        : DateCalculator.getCurrentWeekNumber(firstWeekMonday, targetDate);
    if (targetWeek != null && targetWeek < 1) {
      throw ArgumentError('目标日期不能早于学期开始日期');
    }
    return [
      for (final slot in slots(courses, adjustments))
        if (!slot.cancelled &&
            _within(
              DateCalculator.calculateDate(
                firstWeekMonday: firstWeekMonday,
                weekNumber: slot.week,
                dayOfWeek: slot.day,
              ),
              start,
              end,
            ))
          _override(
            slot,
            targetWeek: targetWeek ?? slot.week,
            targetDay: targetDate?.weekday ?? slot.day,
            start: slot.start,
            end: slot.end,
            cancelled: cancelled,
          ),
    ];
  }

  static bool _within(DateTime date, DateTime start, DateTime end) =>
      !date.isBefore(start) && !date.isAfter(end);

  static List<TimetableAdjustment> forWeeks({
    required CourseModel course,
    required Set<int> sourceWeeks,
    required int targetDay,
    required int start,
    required int end,
    int? targetWeek,
    bool cancelled = false,
  }) {
    _validatePosition(targetDay, start, end);
    final available = WeekParser.parseWeeks(course.weeks);
    if (sourceWeeks.isEmpty || !sourceWeeks.every(available.contains)) {
      throw ArgumentError('请选择课程已有的上课周次');
    }
    if (targetWeek != null && (targetWeek < 1 || sourceWeeks.length != 1)) {
      throw ArgumentError('跨周调课只能指定一个来源周次');
    }
    final weeks = sourceWeeks.toList()..sort();
    return [
      for (final week in weeks)
        _override(
          TimetableSlot(course, week, null),
          targetWeek: targetWeek ?? week,
          targetDay: targetDay,
          start: start,
          end: end,
          cancelled: cancelled,
        ),
    ];
  }

  static List<CourseModel> matchingCourses(
    List<CourseModel> courses,
    CourseModel anchor,
  ) => courses
      .where(
        (course) =>
            course.dayOfWeek == anchor.dayOfWeek &&
            course.startPeriod == anchor.startPeriod &&
            course.endPeriod == anchor.endPeriod,
      )
      .toList();

  static List<TimetableAdjustment> forCourses({
    required List<CourseModel> courses,
    required CourseModel anchor,
    required Set<String> selectedIds,
    required int targetDay,
    required int start,
    required int end,
    bool cancelled = false,
  }) {
    final matching = matchingCourses(courses, anchor);
    if (selectedIds.isEmpty ||
        !selectedIds.every((id) => matching.any((c) => c.id == id))) {
      throw ArgumentError('请选择同一星期、相同节次范围内的课程');
    }
    return [
      for (final course in matching.where((c) => selectedIds.contains(c.id)))
        ...forWeeks(
          course: course,
          sourceWeeks: WeekParser.parseWeeks(course.weeks).toSet(),
          targetDay: targetDay,
          start: start,
          end: end,
          cancelled: cancelled,
        ),
    ];
  }

  static List<TimetableAdjustment> merge(
    List<TimetableAdjustment> existing,
    List<TimetableAdjustment> additions,
  ) {
    final keys = additions.map((a) => (a.courseId, a.sourceWeek)).toSet();
    return [
      ...existing.where((a) => !keys.contains((a.courseId, a.sourceWeek))),
      ...additions,
    ];
  }

  static void _validatePosition(int day, int start, int end) {
    if (day < 1 || day > 7 || start < 1 || end > 12 || start > end) {
      throw ArgumentError('星期或节次范围无效');
    }
  }

  static TimetableAdjustment _override(
    TimetableSlot slot, {
    required int targetWeek,
    required int targetDay,
    required int start,
    required int end,
    required bool cancelled,
  }) => TimetableAdjustment(
    id: '${slot.course.id}_${slot.sourceWeek}',
    courseId: slot.course.id,
    sourceWeek: slot.sourceWeek,
    sourceDay: slot.course.dayOfWeek,
    targetWeek: targetWeek,
    targetDay: targetDay,
    targetStartPeriod: start,
    targetEndPeriod: end,
    cancelled: cancelled,
  );
}
