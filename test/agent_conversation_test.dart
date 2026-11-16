import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart' hide completion;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/agent_models.dart';
import 'package:smart_hunan_agri/services/agent_conversation_store.dart';
import 'package:smart_hunan_agri/services/agent_tool_registry.dart';

import 'agent_service_test.dart'
    show
        config,
        AgentAdapter,
        serviceWith,
        contextFor,
        completion,
        jsonResponse,
        toolCall;

AgentConversation sampleConversation({
  String id = 'chat-1',
  bool pending = false,
}) => AgentConversation(
  id: id,
  title: '植物学课程',
  updatedAt: DateTime(2026, 10, 5),
  pending: pending,
  messages: [
    const AgentDisplayMessage('user', '今天有哪些课？'),
    if (!pending)
      const AgentDisplayMessage(
        'assistant',
        '今天有植物学',
        reasoning: '根据课表查询结果整理课程。',
        model: 'test-model',
        durationMs: 1200,
        usage: AgentTokenUsage(
          inputTokens: 50,
          outputTokens: 12,
          requests: 2,
          reportedRequests: 2,
        ),
      ),
  ],
  history: pending
      ? [
          {'role': 'user', 'content': '今天有哪些课？'},
          {'role': 'assistant', 'content': agentInterruptedText},
        ]
      : [
          {'role': 'user', 'content': '今天有哪些课？'},
          {
            'role': 'assistant',
            'content': null,
            'reasoning_content': '需要查询课表。',
            'tool_calls': [toolCall()],
          },
          {
            'role': 'tool',
            'tool_call_id': 'call-1',
            'content': '{"courses":["植物学"]}',
          },
          {'role': 'assistant', 'content': '今天有植物学'},
        ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('本地存储重启恢复消息、思考、用量和完整工具关联，不包含模型凭据', () async {
    SharedPreferences.setMockInitialValues({});
    final first = AgentConversationStore();
    await first.upsert(sampleConversation());
    final next = AgentConversationStore();
    await next.load();
    final saved = next.active!;
    expect(saved.title, '植物学课程');
    expect(saved.messages.last.reasoning, '根据课表查询结果整理课程。');
    expect(saved.messages.last.durationMs, 1200);
    expect(saved.usage!.inputTokens, 50);
    expect(saved.usage!.outputTokens, 12);
    expect(saved.history[1]['reasoning_content'], '需要查询课表。');
    expect(saved.history[2]['tool_call_id'], 'call-1');
    final encoded = jsonEncode(saved.toJson());
    expect(encoded, isNot(contains(config.apiKey)));
    expect(encoded, isNot(contains('Authorization')));
    expect(saved.exportText(), contains('思考内容（模型返回）'));
    expect(saved.exportText(), contains('输入 Token：50'));
    // Tool protocol is persisted but never dumped into user-facing exports.
    expect(saved.exportText(), isNot(contains('tool_call_id')));
  });

  test('崩溃重启后未完成请求显示中断提示，不自动重放工具', () async {
    String? raw;
    final first = AgentConversationStore(
      read: () async => raw,
      write: (v) async {
        raw = v;
      },
    );
    await first.upsert(sampleConversation(pending: true));
    final next = AgentConversationStore(
      read: () async => raw,
      write: (v) async {
        raw = v;
      },
    );
    await next.load();
    expect(next.active!.pending, isFalse);
    expect(next.active!.messages.last.incomplete, isTrue);
    expect(next.active!.messages.last.text, agentInterruptedText);
    expect(next.active!.history.last['content'], agentInterruptedText);
    await next.retrySave();
    final third = AgentConversationStore(read: () async => raw);
    await third.load();
    expect(third.active!.messages.where((m) => m.incomplete), hasLength(1));
  });

  test('新建和切换保留旧会话，重命名和删除结果可跨重启恢复', () async {
    String? raw;
    final store = AgentConversationStore(
      read: () async => raw,
      write: (v) async {
        raw = v;
      },
    );
    await store.upsert(sampleConversation());
    await store.select(null);
    expect(store.active, isNull);
    expect(store.conversations, hasLength(1));
    await store.upsert(sampleConversation(id: 'chat-2'));
    await store.select('chat-1');
    await store.rename('chat-1', '课程安排');
    await store.delete('chat-2');
    final next = AgentConversationStore(read: () async => raw);
    await next.load();
    expect(next.conversations, hasLength(1));
    expect(next.active!.title, '课程安排');
    await store.clear();
    final cleared = AgentConversationStore(read: () async => raw);
    await cleared.load();
    expect(cleared.conversations, isEmpty);
    expect(cleared.active, isNull);
  });

  test('异步写入按顺序完成，迟到保存不能恢复已删除会话', () async {
    final gate = Completer<void>();
    String? raw;
    var writes = 0;
    final store = AgentConversationStore(
      read: () async => null,
      write: (v) async {
        writes++;
        if (writes == 1) await gate.future;
        raw = v;
      },
    );
    await store.load();
    final saving = store.upsert(sampleConversation());
    await Future<void>.delayed(Duration.zero);
    final clearing = store.clear();
    await Future<void>.delayed(Duration.zero);
    expect(store.conversations, isEmpty);
    gate.complete();
    await Future.wait([saving, clearing]);
    final restored = AgentConversationStore(read: () async => raw);
    await restored.load();
    expect(restored.conversations, isEmpty);
    expect(writes, 2);
  });

  test('加载失败不覆盖原记录，保存失败可重试且写入队列不会失效', () async {
    var readsFail = true;
    var writesFail = true;
    var writes = 0;
    String? raw;
    final store = AgentConversationStore(
      read: () async {
        if (readsFail) throw StateError('unavailable');
        return raw;
      },
      write: (v) async {
        writes++;
        if (writesFail) throw StateError('disk full');
        raw = v;
      },
    );
    await store.load();
    expect(store.loadError, isNotNull);
    await expectLater(
      store.upsert(sampleConversation()),
      throwsA(isA<AgentException>()),
    );
    expect(writes, 0);
    readsFail = false;
    await store.retryLoad();
    await expectLater(
      store.upsert(sampleConversation()),
      throwsA(isA<AgentException>()),
    );
    expect(store.saveError, isNotNull);
    expect(store.active, isNotNull);
    writesFail = false;
    await store.retrySave();
    expect(store.saveError, isNull);
    expect(jsonDecode(raw!)['conversations'], hasLength(1));
  });

  test('工具多轮保留服务商思考字段，累计真实输入输出而不重复加缓存和思考 Token', () async {
    final adapter = AgentAdapter(
      (_, n) => jsonResponse({
        ...completion(
          n == 1
              ? {
                  'content': null,
                  'reasoning_content': '先查询课表。',
                  'tool_calls': [toolCall()],
                }
              : {'content': '今天有植物学', 'reasoning_content': '据工具结果整理。'},
        ),
        'model': 'provider-model',
        'usage': n == 1
            ? {
                'prompt_tokens': 20,
                'completion_tokens': 5,
                'prompt_tokens_details': {'cached_tokens': 4},
                'completion_tokens_details': {'reasoning_tokens': 2},
              }
            : {
                'prompt_tokens': 40,
                'completion_tokens': 10,
                'prompt_cache_hit_tokens': 3,
              },
      }),
    );
    final reply = await serviceWith(adapter).chat(
      config: config,
      history: [
        {'role': 'user', 'content': '今天有哪些课？'},
      ],
      tools: AgentToolRegistry([
        AgentTool(
          name: 'query_timetable',
          label: '查课表',
          description: '',
          run: (_, _) async => {
            'courses': ['植物学'],
          },
        ),
      ]),
      context: contextFor(),
    );
    expect(reply.reasoning, '先查询课表。\n\n据工具结果整理。');
    expect(reply.model, 'provider-model');
    expect(reply.usage!.inputTokens, 60);
    expect(reply.usage!.outputTokens, 15);
    expect(reply.usage!.cachedTokens, 7);
    expect(reply.usage!.reasoningTokens, 2);
    expect(reply.usage!.requests, 2);
    expect(reply.usage!.reportedRequests, 2);
    expect(
      (adapter.payloads[1]['messages'] as List)[2]['reasoning_content'],
      '先查询课表。',
    );
    expect(reply.history.last['reasoning_content'], '据工具结果整理。');
  });

  test('未返回、异常和部分用量保持未知，不伪造零或完整统计', () {
    final unknown = AgentTokenUsage.fromProvider(null);
    expect(unknown.inputTokens, isNull);
    expect(unknown.outputTokens, isNull);
    expect(unknown.reportedRequests, 0);
    final malformed = AgentTokenUsage.fromProvider({
      'prompt_tokens': -1,
      'completion_tokens': '9',
    });
    expect(malformed.inputTokens, isNull);
    expect(malformed.outputTokens, isNull);
    final known = AgentTokenUsage.fromProvider({
      'input_tokens': 8,
      'output_tokens': 0,
      'cached_tokens': 2,
    });
    final partial = unknown.plus(known);
    expect(partial.inputTokens, 8);
    expect(partial.outputTokens, 0);
    expect(partial.requests, 2);
    expect(partial.reportedRequests, 1);
  });
}
