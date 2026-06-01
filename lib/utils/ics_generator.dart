import '../models/course_model.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';

class IcsGenerator {
  static String generate(List<CourseModel> courses, DateTime firstWeekMonday) {
    final buffer = StringBuffer();

    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Live@HUNAU//Timetable//CN');
    buffer.writeln('CALSCALE:GREGORIAN');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('X-WR-CALNAME:湖南农业大学课表');
    buffer.writeln('X-WR-TIMEZONE:Asia/Shanghai');

    for (final course in courses) {
      _generateCourseEvents(buffer, course, firstWeekMonday);
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  static void _generateCourseEvents(
    StringBuffer buffer,
    CourseModel course,
    DateTime firstWeekMonday,
  ) {
    final weeks = WeekParser.parseWeeks(course.weeks);
    if (weeks.isEmpty) return;

    final weekGroups = _groupConsecutiveWeeks(weeks);
    for (final group in weekGroups) {
      if (group.length == 1) {
        _generateSingleEvent(buffer, course, firstWeekMonday, group[0]);
      } else {
        _generateRecurringEvent(buffer, course, firstWeekMonday, group);
      }
    }
  }

  static void _generateSingleEvent(
    StringBuffer buffer,
    CourseModel course,
    DateTime firstWeekMonday,
    int weekNumber,
  ) {
    final date = DateCalculator.calculateDate(
      firstWeekMonday: firstWeekMonday,
      weekNumber: weekNumber,
      dayOfWeek: course.dayOfWeek,
    );

    final startTime = DateCalculator.getSectionTime(course.startPeriod)['start']!;
    final endTime = DateCalculator.getSectionTime(course.endPeriod)['end']!;

    final startDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );

    final endDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:${_generateUid(course, weekNumber)}');
    buffer.writeln('DTSTAMP:${_formatDateTime(DateTime.now().toUtc())}');
    buffer.writeln('DTSTART:${_formatDateTime(startDateTime)}');
    buffer.writeln('DTEND:${_formatDateTime(endDateTime)}');
    buffer.writeln('SUMMARY:${course.name}');
    buffer.writeln('LOCATION:${course.classroom.isEmpty ? '未知教室' : course.classroom}');
    buffer.writeln('DESCRIPTION:${_generateDescription(course, weekNumber)}');
    buffer.writeln('STATUS:CONFIRMED');
    buffer.writeln('SEQUENCE:0');
    buffer.writeln('BEGIN:VALARM');
    buffer.writeln('TRIGGER:-PT15M');
    buffer.writeln('ACTION:DISPLAY');
    buffer.writeln('DESCRIPTION:课程提醒');
    buffer.writeln('END:VALARM');
    buffer.writeln('END:VEVENT');
  }

  static void _generateRecurringEvent(
    StringBuffer buffer,
    CourseModel course,
    DateTime firstWeekMonday,
    List<int> weeks,
  ) {
    final firstWeek = weeks.first;
    final date = DateCalculator.calculateDate(
      firstWeekMonday: firstWeekMonday,
      weekNumber: firstWeek,
      dayOfWeek: course.dayOfWeek,
    );

    final startTime = DateCalculator.getSectionTime(course.startPeriod)['start']!;
    final endTime = DateCalculator.getSectionTime(course.endPeriod)['end']!;

    final startDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );

    final endDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:${_generateUid(course, firstWeek)}-${weeks.length}');
    buffer.writeln('DTSTAMP:${_formatDateTime(DateTime.now().toUtc())}');
    buffer.writeln('DTSTART:${_formatDateTime(startDateTime)}');
    buffer.writeln('DTEND:${_formatDateTime(endDateTime)}');
    buffer.writeln('RRULE:FREQ=WEEKLY;COUNT=${weeks.length}');
    buffer.writeln('SUMMARY:${course.name}');
    buffer.writeln('LOCATION:${course.classroom.isEmpty ? '未知教室' : course.classroom}');
    buffer.writeln('DESCRIPTION:${_generateDescription(course, weeks.first, weeks.last)}');
    buffer.writeln('STATUS:CONFIRMED');
    buffer.writeln('SEQUENCE:0');
    buffer.writeln('BEGIN:VALARM');
    buffer.writeln('TRIGGER:-PT15M');
    buffer.writeln('ACTION:DISPLAY');
    buffer.writeln('DESCRIPTION:课程提醒');
    buffer.writeln('END:VALARM');
    buffer.writeln('END:VEVENT');
  }

  static List<List<int>> _groupConsecutiveWeeks(List<int> weeks) {
    if (weeks.isEmpty) return [];

    final groups = <List<int>>[];
    List<int> currentGroup = [weeks[0]];

    for (int i = 1; i < weeks.length; i++) {
      if (weeks[i] == weeks[i - 1] + 1) {
        currentGroup.add(weeks[i]);
      } else {
        groups.add(currentGroup);
        currentGroup = [weeks[i]];
      }
    }

    groups.add(currentGroup);
    return groups;
  }

  static String _generateUid(CourseModel course, int weekNumber) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'course-${course.hashCode}-w$weekNumber-$timestamp@hunau.edu.cn';
  }

  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}'
        '${_padZero(dateTime.month)}'
        '${_padZero(dateTime.day)}T'
        '${_padZero(dateTime.hour)}'
        '${_padZero(dateTime.minute)}'
        '${_padZero(dateTime.second)}';
  }

  static String _generateDescription(
    CourseModel course,
    int startWeek, [
    int? endWeek,
  ]) {
    final buffer = StringBuffer();

    if (course.teacher.isNotEmpty) {
      buffer.writeln('教师：${course.teacher}');
    }

    if (endWeek != null) {
      buffer.writeln('周次：第$startWeek-${endWeek}周');
    } else {
      buffer.writeln('周次：第$startWeek周');
    }

    if (course.classroom.isNotEmpty) {
      buffer.writeln('教室：${course.classroom}');
    }

    return buffer.toString().trim();
  }

  static String _padZero(int number) {
    return number.toString().padLeft(2, '0');
  }
}
