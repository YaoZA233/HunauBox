import '../models/course_model.dart';
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
        final date = DateCalculator.calculateDate(
          firstWeekMonday: normalizedMonday,
          weekNumber: week,
          dayOfWeek: course.dayOfWeek,
        );
        final startTime = DateCalculator.getSectionTime(course.startPeriod)['start']!;
        final endTime = DateCalculator.getSectionTime(course.endPeriod)['end']!;
        final start = DateTime(date.year, date.month, date.day, startTime.hour, startTime.minute);
        final end = DateTime(date.year, date.month, date.day, endTime.hour, endTime.minute);
        if (!end.isBefore(from)) {
          occurrences.add(CourseOccurrence(course: course, start: start, end: end));
        }
      }
    }

    occurrences.sort((a, b) => a.start.compareTo(b.start));
    return limit == null ? occurrences : occurrences.take(limit).toList();
  }

  static ({CourseOccurrence? current, CourseOccurrence? next}) currentAndNext({
    required List<CourseModel> courses,
    required DateTime? firstWeekMonday,
    required DateTime now,
  }) {
    if (firstWeekMonday == null) return (current: null, next: null);

    final occurrences = upcomingOccurrences(
      courses: courses,
      firstWeekMonday: firstWeekMonday,
      from: now,
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
