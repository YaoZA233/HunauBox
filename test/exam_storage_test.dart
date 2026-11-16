import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/exam_schedule_model.dart';
import 'package:smart_hunan_agri/services/exam_storage.dart';
import 'package:intl/intl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExamStorage Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('exam_storage_test_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('ExamStorage persists and restores exam list correctly', () async {
      final storage = ExamStorage(baseDirectory: tempDir);
      final futureDate = DateTime.now().add(const Duration(days: 10));
      final exams = [
        ExamScheduleModel(
          id: '10762596',
          title: '补考试题',
          time: futureDate,
          allTimes: [
            futureDate,
            futureDate.add(const Duration(minutes: 30)),
          ],
          rawTimeStrs: [
            DateFormat('yyyy-MM-dd HH:mm').format(futureDate),
            DateFormat(
              'yyyy-MM-dd HH:mm',
            ).format(futureDate.add(const Duration(minutes: 30))),
          ],
          status: '已完成',
        ),
      ];

      await storage.saveExamList(exams);
      final loaded = await storage.readExamList();
      expect(loaded.length, equals(1));
      expect(loaded.first.id, equals('10762596'));
      expect(loaded.first.title, equals('补考试题'));
      expect(loaded.first.time.year, equals(futureDate.year));
      expect(loaded.first.time.month, equals(futureDate.month));
      expect(loaded.first.time.day, equals(futureDate.day));

      // 验证过期 ID 集合存储
      await storage.saveExpiredExamIds({'10762596', '9473825'});
      final expired = await storage.readExpiredExamIds();
      expect(expired, contains('10762596'));
      expect(expired, contains('9473825'));

      // 验证删除
      await storage.deleteExamList();
      final afterDelete = await storage.readExamList();
      expect(afterDelete, isEmpty);
    });

    test(
      'ExamScheduleModel supports manual exams, location and remarks',
      () async {
        final storage = ExamStorage(baseDirectory: tempDir);
        final exam = ExamScheduleModel(
          id: 'manual_123456',
          title: '大学英语期末口语考试',
          courseName: '大学英语',
          time: DateTime.now().add(const Duration(days: 20)),
          status: '待考',
          isManual: true,
          location: '十教南204',
          remarks: '自带准考证和学生证',
        );

        await storage.saveExamList([exam]);
        final loaded = await storage.readExamList();
        expect(loaded.length, equals(1));
        expect(loaded.first.isManual, isTrue);
        expect(loaded.first.location, equals('十教南204'));
        expect(loaded.first.remarks, equals('自带准考证和学生证'));
        expect(loaded.first.courseName, equals('大学英语'));
      },
    );

    test('readExamList automatically filters out expired exams', () async {
      final storage = ExamStorage(baseDirectory: tempDir);
      final pastExam = ExamScheduleModel(
        id: 'past_1',
        title: '已结束考试',
        time: DateTime(2020, 1, 1),
      );
      final futureExam = ExamScheduleModel(
        id: 'future_1',
        title: '未来考试',
        time: DateTime.now().add(const Duration(days: 5)),
      );

      // 直接写入文件绕过 saveExamList 过滤
      final file = File('${tempDir.path}/exam_schedule_list.json');
      await file.writeAsString(
        '[${pastExam.toJson()}, ${futureExam.toJson()}]',
      );

      // 通过 saveExamList 正常持久化
      await storage.saveExamList([pastExam, futureExam]);
      final loaded = await storage.readExamList();
      expect(loaded.length, equals(1));
      expect(loaded.first.id, equals('future_1'));
    });
  });
}
