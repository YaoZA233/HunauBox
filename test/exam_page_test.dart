import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_hunan_agri/models/exam_schedule_model.dart';
import 'package:smart_hunan_agri/providers/exam_provider.dart';
import 'package:smart_hunan_agri/pages/exam_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ExamPage renders empty state when no exams', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          examProvider.overrideWith((ref) => _FakeExamNotifier([])),
        ],
        child: const MaterialApp(
          home: ExamPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('考试安排'), findsOneWidget);
    expect(find.text('暂无本学期考试安排'), findsOneWidget);
    expect(find.text('添加考试'), findsWidgets);
  });

  testWidgets('ExamPage renders exam cards correctly', (tester) async {
    final futureDate = DateTime.now().add(const Duration(days: 3));
    final sampleExams = [
      ExamScheduleModel(
        id: 'exam_1',
        title: '大学英语期末考试',
        courseName: '大学英语',
        time: futureDate,
        status: '进行中',
        location: '十教南204',
        remarks: '自带准考证',
        isManual: true,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          examProvider.overrideWith((ref) => _FakeExamNotifier(sampleExams)),
        ],
        child: const MaterialApp(
          home: ExamPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('大学英语'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('十教南204'), findsOneWidget);
    expect(find.text('自带准考证'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });
}

class _FakeExamNotifier extends StateNotifier<AsyncValue<List<ExamScheduleModel>>>
    implements ExamNotifier {
  _FakeExamNotifier(List<ExamScheduleModel> initial)
      : super(AsyncValue.data(initial));

  @override
  Future<void> pruneExpiredManualExams() async {}

  @override
  Future<void> refresh() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
