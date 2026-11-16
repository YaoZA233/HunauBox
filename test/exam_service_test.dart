import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/exam_schedule_model.dart';
import 'package:smart_hunan_agri/services/exam_service.dart';
import 'package:smart_hunan_agri/services/exam_storage.dart';

void main() {
  group('ExamService URL & HTML parsing tests', () {
    late ExamService examService;

    setUpAll(() async {
      examService = ExamService();
    });

    test('buildTaskExamUrl should append ut=s and preserve fragment', () {
      const raw =
          '/exam-ans/exam/phone/task-exam?taskrefId=10783790&courseId=266204575&classId=152272723&from=examlist#INNER';
      final built = ExamService.buildTaskExamUrl(raw);
      expect(
        built,
        equals(
          'https://mooc1-api.chaoxing.com/exam-ans/exam/phone/task-exam?taskrefId=10783790&courseId=266204575&classId=152272723&from=examlist&ut=s#INNER',
        ),
      );
    });

    test('parseExamListHtml on snippet extracts title, status, and id', () {
      const snippet = '''
<li onclick="goTask(this);" data="/exam-ans/exam/phone/task-exam?taskrefId=10783790&courseId=266204575&classId=152272723&from=examlist"
				data-stopexam="0" title="2误差分析">
            		<div class="ks_pic"><img tabindex="-1" aria-hidden="true" src="//mooc1-api.chaoxing.com/exam-ans/views/identifycode/images/ks_02.png"/></div>
            		<dl class="ks_text" tabindex="0" role="text" aria-label='考试名称：2误差分析; 考试状态：已完成;'>
            			<dt>2误差分析</dt>
            		</dl>
            		<span tabindex="-1" aria-hidden="true" class="ks_state">已完成</span>
            	</li>
''';
      final items = examService.parseExamListHtml(snippet);
      expect(items.length, equals(1));
      expect(items[0]['id'], equals('10783790'));
      expect(items[0]['title'], equals('2误差分析'));
      expect(items[0]['status'], equals('已完成'));
      expect(
        items[0]['dataUrl'],
        equals(
          'https://mooc1-api.chaoxing.com/exam-ans/exam/phone/task-exam?taskrefId=10783790&courseId=266204575&classId=152272723&from=examlist&ut=s',
        ),
      );
    });

    test(
      'parseExamDetailHtml strictly extracts from watermark-wrapper z-index:100',
      () {
        const snippet = '''
<div id="watermark-wrapper" class="watermark-wrapper"></div>
<div style="position:relative;z-index:100">
    <p>姓名：李四</p>
    <p>学号：202440801234</p>
    <p>领取时间：
        <span class="din font16">2026-09-10 19:00</span></p>
    <p>提交时间：
        <span class="din font16">2026-09-10 19:30</span></p>
    <p>考试用时：<span class="din font16">30</span>分钟</p>
    <p>提交方式：学生交卷</p>
</div>
''';
        final result = examService.parseExamDetailHtml(snippet);
        expect(result, isNotNull);
        expect(result!.startTime, equals(DateTime(2026, 9, 10, 19, 0)));
        expect(result.displayTime, equals(DateTime(2026, 9, 10, 19, 0)));
        expect(result.endTime, equals(DateTime(2026, 9, 10, 19, 30)));
        expect(result.studentName, equals('李四'));
        expect(result.studentId, equals('202440801234'));
        expect(result.allTimes.length, equals(2));
      },
    );

    test(
      'parseExamDetailHtml ignores dynamicNowTime and extracts true exam times',
      () {
        const htmlWithCurrentTime = '''
<p class="paper_time">当前时间<span class="din_bold font4" id="dynamicNowTime">2026-10-17 03:44:00</span></p>
<div class="result_gray_div pad80" style="position:relative;overflow:hidden;">
  <div id="watermark-wrapper" class="watermark-wrapper"></div>
  <div style="position:relative;z-index:100">
    <p>姓名：王五</p> <p>学号：202440805678</p>
    <p>领取时间：
        <span class="din font16">2026-12-26 11:10</span></p>
    <p>提交时间：
        <span class="din font16">2026-12-26 11:37</span></p>
  </div>
</div>
''';
        final result = examService.parseExamDetailHtml(htmlWithCurrentTime);
        expect(result, isNotNull);
        expect(result!.startTime, equals(DateTime(2026, 12, 26, 11, 10)));
        expect(result.endTime, equals(DateTime(2026, 12, 26, 11, 37)));
        expect(result.studentName, equals('王五'));
        expect(result.studentId, equals('202440805678'));
      },
    );

    test('isPendingOrUnfinished identifies pending and completed exams', () {
      expect(ExamService.isPendingOrUnfinished('待考'), isTrue);
      expect(ExamService.isPendingOrUnfinished('未开始'), isTrue);
      expect(ExamService.isPendingOrUnfinished('进行中'), isTrue);
      expect(ExamService.isPendingOrUnfinished('未交'), isTrue);
      expect(ExamService.isPendingOrUnfinished('已完成'), isFalse);
      expect(ExamService.isPendingOrUnfinished('已结束'), isFalse);
      expect(ExamService.isPendingOrUnfinished(''), isFalse);
    });

    test('ExamStorage.isUpcomingOrToday filters dates correctly', () {
      final now = DateTime(2026, 10, 23, 14, 0);
      final todayMorning = DateTime(2026, 10, 23, 8, 30);
      final futureDate = DateTime(2026, 10, 25, 9, 0);
      final pastDate = DateTime(2026, 10, 22, 23, 59);

      final examToday = ExamScheduleModel(
        id: '1',
        title: '今日考试',
        time: todayMorning,
      );
      final examFuture = ExamScheduleModel(
        id: '2',
        title: '未来考试',
        time: futureDate,
      );
      final examPast = ExamScheduleModel(
        id: '3',
        title: '过去考试',
        time: pastDate,
      );

      expect(ExamStorage.isUpcomingOrToday(examToday, now), isTrue);
      expect(ExamStorage.isUpcomingOrToday(examFuture, now), isTrue);
      expect(ExamStorage.isUpcomingOrToday(examPast, now), isFalse);
    });
  });
}
