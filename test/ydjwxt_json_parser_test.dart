import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/utils/ydjwxt_json_parser.dart';

Map<String, dynamic> _response({
  String classTime = '609101112',
  String weekNoteDetail = '609,610,611,612',
  int coursesNote = 4,
}) {
  return {
    'code': '1',
    'data': [
      {
        'date': [
          {'xqid': '1', 'mxrq': '2026-09-21', 'zc': '4'},
        ],
        'courses': [
          {
            'jx0408id': 'course-1',
            'courseName': '机器人学',
            'teacherName': '刘老师',
            'classroomName': '八教南617',
            'classWeek': '4-6',
            'classTime': classTime,
            'weekDay': '6',
            'weekNoteDetail': weekNoteDetail,
            'coursesNote': coursesNote,
          },
        ],
      },
    ],
  };
}

void main() {
  group('YdjwxtJsonParser', () {
    test('从教学周日期反推出第一周周一', () {
      expect(
        YdjwxtJsonParser.extractFirstWeekMonday(_response()),
        DateTime(2026, 8, 31),
      );
    });

    test('解析四节连堂课程', () {
      final course = YdjwxtJsonParser.parseWeekJson(_response()).single;

      expect(course.name, '机器人学');
      expect(course.startPeriod, 9);
      expect(course.endPeriod, 12);
      expect(course.periods, '09-12');
      expect(course.dayOfWeek, DateTime.saturday);
      expect(course.weeks, '4-6(周)');
    });

    test('classTime 缺失时使用 weekNoteDetail', () {
      final course = YdjwxtJsonParser.parseWeekJson(
        _response(classTime: ''),
      ).single;

      expect(course.startPeriod, 9);
      expect(course.endPeriod, 12);
    });

    test('合并不同周响应中的重复课程', () {
      final week = YdjwxtJsonParser.parseWeekJson(_response());

      expect(YdjwxtJsonParser.mergeWeeks([week, week]), hasLength(1));
    });
  });
}
