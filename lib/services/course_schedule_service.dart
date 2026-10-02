import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';

class CourseOccurrence {
  const CourseOccurrence({
    required this.course,
    required this.start,
    required this.end,
  });

  final CourseModel course;
  final DateTime start;
  final DateTime end;
}

class CourseScheduleService {
  const CourseScheduleService._();

  static List<CourseOccurrence> upcomingOccurrences({
    required List<CourseModel> courses,
    required DateTime firstWeekMonday,
    required DateTime from,
    List<TimetableAdjustment> adjustments = const [],
    int? limit,
  }) {
    if (courses.isEmpty) return const [];

    final normalizedMonday = DateTime(
      firstWeekMonday.year,
      firstWeekMonday.month,
      firstWeekMonday.day,
    ).subtract(Duration(days: firstWeekMonday.weekday - DateTime.monday));
    final occurrences = <CourseOccurrence>[];

    for (final course in courses) {
      for (final week in WeekParser.parseWeeks(course.weeks)) {
        final adjustment = adjustments.where((item) => item.courseId == course.id && item.sourceWeek == week).firstOrNull;
        if (adjustment?.cancelled == true || (adjustment != null && adjustment.targetWeek != week)) continue;
        final scheduledCourse = adjustment == null ? course : course.copyWith(
          dayOfWeek: adjustment.targetDay,
          startPeriod: adjustment.targetStartPeriod,
          endPeriod: adjustment.targetEndPeriod,
          periods: '${adjustment.targetStartPeriod}-${adjustment.targetEndPeriod}',
        );
        final date = DateCalculator.calculateDate(
          firstWeekMonday: normalizedMonday,
          weekNumber: week,
          dayOfWeek: scheduledCourse.dayOfWeek,
        );
        final startTime = DateCalculator.getSectionTime(scheduledCourse.startPeriod)['start']!;
        final endTime = DateCalculator.getSectionTime(scheduledCourse.endPeriod)['end']!;
        final start = DateTime(date.year, date.month, date.day, startTime.hour, startTime.minute);
        final end = DateTime(date.year, date.month, date.day, endTime.hour, endTime.minute);
        if (!end.isBefore(from)) {
          occurrences.add(CourseOccurrence(course: scheduledCourse, start: start, end: end));
        }
      }
    }

    for (final adjustment in adjustments.where((item) => item.targetWeek != item.sourceWeek && !item.cancelled)) {
      final course = courses.where((item) => item.id == adjustment.courseId).firstOrNull;
      if (course == null) continue;
      final date = DateCalculator.calculateDate(firstWeekMonday: normalizedMonday, weekNumber: adjustment.targetWeek, dayOfWeek: adjustment.targetDay);
      final startTime = DateCalculator.getSectionTime(adjustment.targetStartPeriod)['start']!;
      final endTime = DateCalculator.getSectionTime(adjustment.targetEndPeriod)['end']!;
      final start = DateTime(date.year, date.month, date.day, startTime.hour, startTime.minute);
      final end = DateTime(date.year, date.month, date.day, endTime.hour, endTime.minute);
      if (!end.isBefore(from)) {
        occurrences.add(CourseOccurrence(course: course.copyWith(dayOfWeek: adjustment.targetDay, startPeriod: adjustment.targetStartPeriod, endPeriod: adjustment.targetEndPeriod, periods: '${adjustment.targetStartPeriod}-${adjustment.targetEndPeriod}'), start: start, end: end));
      }
    }

    occurrences.sort((a, b) => a.start.compareTo(b.start));
    return limit == null ? occurrences : occurrences.take(limit).toList();
  }

  static ({CourseOccurrence? current, CourseOccurrence? next}) currentAndNext({
    required List<CourseModel> courses,
    required DateTime? firstWeekMonday,
    required DateTime now,
    List<TimetableAdjustment> adjustments = const [],
  }) {
    if (firstWeekMonday == null) return (current: null, next: null);

    final occurrences = upcomingOccurrences(
      courses: courses,
      firstWeekMonday: firstWeekMonday,
      from: now,
      adjustments: adjustments,
    );
    CourseOccurrence? current;
    CourseOccurrence? next;

    for (final occurrence in occurrences) {
      if (!now.isBefore(occurrence.start) && now.isBefore(occurrence.end)) {
        current ??= occurrence;
      } else if (occurrence.start.isAfter(now)) {
        next = occurrence;
        break;
      }
    }

    return (current: current, next: next);
  }
}
