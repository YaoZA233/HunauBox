import '../models/course_model.dart';
import '../services/app_logger.dart';

/// 移动教务课表 JSON 解析器。
class YdjwxtJsonParser {
  YdjwxtJsonParser._();

  static final _logger = AppLogger.instance;

  /// 根据接口返回的某一教学周日期，反推出第一周周一。
  static DateTime? extractFirstWeekMonday(Map<String, dynamic> json) {
    try {
      final data = json['data'];
      if (data is! List || data.isEmpty || data.first is! Map) return null;

      final dateList = (data.first as Map)['date'];
      if (dateList is! List || dateList.isEmpty) return null;

      Map<dynamic, dynamic>? monday;
      for (final value in dateList.whereType<Map>()) {
        if (value['xqid']?.toString() == '1') {
          monday = value;
          break;
        }
      }
      monday ??= dateList.whereType<Map>().firstOrNull;
      if (monday == null) return null;

      final date = DateTime.tryParse(monday['mxrq']?.toString() ?? '');
      final week = int.tryParse(monday['zc']?.toString() ?? '');
      if (date == null || week == null || week < 1) return null;

      final normalizedMonday = date.subtract(
        Duration(days: date.weekday - DateTime.monday),
      );
      return DateTime(
        normalizedMonday.year,
        normalizedMonday.month,
        normalizedMonday.day,
      ).subtract(Duration(days: (week - 1) * 7));
    } catch (e) {
      _logger.e('解析移动教务学期日期失败: $e');
      return null;
    }
  }

  static List<CourseModel> parseWeekJson(Map<String, dynamic> json) {
    final courses = <CourseModel>[];

    try {
      final data = json['data'];
      if (data is! List || data.isEmpty || data.first is! Map) return courses;

      final rawCourses = (data.first as Map)['courses'];
      if (rawCourses is! List) return courses;

      for (final item in rawCourses.whereType<Map>()) {
        final name = item['courseName']?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        final day = int.tryParse(item['weekDay']?.toString() ?? '') ?? 0;
        final periods = _parsePeriods(item);
        if (day < 0 || day > 7 || periods == null) continue;

        final rawWeeks = item['classWeek']?.toString().trim() ?? '';
        if (rawWeeks.isEmpty) continue;

        final normalizedDay = day == 0 ? DateTime.sunday : day;
        final id = item['jx0408id']?.toString().trim();
        courses.add(
          CourseModel(
            id: id == null || id.isEmpty
                ? [name, normalizedDay, periods.$1, rawWeeks].join('_')
                : id,
            name: name,
            teacher: item['teacherName']?.toString().trim() ?? '',
            classroom: item['classroomName']?.toString().trim() ?? '',
            weeks: rawWeeks.contains('(周)') ? rawWeeks : '$rawWeeks(周)',
            periods:
                '${periods.$1.toString().padLeft(2, '0')}-${periods.$2.toString().padLeft(2, '0')}',
            dayOfWeek: normalizedDay,
            startPeriod: periods.$1,
            endPeriod: periods.$2,
          ),
        );
      }
    } catch (e) {
      _logger.e('解析移动教务课表失败: $e');
    }

    return courses;
  }

  /// 同一门课会在每周响应中重复出现，按稳定的上课信息去重。
  static List<CourseModel> mergeWeeks(
    Iterable<List<CourseModel>> allWeeksData,
  ) {
    final merged = <String, CourseModel>{};
    for (final courses in allWeeksData) {
      for (final course in courses) {
        final key = [
          course.name,
          course.teacher,
          course.classroom,
          course.dayOfWeek,
          course.startPeriod,
          course.endPeriod,
          course.weeks,
        ].join('\u0000');
        merged.putIfAbsent(key, () => course);
      }
    }
    return merged.values.toList()
      ..sort((a, b) {
        final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
        return byDay != 0 ? byDay : a.startPeriod.compareTo(b.startPeriod);
      });
  }

  static (int, int)? _parsePeriods(Map<dynamic, dynamic> item) {
    final classTime = item['classTime']?.toString().trim() ?? '';
    int start = 0;
    int end = 0;

    if (classTime.length >= 3) {
      start = int.tryParse(classTime.substring(1, 3)) ?? 0;
      end = int.tryParse(classTime.substring(classTime.length - 2)) ?? start;
    }

    if (start == 0 || end == 0) {
      final details = (item['weekNoteDetail']?.toString() ?? '')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (details.isNotEmpty) {
        start = _periodFromDetail(details.first);
        end = _periodFromDetail(details.last);
      }
    }

    final count = int.tryParse(item['coursesNote']?.toString() ?? '') ?? 0;
    if (start > 0 && count > 0 && end < start + count - 1) {
      end = start + count - 1;
    }

    if (start < 1 || end < start) return null;
    return (start, end);
  }

  static int _periodFromDetail(String value) {
    final period = value.length > 2
        ? value.substring(value.length - 2)
        : value;
    return int.tryParse(period) ?? 0;
  }
}
