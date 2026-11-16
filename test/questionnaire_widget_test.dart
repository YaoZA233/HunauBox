import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/questionnaire_models.dart';
import 'package:smart_hunan_agri/pages/questionnaire_detail_page.dart';
import 'package:smart_hunan_agri/pages/questionnaire_list_page.dart';
import 'package:smart_hunan_agri/services/questionnaire_service.dart';

const pending = QuestionnaireItem(
  dm: 'survey',
  title: '国庆假期去向登记',
  startTime: '',
  endTime: '',
  taskTimeM: 'task',
);
const submitted = QuestionnaireItem(
  dm: 'survey-done',
  title: '已完成的登记',
  startTime: '',
  endTime: '',
  taskTimeM: 'task-done',
  doneInd: '1',
);
const questions = [
  QuestionnaireQuestion(
    dm: 'choice',
    title: '假期去向',
    stType: '1',
    required: true,
    options: [
      QuestionnaireOption(dm: 'home', name: '回家'),
      QuestionnaireOption(dm: 'school', name: '留校'),
    ],
  ),
  QuestionnaireQuestion(
    dm: 'text',
    title: '填写目的地',
    stType: '4',
    txType: '1',
    required: true,
  ),
];
const detail = QuestionnaireDetail(
  dm: 'survey',
  title: '国庆假期去向登记',
  desc: '请如实登记假期去向，便于辅导员联系。',
  jgM: 'result',
  questions: questions,
);

class FakeService extends QuestionnaireService {
  FakeService({this.items = const [pending, submitted], this.data = detail});
  final List<QuestionnaireItem> items;
  final QuestionnaireDetail data;
  int submissions = 0;
  int listReads = 0;
  Map<String, dynamic>? submittedAnswers;
  QuestionnaireException? failure;

  @override
  Future<List<QuestionnaireItem>> fetchList() async {
    listReads++;
    return items;
  }

  @override
  Future<QuestionnaireDetail> fetchDetail(QuestionnaireItem item) async => data;

  @override
  Future<void> submit({
    required QuestionnaireItem item,
    required QuestionnaireDetail detail,
    required Map<String, dynamic> answers,
  }) async {
    submissions++;
    submittedAnswers = answers;
    if (failure != null) throw failure!;
  }
}

Widget app(
  Widget page, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF216B52),
      brightness: brightness,
    ),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

Future<void> fill(WidgetTester tester) async {
  await tester.tap(find.text('回家'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('answer-text')));
  await tester.enterText(find.byKey(const ValueKey('answer-text')), '湖南长沙');
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('多选切换、日期选择和联系电话输入可提交', (tester) async {
    const data = QuestionnaireDetail(
      dm: 'survey',
      title: '去向登记',
      jgM: 'result',
      questions: [
        QuestionnaireQuestion(
          dm: 'multi',
          title: '出行方式',
          stType: '2',
          required: true,
          options: [
            QuestionnaireOption(dm: 'train', name: '火车'),
            QuestionnaireOption(dm: 'bus', name: '汽车'),
          ],
        ),
        QuestionnaireQuestion(
          dm: 'date',
          title: '返校日期',
          stType: '4',
          txType: '3',
          required: true,
        ),
        QuestionnaireQuestion(
          dm: 'phone',
          title: '联系电话',
          stType: '4',
          txType: '2',
          required: true,
        ),
      ],
    );
    final service = FakeService(data: data);
    await tester.pumpWidget(
      app(QuestionnaireDetailPage(item: pending, service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('火车'));
    await tester.tap(find.text('汽车'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('汽车'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('请选择日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('请选择日期'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('answer-phone')));
    await tester.enterText(
      find.byKey(const ValueKey('answer-phone')),
      'abc123+45',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(find.text('已填写 3 / 3 题'), findsOneWidget);
    await tester.tap(find.text('提交问卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(service.submittedAnswers!['multi'], ['train']);
    expect(
      service.submittedAnswers!['date'],
      matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
    );
    expect(service.submittedAnswers!['phone'], '123+45');
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表筛选和打开问卷，呈现题型与固定提交按钮', (tester) async {
    final service = FakeService();
    await tester.pumpWidget(app(QuestionnaireListPage(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('国庆假期去向登记'), findsOneWidget);
    expect(find.text('已完成的登记'), findsOneWidget);
    await tester.tap(find.text('待填写 1'));
    await tester.pumpAndSettle();
    expect(find.text('已完成的登记'), findsNothing);
    await tester.tap(find.text('国庆假期去向登记'));
    await tester.pumpAndSettle();
    expect(find.text('单选'), findsOneWidget);
    expect(find.text('提交问卷'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('必填校验不调用提交，完成填写并确认后只提交一次', (tester) async {
    final service = FakeService();
    await tester.pumpWidget(app(QuestionnaireListPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('国庆假期去向登记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交问卷'));
    await tester.pumpAndSettle();
    expect(service.submissions, 0);
    expect(find.text('请完成这道必填题'), findsOneWidget);
    await fill(tester);
    expect(find.text('已填写 2 / 2 题'), findsOneWidget);
    await tester.tap(find.text('提交问卷'));
    await tester.pumpAndSettle();
    expect(service.submissions, 0);
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(service.submissions, 1);
    expect(service.submittedAnswers, {'choice': 'home', 'text': '湖南长沙'});
    expect(service.listReads, 2);
    expect(find.text('学工问卷'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提交结果不明时禁用重复提交，返回刷新列表', (tester) async {
    final service = FakeService()
      ..failure = const QuestionnaireException(
        '暂时无法确认提交结果，请返回列表核对状态',
        requiresStatusCheck: true,
      );
    await tester.pumpWidget(app(QuestionnaireListPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('国庆假期去向登记'));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.tap(find.text('提交问卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(find.text('提交问卷'), findsNothing);
    expect(find.text('返回核对'), findsOneWidget);
    expect(service.submissions, 1);
    await tester.tap(find.text('返回核对'));
    await tester.pumpAndSettle();
    expect(service.listReads, 2);
  });

  testWidgets('退出已填写内容时提示，继续填写保留答案', (tester) async {
    await tester.pumpWidget(app(QuestionnaireListPage(service: FakeService())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('国庆假期去向登记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回家'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('退出填写？'), findsOneWidget);
    await tester.tap(find.text('继续填写'));
    await tester.pumpAndSettle();
    expect(find.text('已填写 1 / 2 题'), findsOneWidget);
  });

  testWidgets('已提交答案回填并只读', (tester) async {
    final data = QuestionnaireDetail.fromJson({
      'dm': 'survey',
      'mc': '假期登记',
      'jgM': 'result',
      'canSubmit': '1',
      'stList': [
        {
          'dm': 'choice',
          'stmc': '去向',
          'stType': '1',
          'jg': '回家',
          'stxxList': [
            {'dm': 'home', 'mc': '回家'},
            {'dm': 'school', 'mc': '留校'},
          ],
        },
        {'dm': 'text', 'stmc': '地址', 'stType': '4', 'jg': '长沙'},
      ],
    });
    final service = FakeService(data: data);
    await tester.pumpWidget(
      app(QuestionnaireDetailPage(item: submitted, service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('提交问卷'), findsNothing);
    final radios = tester.widgetList<RadioListTile<String>>(
      find.byType(RadioListTile<String>),
    );
    expect(radios.every((radio) => !radio.enabled!), isTrue);
    final text = tester.widget<TextField>(
      find.byKey(const ValueKey('answer-text')),
    );
    expect(text.readOnly, isTrue);
    expect(text.controller!.text, '长沙');
    expect(service.submissions, 0);
  });

  for (final brightness in Brightness.values) {
    testWidgets('320px 窄屏、大字体和 ${brightness.name} 模式无布局溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeService();
      await tester.pumpWidget(
        app(
          QuestionnaireListPage(service: service),
          brightness: brightness,
          scale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('国庆假期去向登记'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('answer-text')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
