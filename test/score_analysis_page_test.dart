import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/score_model.dart';
import 'package:smart_hunan_agri/pages/score_analysis_page.dart';

Map<SemesterModel, List<ScoreModel>> analysisScores() => {
  SemesterModel(
    value: '2025-2026-2',
    xq: '2',
    name: '2025-2026 学年第二学期（春季学期完整名称）',
  ): [
    ScoreModel(
      courseName: '农业生态环境保护与可持续发展综合实践课程完整名称',
      score: '98',
      credit: '3',
    ),
    ScoreModel(courseName: '计算机科学与技术基础课程完整名称', score: '良好', credit: '2'),
    ScoreModel(courseName: '暂无成绩', score: '--'),
  ],
  SemesterModel(
    value: '2024-2025-1',
    xq: '1',
    name: '2024-2025 学年第一学期（秋季学期完整名称）',
  ): [
    ScoreModel(courseName: '高等数学与线性代数综合应用课程完整名称', score: '45', credit: '4'),
    ScoreModel(courseName: '大学英语', score: '75', credit: '2'),
  ],
};

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('成绩分析 $brightness 320px 字号$scale，完整文字、主题对比与滚动无溢出', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final theme = ThemeData(
          colorSchemeSeed: Colors.green,
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ScoreAnalysisPage(loadScores: () async => analysisScores()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['累计均分', '通过率', '修读课程', '优秀成绩']) {
          await tester.scrollUntilVisible(
            find.text(label),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          final color = tester.widget<Text>(find.text(label)).style!.color!;
          final background = theme.colorScheme.surface;
          final l1 = color.computeLuminance();
          final l2 = background.computeLuminance();
          final contrast =
              ((l1 > l2 ? l1 : l2) + 0.05) / ((l1 > l2 ? l2 : l1) + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          expect(tester.takeException(), isNull);
        }
        for (var i = 0; i < 40; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        const longCourse = '高等数学与线性代数综合应用课程完整名称';
        expect(find.text(longCourse), findsOneWidget);
        expect(tester.widget<Text>(find.text(longCourse)).maxLines, isNull);
        expect(
          tester.widget<Text>(find.text(longCourse)).overflow,
          isNot(TextOverflow.ellipsis),
        );
        // No information text on this page intentionally truncates.
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .where((t) => t.overflow == TextOverflow.ellipsis),
          isEmpty,
        );
      });
    }
  }

  testWidgets('乱序接口数据按时间排序，算术均分和等级制转换正确', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreAnalysisPage(loadScores: () async => analysisScores()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('75.8 分'), findsOneWidget);
    expect(find.text('75.0%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('1 · 2024-2025 学年第一学期（秋季学期完整名称）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2 · 2025-2026 学年第二学期（春季学期完整名称）'), findsOneWidget);
    expect(find.text('4 门'), findsOneWidget);
  });

  testWidgets('空数据和网络失败提供可用重试，刷新失败不逃逸为异步异常', (tester) async {
    var attempt = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreAnalysisPage(
          loadScores: () async {
            if (attempt++ == 0) throw StateError('network');
            return {};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法获取完整成绩'), findsOneWidget);
    await tester.tap(find.text('重新获取'));
    await tester.pumpAndSettle();
    expect(find.text('还没有可分析的成绩'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
