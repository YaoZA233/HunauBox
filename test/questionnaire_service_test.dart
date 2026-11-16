import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/questionnaire_models.dart';
import 'package:smart_hunan_agri/services/questionnaire_service.dart';

const item = QuestionnaireItem(
  dm: 'survey',
  title: '假期去向登记',
  startTime: '',
  endTime: '',
  taskTimeM: 'task-1',
);

Map<String, dynamic> row(int id) => {
  'DM': 'survey-$id',
  'MC': '问卷 $id',
  'TASK_TIME_M': 'task-$id',
};

Map<String, dynamic> detailJson({String canSubmit = '1'}) => {
  'dm': 'survey',
  'mc': '假期去向登记',
  'jgM': 'result-1',
  'canSubmit': canSubmit,
  'stList': [
    {
      'dm': 'choice',
      'stmc': '去向',
      'stType': '2',
      'btInd': '1',
      'stxxList': [
        {'dm': 'a', 'mc': '回家'},
        {'dm': 'b', 'mc': '留校'},
      ],
    },
    {'dm': 'text', 'stmc': '说明', 'stType': '4', 'txType': '1', 'btInd': '1'},
  ],
};

class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.handle);
  final ResponseBody Function(RequestOptions) handle;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  test('问卷 JSON 中的 HTML 和登录说明不会触发不必要的重登', () async {
    final adapter = StubAdapter(
      (request) => jsonBody({
        'aaData': [
          {...row(1), 'MC': '<html>cas/login 登录说明'},
        ],
      }),
    );
    final items = await QuestionnaireService(
      dio: Dio()..httpClientAdapter = adapter,
      reauthenticate: () async => throw StateError('有效 JSON 不应重登'),
    ).fetchList();
    expect(items.single.title, contains('cas/login'));
    expect(adapter.requests, hasLength(1));
  });

  group('问卷协议与校验', () {
    test('保留任务 ID，识别数字状态和 HTML 标题', () {
      final parsed = QuestionnaireItem.fromJson({
        ...row(1),
        'MC': '<b>假期去向</b>',
        'DONE_IND': 1,
      });
      expect(parsed.taskTimeM, 'task-1');
      expect(parsed.title, '假期去向');
      expect(parsed.isSubmitted, isTrue);
      expect(parsed.isPending, isFalse);
    });

    test('未来问卷和已截止问卷不属于待办', () {
      final future = QuestionnaireItem.fromJson({
        ...row(1),
        'KSSJ': '2999-01-01 00:00:00',
      });
      final expired = QuestionnaireItem.fromJson({
        ...row(2),
        'JSSJ': '2000-01-01 00:00:00',
      });
      expect(future.statusLabel, '未开始');
      expect(future.isPending, isFalse);
      expect(expired.statusLabel, '已截止');
      expect(expired.isPending, isFalse);
    });

    test('服务端选项名称回填为 ID，多选去重且不模糊匹配', () {
      final q = QuestionnaireQuestion.fromJson({
        'dm': 'q',
        'stType': '2',
        'jg': '回家，b;回家;家',
        'stxxList': [
          {'dm': 'a', 'mc': '回家'},
          {'dm': 'b', 'mc': '留校'},
        ],
      });
      expect(q.initialAnswer, ['a', 'b']);
    });

    test('多选使用重复字段，文本安全编码，附带结果 ID', () {
      final detail = QuestionnaireDetail.fromJson(detailJson());
      final encoded = QuestionnaireService.encodeAnswers(detail, {
        'choice': ['a', 'b'],
        'text': '地址 & 电话=123+456',
      });
      final parsed = Uri.splitQueryString(encoded);
      expect(encoded, contains('choice=a&choice=b'));
      expect(parsed['text'], '地址 & 电话=123+456');
      expect(parsed['ks_jgdm'], 'result-1');
      expect(parsed['operationType'], '');
    });

    test('必填为空、伪造选项和未知题型不允许提交', () {
      final detail = QuestionnaireDetail.fromJson(detailJson());
      expect(detail.validate({}), '请填写：去向');
      expect(
        detail.validate({
          'choice': ['wrong'],
          'text': '说明',
        }),
        '请重新选择：去向',
      );
      expect(
        detail.validate({
          'choice': ['a'],
          'text': '  ',
        }),
        '请填写：说明',
      );
      expect(
        detail.validate({
          'choice': ['a'],
          'text': '有效回答',
        }),
        isNull,
      );
      const unsupported = QuestionnaireDetail(
        dm: 's',
        title: '评分',
        jgM: 'r',
        questions: [QuestionnaireQuestion(dm: 'q', title: '评分', stType: '9')],
      );
      expect(unsupported.validate({}), contains('暂不支持'));
    });

    test('日期/电话字段和只读标志解析', () {
      final detail = QuestionnaireDetail.fromJson({
        'dm': 's',
        'jgM': 'r',
        'canSubmit': 0,
        'stList': [
          {'dm': 'date', 'stmc': '返校日期', 'stType': 4, 'txType': 3},
          {'dm': 'phone', 'stmc': '电话', 'stType': 4, 'txType': 2},
        ],
      });
      expect(detail.canSubmit, isFalse);
      expect(detail.questions.first.isDate, isTrue);
      expect(detail.questions.last.isPhone, isTrue);
    });
  });

  group('问卷 HTTP 行为（模拟服务器）', () {
    test('读取下一页，不丢失第 51 项', () async {
      final adapter = StubAdapter((request) {
        final start = int.parse(
          request.queryParameters['iDisplayStart'].toString(),
        );
        return jsonBody({
          'aaData': start == 0 ? List.generate(50, row) : [row(50)],
          'iTotalDisplayRecords': 51,
        });
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final result = await QuestionnaireService(dio: dio).fetchList();
      expect(result.length, 51);
      expect(adapter.requests.length, 2);
      expect(adapter.requests.last.queryParameters['iDisplayStart'], '50');
    });

    test('列表过期会话仅登录一次并重试一次 GET', () async {
      var count = 0;
      var logins = 0;
      final adapter = StubAdapter(
        (request) => count++ == 0
            ? ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': ['/cas/login'],
                },
              )
            : jsonBody({'aaData': []}),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = QuestionnaireService(
        dio: dio,
        reauthenticate: () async {
          logins++;
          return true;
        },
      );
      expect(await service.fetchList(), isEmpty);
      expect(logins, 1);
      expect(adapter.requests.length, 2);
      expect(adapter.requests.first.followRedirects, isFalse);
    });

    test('二次登录页和登录失败提供可理解错误', () async {
      final adapter = StubAdapter(
        (request) =>
            ResponseBody.fromString('<!DOCTYPE html><HTML>登录</HTML>', 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = QuestionnaireService(
        dio: dio,
        reauthenticate: () async => true,
      );
      await expectLater(
        service.fetchList(),
        throwsA(isA<QuestionnaireException>()),
      );
      expect(adapter.requests.length, 2);
    });

    test('提交前 GET 检查状态，POST 表单只发送一次', () async {
      final adapter = StubAdapter(
        (request) => request.method == 'GET'
            ? jsonBody(detailJson())
            : jsonBody({'result': true}),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      await QuestionnaireService(dio: dio).submit(
        item: item,
        detail: QuestionnaireDetail.fromJson(detailJson()),
        answers: {
          'choice': ['a', 'b'],
          'text': '测试',
        },
      );
      expect(adapter.requests.map((e) => e.method), ['GET', 'POST']);
      expect(
        adapter.requests.last.contentType,
        Headers.formUrlEncodedContentType,
      );
      expect(adapter.requests.last.data, contains('choice=a&choice=b'));
    });

    test('问卷关闭时不会发送 POST', () async {
      final adapter = StubAdapter(
        (request) => jsonBody(detailJson(canSubmit: '0')),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      await expectLater(
        QuestionnaireService(dio: dio).submit(
          item: item,
          detail: QuestionnaireDetail.fromJson(detailJson()),
          answers: {
            'choice': ['a'],
            'text': '测试',
          },
        ),
        throwsA(isA<QuestionnaireException>()),
      );
      expect(adapter.requests.every((e) => e.method == 'GET'), isTrue);
    });

    test('POST 跳转不会重发；要求核对结果', () async {
      var logins = 0;
      final adapter = StubAdapter(
        (request) => request.method == 'GET'
            ? jsonBody(detailJson())
            : ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': ['/cas/login'],
                },
              ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final service = QuestionnaireService(
        dio: dio,
        reauthenticate: () async {
          logins++;
          return true;
        },
      );
      await expectLater(
        service.submit(
          item: item,
          detail: QuestionnaireDetail.fromJson(detailJson()),
          answers: {
            'choice': ['a'],
            'text': '测试',
          },
        ),
        throwsA(
          isA<QuestionnaireException>().having(
            (e) => e.requiresStatusCheck,
            '核对状态',
            isTrue,
          ),
        ),
      );
      expect(adapter.requests.where((e) => e.method == 'POST').length, 1);
      expect(logins, 0);
    });

    test('POST 断网或异常响应不允许盲目重试', () async {
      for (final disconnect in [true, false]) {
        final adapter = StubAdapter((request) {
          if (request.method == 'GET') return jsonBody(detailJson());
          if (disconnect) {
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.connectionError,
            );
          }
          return jsonBody({'unexpected': 'response'});
        });
        final dio = Dio()..httpClientAdapter = adapter;
        await expectLater(
          QuestionnaireService(dio: dio).submit(
            item: item,
            detail: QuestionnaireDetail.fromJson(detailJson()),
            answers: {
              'choice': ['a'],
              'text': '测试',
            },
          ),
          throwsA(
            isA<QuestionnaireException>().having(
              (e) => e.requiresStatusCheck,
              '核对状态',
              isTrue,
            ),
          ),
        );
        expect(adapter.requests.where((e) => e.method == 'POST').length, 1);
      }
    });

    test('服务器业务错误保留提示且不自动重试', () async {
      final adapter = StubAdapter(
        (request) => request.method == 'GET'
            ? jsonBody(detailJson())
            : jsonBody({
                'result': false,
                'errorInfoList': ['信息不完整'],
              }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      await expectLater(
        QuestionnaireService(dio: dio).submit(
          item: item,
          detail: QuestionnaireDetail.fromJson(detailJson()),
          answers: {
            'choice': ['a'],
            'text': '测试',
          },
        ),
        throwsA(
          isA<QuestionnaireException>().having(
            (e) => e.message,
            '业务错误',
            '信息不完整',
          ),
        ),
      );
      expect(adapter.requests.length, 2);
    });
  });
}
