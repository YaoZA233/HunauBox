import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/course_model.dart';
import 'package:smart_hunan_agri/models/timetable_adjustment.dart';
import 'package:smart_hunan_agri/services/course_schedule_service.dart';
import 'package:smart_hunan_agri/services/timetable_adjustment_service.dart';

CourseModel course(
  String id, {
  int day = 1,
  int start = 1,
  int end = 2,
  String weeks = '1-3',
}) => CourseModel(
  id: id,
  name: id,
  teacher: '',
  classroom: 'A101',
  weeks: weeks,
  periods: '$start-$end',
  dayOfWeek: day,
  startPeriod: start,
  endPeriod: end,
);

void main() {
  final monday = DateTime(2026, 10, 5);
  final morning = course('上午');
  final afternoon = course('下午', start: 5, end: 6);
  final tuesday = course('周二', day: 2);
  final courses = [morning, afternoon, tuesday];

  List<CourseOccurrence> schedule(List<TimetableAdjustment> changes) =>
      CourseScheduleService.upcomingOccurrences(
        courses: courses,
        firstWeekMonday: monday,
        from: monday,
        adjustments: changes,
      );

  test('整天跨周调课移动全部课程，保留不同节次和其他日期的课程', () {
    final changes = TimetableAdjustmentService.forDates(
      courses: courses,
      adjustments: [],
      firstWeekMonday: monday,
      sourceStart: monday,
      targetDate: DateTime(2026, 10, 18),
    );
    expect(changes, hasLength(2));
    final occurrences = schedule(changes);
    expect(occurrences, hasLength(9));
    expect(occurrences.where((o) => o.start.day == 5), isEmpty);
    final moved = occurrences.where((o) => o.start.day == 18).toList();
    expect(moved.map((o) => o.start.hour), [8, 14]);
    expect(occurrences.where((o) => o.course.id == '周二'), hasLength(3));
    expect(changes.map((a) => a.sourceWeek), everyElement(1));
    expect(changes.map((a) => a.targetWeek), everyElement(2));
  });

  test('连续日期停课包括两端日期，其他周次不变', () {
    final changes = TimetableAdjustmentService.forDates(
      courses: courses,
      adjustments: [],
      firstWeekMonday: monday,
      sourceStart: monday,
      sourceEnd: DateTime(2026, 10, 6),
      cancelled: true,
    );
    expect(changes, hasLength(3));
    expect(changes.every((a) => a.cancelled), isTrue);
    expect(schedule(changes), hasLength(6));
    expect(schedule(changes).every((o) => o.start.day >= 12), isTrue);
  });

  test('日期模式按当前安排查找已调课程，重复迁移更新同一来源记录', () {
    final first = TimetableAdjustmentService.forWeeks(
      course: morning,
      sourceWeeks: {1},
      targetWeek: 2,
      targetDay: 2,
      start: 3,
      end: 4,
    );
    final second = TimetableAdjustmentService.forDates(
      courses: courses,
      adjustments: first,
      firstWeekMonday: monday,
      sourceStart: DateTime(2026, 10, 13),
      targetDate: DateTime(2026, 10, 17),
    );
    expect(second.map((a) => a.courseId).toSet(), {'上午', '周二'});
    final moved = second.firstWhere((a) => a.courseId == '上午');
    expect(moved.sourceWeek, 1);
    expect(moved.targetWeek, 2);
    expect((moved.targetStartPeriod, moved.targetEndPeriod), (3, 4));
    final merged = TimetableAdjustmentService.merge(first, second);
    expect(merged, hasLength(2));
    final occurrences = schedule(merged);
    expect(occurrences, hasLength(9));
    expect(occurrences.where((o) => o.start.day == 13), isEmpty);
    expect(occurrences.where((o) => o.start.day == 17), hasLength(2));
  });

  test('原日期不再选中已移走或已停课的课程', () {
    final existing = [
      ...TimetableAdjustmentService.forWeeks(
        course: morning,
        sourceWeeks: {1},
        targetDay: 3,
        start: 1,
        end: 2,
      ),
      ...TimetableAdjustmentService.forWeeks(
        course: afternoon,
        sourceWeeks: {1},
        targetDay: 1,
        start: 5,
        end: 6,
        cancelled: true,
      ),
    ];
    expect(
      TimetableAdjustmentService.forDates(
        courses: courses,
        adjustments: existing,
        firstWeekMonday: monday,
        sourceStart: monday,
        cancelled: true,
      ),
      isEmpty,
    );
  });

  test('单周调课可指定来源周次，只替换这一周，跨周目标不丢课', () {
    final changes = TimetableAdjustmentService.forWeeks(
      course: morning,
      sourceWeeks: {2},
      targetWeek: 4,
      targetDay: 7,
      start: 9,
      end: 10,
    );
    expect(changes.single.sourceWeek, 2);
    final occurrences = schedule(
      changes,
    ).where((o) => o.course.id == '上午').toList();
    expect(occurrences.map((o) => o.start.day), [5, 19, 1]);
    expect(occurrences.last.start, DateTime(2026, 11, 1, 19, 30));
  });

  test('批量周次仅修改勾选周次，保留各自周次和未勾选周次', () {
    final changes = TimetableAdjustmentService.forWeeks(
      course: morning,
      sourceWeeks: {1, 3},
      targetDay: 5,
      start: 3,
      end: 4,
    );
    expect(changes.map((a) => (a.sourceWeek, a.targetWeek)), [(1, 1), (3, 3)]);
    final occurrences = schedule(
      changes,
    ).where((o) => o.course.id == '上午').toList();
    expect(occurrences.map((o) => o.start.day), [9, 12, 23]);
    expect(occurrences[1].start.hour, 8);
    expect(occurrences.first.start.hour, 10);
  });

  test('批量课程可选多门课，保留不同周次，排除结束节次不同的课程', () {
    final sameSlot = course('另一门课', weeks: '2,4');
    final longer = course('四节课', end: 4);
    final all = [...courses, sameSlot, longer];
    expect(
      TimetableAdjustmentService.matchingCourses(all, morning).map((c) => c.id),
      ['上午', '另一门课'],
    );
    final changes = TimetableAdjustmentService.forCourses(
      courses: all,
      anchor: morning,
      selectedIds: {'上午', '另一门课'},
      targetDay: 6,
      start: 7,
      end: 8,
    );
    expect(changes, hasLength(5));
    expect(
      changes.where((a) => a.courseId == '另一门课').map((a) => a.sourceWeek),
      [2, 4],
    );
    expect(changes.every((a) => a.sourceWeek == a.targetWeek), isTrue);
    final subset = TimetableAdjustmentService.forCourses(
      courses: all,
      anchor: morning,
      selectedIds: {'另一门课'},
      targetDay: 6,
      start: 7,
      end: 8,
    );
    expect(subset, hasLength(2));
    expect(subset.every((a) => a.courseId == '另一门课'), isTrue);
  });

  test('拒绝无效节次、无课周次和错误日期范围', () {
    expect(
      () => TimetableAdjustmentService.forWeeks(
        course: morning,
        sourceWeeks: {1},
        targetDay: 1,
        start: 5,
        end: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => TimetableAdjustmentService.forWeeks(
        course: morning,
        sourceWeeks: {4},
        targetDay: 1,
        start: 1,
        end: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => TimetableAdjustmentService.forDates(
        courses: courses,
        adjustments: [],
        firstWeekMonday: monday,
        sourceStart: monday,
        sourceEnd: monday.subtract(const Duration(days: 1)),
        cancelled: true,
      ),
      throwsArgumentError,
    );
  });
}
