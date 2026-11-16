import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/agent_models.dart';
import 'package:smart_hunan_agri/models/course_model.dart';
import 'package:smart_hunan_agri/services/agent_service.dart';
import 'package:smart_hunan_agri/services/agent_settings_store.dart';
import 'package:smart_hunan_agri/services/agent_tool_registry.dart';
import 'package:smart_hunan_agri/services/campus_agent_tools.dart';

const config = AgentConfig(
  enabled: true,
  apiUrl: 'https://model.example/v1',
  apiKey: 'fake-test-key',
  model: 'test-model',
);
const userMessage = {'role': 'user', 'content': '今天有哪些课？'};
Map<String, dynamic> completion(Map<String, dynamic> message) => {
  'choices': [
    {'message': message},
  ],
};
Map<String, dynamic> toolCall({
  String id = 'call-1',
  String name = 'query_timetable',
  dynamic args = '{}',
}) => {
  'id': id,
  'type': 'function',
  'function': {'name': name, 'arguments': args},
};

class AgentAdapter implements HttpClientAdapter {
  AgentAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions, int) handler;
  final requests = <RequestOptions>[];
  final payloads = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (stream != null) {
      final bytes = await stream.fold<List<int>>([], (a, b) => a..addAll(b));
      payloads.add(Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes))));
    }
    return handler(options, requests.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
AgentService serviceWith(AgentAdapter adapter) =>
    AgentService(dio: Dio()..httpClientAdapter = adapter);
AgentToolContext contextFor({CancelToken? token, AgentConfirmation? confirm}) =>
    AgentToolContext(
      cancelToken: token ?? CancelToken(),
      confirm: confirm ?? ((_, _) async => false),
    );

void main() {
  group('Agent 配置与安全存储', () {
    test('默认关闭，不含默认 URL、模型或 Key', () {
      const value = AgentConfig();
      expect(value.enabled, isFalse);
      expect(value.apiUrl, isEmpty);
      expect(value.apiKey, isEmpty);
      expect(value.isConfigured, isFalse);
    });
    test('Base URL 与完整接口地址不会重复拼接', () {
      expect(config.endpoint, 'https://model.example/v1/chat/completions');
      expect(
        config
            .copyWith(apiUrl: ' https://model.example/v1/chat/completions/// ')
            .endpoint,
        'https://model.example/v1/chat/completions',
      );
    });
    for (final url in [
      'http://model.example/v1',
      'https://user:password@model.example/v1',
      'https://model.example/v1?key=x',
      'https://model.example/v1#token',
      'not a URL',
      '',
    ]) {
      test('不安全或无效 URL 不允许发送：$url', () {
        expect(config.copyWith(apiUrl: url).isConfigured, isFalse);
      });
    }
    test('持久保存开关与配置，重启后恢复，关闭不删除用户配置', () async {
      String? value;
      final store = AgentSettingsStore(
        read: () async => value,
        write: (v) async {
          value = v;
        },
        delete: () async {
          value = null;
        },
      );
      await store.load();
      expect(store.config.enabled, isFalse);
      await store.save(config);
      final next = AgentSettingsStore(
        read: () async => value,
        write: (v) async {
          value = v;
        },
      );
      await next.load();
      expect(next.config.model, config.model);
      expect(next.config.enabled, isTrue);
      await next.setEnabled(false);
      expect(next.config.apiKey, config.apiKey);
      expect(AgentConfig.decode(value!).enabled, isFalse);
      await store.clear();
      expect(store.config.enabled, isFalse);
      expect(value, isNull);
    });
    test('读取失败保持关闭，写入失败不假装保存成功', () async {
      final store = AgentSettingsStore(
        read: () async => throw StateError('storage unavailable'),
      );
      await store.load();
      expect(store.config.enabled, isFalse);
      expect(store.error, isNotNull);
      await expectLater(store.save(config), throwsA(isA<AgentException>()));
      final writeFail = AgentSettingsStore(
        read: () async => null,
        write: (_) async => throw StateError('failure'),
      );
      await expectLater(writeFail.save(config), throwsA(isA<AgentException>()));
      expect(writeFail.config.enabled, isFalse);
      expect(writeFail.saving, isFalse);
    });
    test('load 与 save 同时发生不会用旧读取结果覆盖新配置', () async {
      final gate = Completer<String?>();
      String? saved;
      final store = AgentSettingsStore(
        read: () => gate.future,
        write: (v) async {
          saved = v;
        },
      );
      final saving = store.save(config);
      gate.complete(null);
      await saving;
      expect(store.config.enabled, isTrue);
      expect(AgentConfig.decode(saved!).model, config.model);
    });
  });

  test('清除与保存同时发生，迟到写入不会重启 Agent 或恢复 Key', () async {
    final gate = Completer<void>();
    String? record;
    final store = AgentSettingsStore(
      read: () async => null,
      write: (value) async {
        await gate.future;
        record = value;
      },
      delete: () async {
        record = null;
      },
    );
    await store.load();
    final saving = store.save(config);
    await Future<void>.delayed(Duration.zero);
    final clearing = store.clear();
    await Future<void>.delayed(Duration.zero);
    expect(store.config.enabled, isFalse);
    expect(store.saving, isTrue);
    gate.complete();
    await saving;
    await clearing;
    expect(store.config.enabled, isFalse);
    expect(store.config.apiKey, isEmpty);
    expect(record, isNull);
  });

  group('Agent 模型协议（完全模拟 HTTP）', () {
    test('仅连接用户 URL，独立授权头，没有校园 Cookie，闲聊不执行工具', () async {
      final adapter = AgentAdapter(
        (_, _) =>
            jsonResponse(completion({'role': 'assistant', 'content': '你好'})),
      );
      var toolRuns = 0;
      final tools = AgentToolRegistry([
        AgentTool(
          name: 'query_timetable',
          label: '查询课表',
          description: '课表',
          run: (_, _) async {
            toolRuns++;
            return {};
          },
        ),
      ]);
      final reply = await serviceWith(adapter).chat(
        config: config,
        history: [userMessage],
        tools: tools,
        context: contextFor(),
      );
      expect(reply.text, '你好');
      expect(toolRuns, 0);
      final r = adapter.requests.single;
      expect(r.uri.toString(), config.endpoint);
      expect(r.headers['Authorization'], 'Bearer fake-test-key');
      expect(r.headers.keys.any((k) => k.toLowerCase() == 'cookie'), isFalse);
      expect(r.followRedirects, isFalse);
      expect(adapter.payloads.single['model'], config.model);
    });
    test('多轮工具调用回传结果，保留工具关联历史', () async {
      var runs = 0;
      final adapter = AgentAdapter(
        (_, n) => jsonResponse(
          completion(
            n == 1
                ? {
                    'role': 'assistant',
                    'tool_calls': [toolCall(args: '{"today":true}')],
                    'content': null,
                  }
                : {'role': 'assistant', 'content': '今天有一节课'},
          ),
        ),
      );
      final tools = AgentToolRegistry([
        AgentTool(
          name: 'query_timetable',
          label: '查询课表',
          description: '课表',
          properties: {
            'today': {'type': 'boolean'},
          },
          run: (a, _) async {
            runs++;
            expect(a['today'], true);
            return {
              'courses': ['植物学'],
            };
          },
        ),
      ]);
      final activity = <String>[];
      final reply = await serviceWith(adapter).chat(
        config: config,
        history: [userMessage],
        tools: tools,
        context: contextFor(),
        onActivity: activity.add,
      );
      expect(runs, 1);
      expect(reply.text, '今天有一节课');
      final second = adapter.payloads[1]['messages'] as List;
      expect(second.last['role'], 'tool');
      expect(second.last['tool_call_id'], 'call-1');
      expect(jsonDecode(second.last['content'])['courses'], ['植物学']);
      expect(reply.history.map((m) => m['role']), [
        'user',
        'assistant',
        'tool',
        'assistant',
      ]);
      expect(activity, contains('正在查询课表'));
    });
    for (final argument in [
      'bad JSON',
      '[]',
      '{"confirmed":true}',
      '{"today":"true"}',
    ]) {
      test('非法工具参数 $argument 不执行', () async {
        var runs = 0;
        final adapter = AgentAdapter(
          (_, n) => jsonResponse(
            completion(
              n == 1
                  ? {
                      'tool_calls': [toolCall(args: argument)],
                    }
                  : {'content': '参数无效'},
            ),
          ),
        );
        final tools = AgentToolRegistry([
          AgentTool(
            name: 'query_timetable',
            label: '查询课表',
            description: '',
            properties: {
              'today': {'type': 'boolean'},
            },
            run: (_, _) async {
              runs++;
              return {};
            },
          ),
        ]);
        await serviceWith(adapter).chat(
          config: config,
          history: [userMessage],
          tools: tools,
          context: contextFor(),
        );
        expect(runs, 0);
        expect(
          jsonDecode((adapter.payloads[1]['messages'] as List).last['content']),
          contains('error'),
        );
      });
    }
    test('未知工具不执行，工具内部错误不会泄露底层异常', () async {
      final registry = AgentToolRegistry([
        AgentTool(
          name: 'broken',
          label: '查询',
          description: '',
          run: (_, _) async => throw StateError('secret-cookie-do-not-expose'),
        ),
      ]);
      final unknown = await registry.execute('anything', {}, contextFor());
      final broken = await registry.execute('broken', {}, contextFor());
      expect(unknown.toString(), contains('不支持'));
      expect(broken.toString(), isNot(contains('secret-cookie')));
    });
    test('重复工具调用 ID 不重复执行', () async {
      var runs = 0;
      final adapter = AgentAdapter(
        (_, n) => jsonResponse(
          completion(
            n < 3
                ? {
                    'tool_calls': [toolCall()],
                  }
                : {'content': '完成'},
          ),
        ),
      );
      final tools = AgentToolRegistry([
        AgentTool(
          name: 'query_timetable',
          label: '',
          description: '',
          run: (_, _) async {
            runs++;
            return {};
          },
        ),
      ]);
      await serviceWith(adapter).chat(
        config: config,
        history: [userMessage],
        tools: tools,
        context: contextFor(),
      );
      expect(runs, 1);
      expect(adapter.requests, hasLength(3));
    });
    test('循环最多六轮，防止无限请求和工具执行', () async {
      var runs = 0;
      final adapter = AgentAdapter(
        (_, n) => jsonResponse(
          completion({
            'tool_calls': [toolCall(id: 'call-$n')],
          }),
        ),
      );
      final tools = AgentToolRegistry([
        AgentTool(
          name: 'query_timetable',
          label: '',
          description: '',
          run: (_, _) async {
            runs++;
            return {};
          },
        ),
      ]);
      await expectLater(
        serviceWith(adapter).chat(
          config: config,
          history: [userMessage],
          tools: tools,
          context: contextFor(),
        ),
        throwsA(predicate<AgentException>((e) => e.message.contains('上限'))),
      );
      expect(adapter.requests, hasLength(AgentService.maxRounds));
      expect(runs, AgentService.maxRounds);
    });
    test('用户取消写操作确认不写入；确认期间关闭请求也不会写入', () async {
      var writes = 0;
      final tool = AgentTool(
        name: 'write',
        label: '',
        description: '',
        run: (_, ctx) async {
          if (!await ctx.askConfirmation('确认', '修改内容')) {
            return {'cancelled': true};
          }
          writes++;
          return {'success': true};
        },
      );
      final registry = AgentToolRegistry([tool]);
      await registry.execute('write', {}, contextFor());
      expect(writes, 0);
      final token = CancelToken();
      await expectLater(
        registry.execute(
          'write',
          {},
          contextFor(
            token: token,
            confirm: (_, _) async {
              token.cancel();
              return true;
            },
          ),
        ),
        throwsA(isA<AgentException>()),
      );
      expect(writes, 0);
    });
    for (final value in [
      config.copyWith(enabled: false),
      config.copyWith(apiKey: ''),
      config.copyWith(apiUrl: 'http://model.example/v1'),
    ]) {
      test('未开启或未配置不请求模型', () async {
        final adapter = AgentAdapter(
          (_, _) => throw StateError('must not call'),
        );
        await expectLater(
          serviceWith(adapter).chat(
            config: value,
            history: [userMessage],
            tools: AgentToolRegistry([]),
            context: contextFor(),
          ),
          throwsA(isA<AgentException>()),
        );
        expect(adapter.requests, isEmpty);
      });
    }
    for (final status in [307, 401, 404, 429, 500]) {
      test('HTTP $status 错误不会回显服务端密钥或跟随重定向', () async {
        final adapter = AgentAdapter(
          (_, _) => jsonResponse({
            'error': 'fake-test-key secret-body',
          }, status: status),
        );
        await expectLater(
          serviceWith(adapter).chat(
            config: config,
            history: [userMessage],
            tools: AgentToolRegistry([]),
            context: contextFor(),
          ),
          throwsA(
            predicate<AgentException>(
              (e) =>
                  !e.message.contains('fake-test-key') &&
                  !e.message.contains('secret-body'),
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.followRedirects, isFalse);
      });
    }
    test('格式异常不会被当成有效回复', () async {
      final adapter = AgentAdapter(
        (_, _) => jsonResponse({'not_choices': 'response'}),
      );
      await expectLater(
        serviceWith(adapter).chat(
          config: config,
          history: [userMessage],
          tools: AgentToolRegistry([]),
          context: contextFor(),
        ),
        throwsA(isA<AgentException>()),
      );
    });
  });

  group('校园查询参数', () {
    test('空教室大节映射到财务以外的教务实际节次编码', () {
      expect(agentClassroomSectionCode(1), '0102');
      expect(agentClassroomSectionCode(3), '0506');
      expect(agentClassroomSectionCode(6), '1112');
      expect(
        () => agentClassroomSectionCode(0),
        throwsA(isA<AgentException>()),
      );
    });
    const courses = [
      CourseModel(
        id: 'course',
        name: '植物学',
        teacher: '老师',
        classroom: '教学楼 101',
        weeks: '1-16(周)',
        periods: '1-2',
        dayOfWeek: 1,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ];
    test('今日课程必须按学期起点和真实周次过滤', () {
      expect(
        filterAgentCourses(
          courses,
          {'today': true},
          now: DateTime(2026, 9, 7),
          firstWeekMonday: DateTime(2026, 9, 7),
        ),
        hasLength(1),
      );
      expect(
        filterAgentCourses(
          courses,
          {'today': true},
          now: DateTime(2026, 9, 8),
          firstWeekMonday: DateTime(2026, 9, 7),
        ),
        isEmpty,
      );
      expect(
        filterAgentCourses(
          courses,
          {'today': true},
          now: DateTime(2027, 9, 6),
          firstWeekMonday: DateTime(2026, 9, 7),
        ),
        isEmpty,
      );
      expect(
        () => filterAgentCourses(courses, {
          'today': true,
        }, now: DateTime(2026, 9, 7)),
        throwsA(isA<AgentException>()),
      );
    });
    test('日期解析拒绝自动归一化的非法日期', () {
      expect(
        parseAgentDeadline('2026-10-02 18:00:00'),
        DateTime(2026, 10, 2, 18),
      );
      for (final value in [
        '2026-02-30 18:00:00',
        '2026-13-01 18:00:00',
        '明天',
        '2026-10-02T18:00:00Z',
      ]) {
        expect(() => parseAgentDeadline(value), throwsA(isA<AgentException>()));
      }
    });
  });
}
