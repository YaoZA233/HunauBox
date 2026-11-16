import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide completion;
import 'package:smart_hunan_agri/models/agent_models.dart';
import 'package:smart_hunan_agri/pages/agent_page.dart';
import 'package:smart_hunan_agri/services/agent_conversation_store.dart';
import 'package:smart_hunan_agri/services/agent_service.dart';
import 'package:smart_hunan_agri/services/agent_tool_registry.dart';

import 'agent_service_test.dart'
    show config, AgentAdapter, completion, jsonResponse;
import 'agent_widget_test.dart' show app, memorySettings;
import 'agent_conversation_test.dart' show sampleConversation;

AgentPage pageWith(AgentAdapter adapter) => AgentPage(
  service: AgentService(dio: Dio()..httpClientAdapter = adapter),
  tools: AgentToolRegistry([]),
);

Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.tap(find.byTooltip('发送'));
}

void main() {
  testWidgets('自动保存，页面重建后恢复思考和 Token，继续发送保留工具上下文', (tester) async {
    String? disk;
    AgentConversationStore newStore() => AgentConversationStore(
      read: () async => disk,
      write: (v) async {
        disk = v;
      },
    );
    final store = newStore();
    await store.upsert(sampleConversation());
    await tester.pumpWidget(
      app(
        await memorySettings(config),
        pageWith(AgentAdapter((_, _) => throw StateError('no automatic call'))),
        conversations: store,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天有植物学'), findsOneWidget);
    expect(find.text('输入 50 Token'), findsOneWidget);
    expect(find.text('输出 12 Token'), findsOneWidget);
    expect(find.text('根据课表查询结果整理课程。'), findsNothing);
    await tester.tap(find.text('思考内容'));
    await tester.pumpAndSettle();
    expect(find.text('根据课表查询结果整理课程。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final adapter = AgentAdapter(
      (_, _) => jsonResponse(
        completion({'content': '明天没有课', 'reasoning': '根据已保存的课表回答。'}),
      ),
    );
    await tester.pumpWidget(
      app(
        await memorySettings(config),
        pageWith(adapter),
        conversations: newStore(),
      ),
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, isEmpty);
    await send(tester, '明天呢？');
    await tester.pumpAndSettle();
    expect(find.text('明天没有课'), findsOneWidget);
    final sentHistory = adapter.payloads.single['messages'] as List;
    expect(
      sentHistory.any(
        (m) => m['role'] == 'tool' && m['tool_call_id'] == 'call-1',
      ),
      isTrue,
    );
    expect(find.text('输入 未返回 Token'), findsOneWidget);
    final next = newStore();
    await next.load();
    expect(next.active!.messages.last.reasoning, '根据已保存的课表回答。');
    expect(next.active!.messages.where((m) => m.role == 'user'), hasLength(2));
  });

  testWidgets('新建保留旧聊天，历史支持搜索消息、重命名、选择和删除', (tester) async {
    final conversations = AgentConversationStore(
      read: () async => null,
      write: (_) async {},
    );
    final adapter = AgentAdapter(
      (_, _) => jsonResponse(completion({'content': '结果中包含植物学'})),
    );
    await tester.pumpWidget(
      app(
        await memorySettings(config),
        pageWith(adapter),
        conversations: conversations,
      ),
    );
    await tester.pumpAndSettle();
    await send(tester, '查询课程');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    expect(find.text('结果中包含植物学'), findsNothing);
    expect(conversations.conversations, hasLength(1));
    await tester.tap(find.byTooltip('聊天记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索标题或消息'), '植物学');
    await tester.pumpAndSettle();
    expect(find.text('查询课程'), findsOneWidget);
    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '我的课表',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('我的课表'), findsOneWidget);
    await tester.tap(find.text('我的课表'));
    await tester.pumpAndSettle();
    expect(find.text('结果中包含植物学'), findsOneWidget);
    await tester.tap(find.byTooltip('聊天记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(conversations.conversations, isEmpty);
    await tester.tap(find.byTooltip('关闭聊天记录'));
    await tester.pumpAndSettle();
    expect(find.text('结果中包含植物学'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换会话中断旧请求，迟到响应不会污染新聊天', (tester) async {
    final conversations = AgentConversationStore(
      read: () async => null,
      write: (_) async {},
    );
    await conversations.upsert(sampleConversation(id: 'existing'));
    await conversations.select(null);
    final gate = Completer<void>();
    final adapter = AgentAdapter((_, _) async {
      await gate.future;
      return jsonResponse(completion({'content': '旧请求迟到回复'}));
    });
    await tester.pumpWidget(
      app(
        await memorySettings(config),
        pageWith(adapter),
        conversations: conversations,
      ),
    );
    await tester.pumpAndSettle();
    await send(tester, '新的问题');
    await tester.pump();
    expect(find.text('正在思考'), findsOneWidget);
    await tester.tap(find.byTooltip('聊天记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('植物学课程'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('今天有植物学'), findsOneWidget);
    expect(find.text('旧请求迟到回复'), findsNothing);
    final interrupted = conversations.conversations.firstWhere(
      (c) => c.title == '新的问题',
    );
    expect(interrupted.messages.last.incomplete, isTrue);
    expect(interrupted.pending, isFalse);
    expect(interrupted.history.last['content'], agentInterruptedText);
    expect(conversations.activeId, 'existing');
  });

  testWidgets('保存失败阻止模型请求，并提供重试保存', (tester) async {
    var fail = true;
    final conversations = AgentConversationStore(
      read: () async => null,
      write: (_) async {
        if (fail) throw StateError('disk unavailable');
      },
    );
    final adapter = AgentAdapter(
      (_, _) => jsonResponse(completion({'content': '保存恢复后可聊天'})),
    );
    await tester.pumpWidget(
      app(
        await memorySettings(config),
        pageWith(adapter),
        conversations: conversations,
      ),
    );
    await tester.pumpAndSettle();
    await send(tester, '第一条消息');
    await tester.pumpAndSettle();
    expect(adapter.requests, isEmpty);
    expect(find.text('重试保存'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(conversations.saveError, isNull);
    await send(tester, '继续');
    await tester.pumpAndSettle();
    expect(find.text('保存恢复后可聊天'), findsOneWidget);
  });

  testWidgets('复制消息与导出完整对话包含可读内容和用量', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final conversations = AgentConversationStore(
      read: () async => null,
      write: (_) async {},
    );
    await conversations.upsert(sampleConversation());
    await tester.pumpWidget(
      app(
        await memorySettings(config),
        pageWith(AgentAdapter((_, _) => throw StateError('no call'))),
        conversations: conversations,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('复制消息').last);
    await tester.pumpAndSettle();
    expect(copied, '今天有植物学');
    await tester.tap(find.byTooltip('导出对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制完整对话'));
    await tester.pumpAndSettle();
    expect(copied, contains('# 植物学课程'));
    expect(copied, contains('输入 Token：50'));
    expect(copied, contains('根据课表查询结果整理课程。'));
    expect(copied, isNot(contains(config.apiKey)));
  });

  for (final brightness in Brightness.values) {
    testWidgets('思考、用量与历史在 320px 大字体 ${brightness.name} 无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final conversations = AgentConversationStore(
        read: () async => null,
        write: (_) async {},
      );
      await conversations.upsert(sampleConversation());
      await tester.pumpWidget(
        app(
          await memorySettings(config),
          pageWith(AgentAdapter((_, _) => throw StateError('no call'))),
          conversations: conversations,
          scale: 1.4,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('思考内容'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('聊天记录'));
      await tester.pumpAndSettle();
      expect(find.text('植物学课程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
