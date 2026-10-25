// 手动视觉检查：flutter test --no-pub tool/questionnaire_preview_test.dart
// 可通过 QUESTIONNAIRE_PREVIEW_FONT 指定本机中文字体，图片生成在 build/。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/questionnaire_models.dart';
import 'package:smart_hunan_agri/pages/questionnaire_detail_page.dart';
import 'package:smart_hunan_agri/pages/questionnaire_list_page.dart';
import 'package:smart_hunan_agri/services/questionnaire_service.dart';

const exampleItem = QuestionnaireItem(
  dm: 'sample',
  title: '国庆假期学生去向登记',
  startTime: '',
  endTime: '2099-10-08 18:00:00',
  taskTimeM: 'sample-task',
);

class PreviewService extends QuestionnaireService {
  @override
  Future<List<QuestionnaireItem>> fetchList() async => [
    exampleItem,
    const QuestionnaireItem(
      dm: 'sample2',
      title: '学生住宿信息核对',
      startTime: '',
      endTime: '2099-10-12 18:00:00',
      taskTimeM: 'sample2-task',
    ),
    const QuestionnaireItem(
      dm: 'sample3',
      title: '新学期学生信息登记',
      startTime: '',
      endTime: '2000-09-15 18:00:00',
      taskTimeM: 'sample3-task',
      doneInd: '1',
    ),
  ];

  @override
  Future<QuestionnaireDetail> fetchDetail(QuestionnaireItem item) async =>
      const QuestionnaireDetail(
        dm: 'sample',
        title: '国庆假期学生去向登记',
        jgM: 'sample-result',
        desc: '请如实登记假期去向及联系方式，便于辅导员掌握同学们的出行安排。',
        questions: [
          QuestionnaireQuestion(
            dm: 'choice',
            title: '你的假期安排是什么？',
            stType: '1',
            required: true,
            options: [
              QuestionnaireOption(dm: 'a', name: '回家'),
              QuestionnaireOption(dm: 'b', name: '留校'),
              QuestionnaireOption(dm: 'c', name: '外出旅行或其他安排'),
            ],
          ),
          QuestionnaireQuestion(
            dm: 'text',
            title: '假期居住地址',
            stType: '4',
            txType: '1',
            required: true,
            desc: '请填写到区县及街道，方便联系。',
          ),
          QuestionnaireQuestion(
            dm: 'date',
            title: '预计返校日期',
            stType: '4',
            txType: '3',
            required: true,
          ),
        ],
      );
}

void main() {
  testWidgets('生成问卷列表与答题页的浅色、深色预览', (tester) async {
    final systemFont = '${Platform.environment['SystemRoot']}/Fonts/msyh.ttc';
    final fontPath =
        Platform.environment['QUESTIONNAIRE_PREVIEW_FONT'] ??
        (Platform.isWindows && File(systemFont).existsSync()
            ? systemFont
            : null);
    if (fontPath != null) {
      await tester.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        await (FontLoader(
          'QuestionnairePreview',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
    }
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = PreviewService();
    for (final brightness in Brightness.values) {
      for (final kind in ['list', 'detail']) {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: fontPath == null ? null : 'QuestionnairePreview',
                scaffoldBackgroundColor: brightness == Brightness.dark
                    ? const Color(0xFF121716)
                    : const Color(0xFFF7F8F5),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                ),
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF486A5A),
                  brightness: brightness,
                ),
              ),
              home: kind == 'list'
                  ? QuestionnaireListPage(service: service)
                  : QuestionnaireDetailPage(
                      item: exampleItem,
                      service: service,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (kind == 'detail') {
          await tester.tap(find.text('回家'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            'build/questionnaire_previews/$kind-${brightness.name}.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
