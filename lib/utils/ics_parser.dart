import '../models/course_model.dart';
import '../services/app_logger.dart';

class IcsParser {
  static final _logger = AppLogger.instance;

  static List<CourseModel> parse(String icsContent) {
    final courses = <CourseModel>[];

    final events = _extractEvents(icsContent);
    for (int i = 0; i < events.length; i++) {
      final eventCourses = _parseEvent(events[i]);
      if (eventCourses != null && eventCourses.isNotEmpty) {
        courses.addAll(eventCourses);
      } else {
        _logger.w('⚠️ Failed to parse event $i');
      }
    }

    return courses;
  }

  static List<String> _extractEvents(String icsContent) {
    final events = <String>[];
    final eventRegex = RegExp(
      r'BEGIN:VEVENT\s*([\s\S]*?)\s*END:VEVENT',
      multiLine: true,
      dotAll: true,
    );

    final matches = eventRegex.allMatches(icsContent);
    for (final match in matches) {
      final eventContent = match.group(0);
      if (eventContent != null && eventContent.isNotEmpty) {
        events.add(eventContent);
      }
    }

    return events;
  }

  static List<CourseModel>? _parseEvent(String event) {
    try {
      final lines = event.split('\n');

      String? summary;
      String? location;
      final descriptionLines = <String>[];
      String? dtstart;
      String? dtend;
      String? rrule;

      bool inDescription = false;

      for (final line in lines) {
        final trimmed = line.trim();

        if (trimmed.startsWith('SUMMARY:')) {
          summary = trimmed.substring(8);
          inDescription = false;
        } else if (trimmed.startsWith('LOCATION:')) {
          location = trimmed.substring(9);
          inDescription = false;
        } else if (trimmed.startsWith('DESCRIPTION:')) {
          final firstLine = trimmed.substring(12);
          if (firstLine.isNotEmpty) {
            descriptionLines.add(firstLine);
          }
          inDescription = true;
        } else if (trimmed.startsWith('DTSTART:')) {
          dtstart = trimmed.substring(8);
          inDescription = false;
        } else if (trimmed.startsWith('DTEND:')) {
          dtend = trimmed.substring(6);
          inDescription = false;
        } else if (trimmed.startsWith('RRULE:')) {
          rrule = trimmed.substring(6);
          inDescription = false;
        } else if (trimmed.startsWith('STATUS:') ||
            trimmed.startsWith('SEQUENCE:') ||
            trimmed.startsWith('BEGIN:') ||
            trimmed.startsWith('END:')) {
          inDescription = false;
        } else if (inDescription && trimmed.isNotEmpty) {
          descriptionLines.add(trimmed);
        }
      }

      final description = descriptionLines.isEmpty ? null : descriptionLines.join('\n');

      if (summary == null || dtstart == null) {
        return null;
      }

      final startDate = _parseIcsDateTime(dtstart);
      if (startDate == null) {
        return null;
      }

      final dayOfWeek = startDate.weekday;
      final startPeriod = _timeToPeriod(startDate.hour, startDate.minute);
      final endPeriod = dtend != null ? _timeToPeriodFromEnd(dtend, startDate) : startPeriod;

      String weeks = '1';
      String teacher = '';

      if (description != null) {
        final weekMatch = RegExp(r'周次[：:]\s*第([\d,\-]+)周').firstMatch(description);
        if (weekMatch != null) {
          weeks = '${weekMatch.group(1)}(周)';
        }

        final teacherMatch = RegExp(r'教师[：:]\s*(.+)').firstMatch(description);
        if (teacherMatch != null) {
          teacher = teacherMatch.group(1)!.trim();
        }
      } else if (rrule != null) {
        final countMatch = RegExp(r'COUNT=(\d+)').firstMatch(rrule);
        if (countMatch != null) {
          final count = int.tryParse(countMatch.group(1)!);
          if (count != null && count > 0) {
            weeks = count == 1 ? '1(周)' : '1-$count(周)';
          }
        }
      }

      final id = '${startDate.millisecondsSinceEpoch}_$dayOfWeek';

      return [
        CourseModel(
          id: id,
          name: summary,
          teacher: teacher,
          classroom: location ?? '',
          weeks: weeks,
          periods: '$startPeriod-$endPeriod',
          dayOfWeek: dayOfWeek,
          startPeriod: startPeriod,
          endPeriod: endPeriod,
        ),
      ];
    } catch (e) {
      return null;
    }
  }

  static DateTime? _parseIcsDateTime(String dateTimeStr) {
    try {
      if (dateTimeStr.length < 15) return null;

      final year = int.parse(dateTimeStr.substring(0, 4));
      final month = int.parse(dateTimeStr.substring(4, 6));
      final day = int.parse(dateTimeStr.substring(6, 8));
      final hour = int.parse(dateTimeStr.substring(9, 11));
      final minute = int.parse(dateTimeStr.substring(11, 13));

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  static int _timeToPeriod(int hour, int minute) {
    final timeInMinutes = hour * 60 + minute;

    const periodTimes = [
      (start: 480, end: 525, period: 1),
      (start: 535, end: 580, period: 2),
      (start: 605, end: 650, period: 3),
      (start: 660, end: 705, period: 4),
      (start: 870, end: 915, period: 5),
      (start: 925, end: 970, period: 6),
      (start: 995, end: 1040, period: 7),
      (start: 1050, end: 1095, period: 8),
      (start: 1170, end: 1215, period: 9),
      (start: 1225, end: 1270, period: 10),
      (start: 1280, end: 1325, period: 11),
      (start: 1335, end: 1380, period: 12),
    ];

    for (final pt in periodTimes) {
      if (timeInMinutes >= pt.start && timeInMinutes <= pt.end) {
        return pt.period;
      }
    }

    return 1;
  }

  static int _timeToPeriodFromEnd(String dtend, DateTime startDate) {
    try {
      final endDate = _parseIcsDateTime(dtend);
      if (endDate == null) return 1;

      return _timeToPeriod(endDate.hour, endDate.minute);
    } catch (e) {
      return 1;
    }
  }
}
