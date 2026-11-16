import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/course_model.dart';
import 'package:smart_hunan_agri/services/course_schedule_service.dart';

CourseModel _course({
  required String id,
  required int dayOfWeek,
  required int startPeriod,
  required int endPeriod,
  String weeks = '1-2',
}) {
  return CourseModel(
    id: id,
    name: id,
    teacher: '',
    classroom: 'A101',
    weeks: weeks,
    periods: '$startPeriod-$endPeriod',
    dayOfWeek: dayOfWeek,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
  );
}

void main() {
  final firstMonday = DateTime(2026, 7, 20);

  group('CourseScheduleService.currentAndNext', () {
    test('identifies the course in progress and its following course', () {
      final result = CourseScheduleService.currentAndNext(
        courses: [
          _course(id: 'current', dayOfWeek: DateTime.monday, startPeriod: 1, endPeriod: 2),
          _course(id: 'next', dayOfWeek: DateTime.monday, startPeriod: 3, endPeriod: 4),
        ],
        firstWeekMonday: firstMonday,
        now: DateTime(2026, 7, 20, 8, 30),
      );

      expect(result.current?.course.id, 'current');
      expect(result.next?.course.id, 'next');
    });

    test('finds the next real class beyond the current day', () {
      final result = CourseScheduleService.currentAndNext(
        courses: [
          _course(id: 'monday', dayOfWeek: DateTime.monday, startPeriod: 1, endPeriod: 2),
          _course(id: 'wednesday', dayOfWeek: DateTime.wednesday, startPeriod: 1, endPeriod: 2),
        ],
        firstWeekMonday: firstMonday,
        now: DateTime(2026, 7, 20, 10),
      );

      expect(result.current, isNull);
      expect(result.next?.course.id, 'wednesday');
      expect(result.next?.start, DateTime(2026, 7, 22, 8));
    });

    test('returns no course outside all configured teaching weeks', () {
      final result = CourseScheduleService.currentAndNext(
        courses: [
          _course(id: 'week-one', dayOfWeek: DateTime.monday, startPeriod: 1, endPeriod: 2, weeks: '1'),
        ],
        firstWeekMonday: firstMonday,
        now: DateTime(2026, 8, 3, 8),
      );

      expect(result.current, isNull);
      expect(result.next, isNull);
    });
  });
}
