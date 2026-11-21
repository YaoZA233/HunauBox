import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/score_model.dart';
import 'package:smart_hunan_agri/pages/score_page.dart';
import 'package:smart_hunan_agri/providers/score_provider.dart';

class _FakeScoreNotifier extends ScoreNotifier {
  _FakeScoreNotifier()
    : super(
        fetchOnCreate: false,
        initialState: ScoreState(
          isLoading: false,
          semesters: [
            SemesterModel(value: '2025', xq: '1', name: '2025-2026 学年第一学期'),
          ],
          selectedSemester: SemesterModel(
            value: '2025',
            xq: '1',
            name: '2025-2026 学年第一学期',
          ),
          cachedAt: DateTime(2026, 11, 19, 9),
          scores: [
            ScoreModel(
              courseName: '大学英语',
              score: '92',
              credit: '2.0',
              examType: '正常考试',
            ),
            ScoreModel(
              courseName: '植物生理学',
              score: '55',
              credit: '3.0',
              examType: '正常考试',
            ),
            ScoreModel(
              courseName: '线性代数',
              score: '85',
              credit: '2.0',
              examType: '正常考试',
            ),
          ],
        ),
      );
}

void main() {
  testWidgets('成绩页把课程成绩作为主要内容展示', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scoreProvider.overrideWith((ref) => _FakeScoreNotifier())],
        child: const MaterialApp(home: ScorePage()),
      ),
    );

    expect(find.text('大学英语'), findsOneWidget);
    expect(find.text('植物生理学'), findsOneWidget);
    expect(find.text('线性代数'), findsOneWidget);
    expect(find.text('平均分'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SegmentedButton<Object>), findsNothing);
  });
}
