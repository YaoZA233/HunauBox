import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide completion;
import 'package:smart_hunan_agri/models/agent_models.dart';
import 'package:smart_hunan_agri/models/homework_model.dart';
import 'package:smart_hunan_agri/pages/agent_page.dart';
import 'package:smart_hunan_agri/pages/agent_settings_page.dart';
import 'package:smart_hunan_agri/pages/main_navigator.dart';
import 'package:smart_hunan_agri/pages/profile_page.dart';
import 'package:smart_hunan_agri/providers/homework_provider.dart';
import 'package:smart_hunan_agri/services/agent_service.dart';
import 'package:smart_hunan_agri/services/agent_conversation_store.dart';
import 'package:smart_hunan_agri/services/agent_settings_store.dart';
import 'package:smart_hunan_agri/services/agent_tool_registry.dart';
import 'package:smart_hunan_agri/services/campus_agent_tools.dart';
import 'package:smart_hunan_agri/services/homework_storage.dart';
import 'package:smart_hunan_agri/widgets/agent_settings_section.dart';

import 'agent_service_test.dart'
    show config, AgentAdapter, completion, jsonResponse;

Future<AgentSettingsStore> memorySettings([
  AgentConfig value = const AgentConfig(),
]) async {
  String? record = value.encodeForStorage();
  final store = AgentSettingsStore(
    read: () async => record,
    write: (v) async {
      record = v;
    },
    delete: () async {
      record = null;
    },
  );
  await store.load();
  return store;
}

Widget app(
  AgentSettingsStore store,
  Widget child, {
  Size? size,
  double scale = 1,
  Brightness brightness = Brightness.light,
  AgentConversationStore? conversations,
}) => ProviderScope(
  overrides: [
    agentSettingsProvider.overrideWith((_) => store),
    agentConversationsProvider.overrideWith(
      (_) =>
          conversations ??
          AgentConversationStore(read: () async => null, write: (_) async {}),
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  ),
);

class MemoryHomeworkStorage extends HomeworkStorage {
  List<HomeworkModel> items = [];
  bool failWrite = false;
  @override
  Future<List<HomeworkModel>?> readHomeworkList() async => items;
  @override
  Future<void> saveHomeworkList(
    List<HomeworkModel> list, {
    bool throwOnError = false,
  }) async {
    if (failWrite) throw StateError('write failed');
    items = list;
  }
}

void main() {
  testWidgets('关闭 Agent 左侧仅三项，设置开关确认后立即变四项，关闭恢复三项', (tester) async {
    final store = await memorySettings();
    await tester.pumpWidget(
      app(
        store,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final settings = ref.watch(agentSettingsProvider);
              return Row(
                children: [
                  SizedBox(
                    width: 78,
                    child: CampusNavigationRail(
                      agentEnabled: settings.config.enabled,
                      showSystemStatus: false,
                      onChanged: (_) {},
                    ),
                  ),
                  const Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: AgentSettingsSection(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    final rail = find.byType(CampusNavigationRail);
    expect(
      find.descendant(of: rail, matching: find.text('Agent')),
      findsNothing,
    );
    for (final label in ['功能', '通知', '作业']) {
      expect(
        find.descendant(of: rail, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.descendant(of: rail, matching: find.text('设置')), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('开启校园 Agent？'), findsOneWidget);
    await tester.tap(find.text('开启'));
    await tester.pumpAndSettle();
    expect(store.config.enabled, isTrue);
    expect(
      find.descendant(of: rail, matching: find.text('Agent')),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.config.enabled, isFalse);
    expect(
      find.descendant(of: rail, matching: find.text('Agent')),
      findsNothing,
    );
  });

  testWidgets('开启确认取消时不保存开关', (tester) async {
    final store = await memorySettings();
    await tester.pumpWidget(
      app(store, const Scaffold(body: AgentSettingsSection())),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不开启'));
    await tester.pumpAndSettle();
    expect(store.config.enabled, isFalse);
  });

  testWidgets('未配置 Agent 只展示配置引导，不调用模型', (tester) async {
    final store = await memorySettings(const AgentConfig(enabled: true));
    final adapter = AgentAdapter((_, _) => throw StateError('must not call'));
    await tester.pumpWidget(
      app(
        store,
        AgentPage(
          service: AgentService(dio: Dio()..httpClientAdapter = adapter),
          tools: AgentToolRegistry([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('先连接你的模型服务'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(adapter.requests, isEmpty);
    await tester.tap(find.text('填写模型服务配置'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentSettingsPage), findsOneWidget);
  });

  testWidgets('填写配置保存到安全存储，Key 默认遮挡，保存不会自动启用或联网', (tester) async {
    final store = await memorySettings();
    await tester.pumpWidget(
      app(
        store,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AgentSettingsPage(),
                ),
              ),
              child: const Text('打开配置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开配置'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'https://model.example/v1');
    await tester.enterText(fields.at(1), 'fake-test-key');
    await tester.enterText(fields.at(2), 'test-model');
    final keyField = find.descendant(
      of: fields.at(1),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(keyField).obscureText, isTrue);
    await tester.scrollUntilVisible(
      find.text('保存配置'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(store.config.apiUrl, 'https://model.example/v1');
    expect(store.config.apiKey, 'fake-test-key');
    expect(store.config.enabled, isFalse);
    expect(find.text('打开配置'), findsOneWidget);
  });

  testWidgets('聊天发送成功，保留上下文并防止重复点击', (tester) async {
    final store = await memorySettings(config);
    final gate = Completer<void>();
    final adapter = AgentAdapter((_, _) async {
      await gate.future;
      return jsonResponse(completion({'content': '今天有植物学，教学楼 101。'}));
    });
    await tester.pumpWidget(
      app(
        store,
        AgentPage(
          service: AgentService(dio: Dio()..httpClientAdapter = adapter),
          tools: AgentToolRegistry([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '今天有哪些课？');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(find.text('正在思考'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '发送'),
          )
          .onPressed,
      isNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(1));
    expect(find.text('今天有植物学，教学楼 101。'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '发送'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('关闭 Agent 会取消进行中请求并清空对话，不显示迟到响应', (tester) async {
    final store = await memorySettings(config);
    final gate = Completer<void>();
    final adapter = AgentAdapter((_, _) async {
      await gate.future;
      return jsonResponse(completion({'content': '迟到的回复'}));
    });
    await tester.pumpWidget(
      app(
        store,
        AgentPage(
          service: AgentService(dio: Dio()..httpClientAdapter = adapter),
          tools: AgentToolRegistry([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '问一个问题');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await store.setEnabled(false);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Agent 已关闭'), findsOneWidget);
    expect(find.text('问一个问题'), findsNothing);
    expect(find.text('迟到的回复'), findsNothing);
  });

  testWidgets('写操作确认框取消，不执行写入', (tester) async {
    final store = await memorySettings(config);
    var writes = 0;
    final adapter = AgentAdapter(
      (_, n) => jsonResponse(
        completion(
          n == 1
              ? {
                  'tool_calls': [
                    {
                      'id': 'write-1',
                      'type': 'function',
                      'function': {'name': 'write', 'arguments': '{}'},
                    },
                  ],
                }
              : {'content': '已取消，未修改。'},
        ),
      ),
    );
    final tools = AgentToolRegistry([
      AgentTool(
        name: 'write',
        label: '修改作业',
        description: '',
        run: (_, ctx) async {
          if (!await ctx.askConfirmation('修改作业', '将作业标记完成？')) {
            return {'cancelled': true};
          }
          writes++;
          return {'success': true};
        },
      ),
    ]);
    await tester.pumpWidget(
      app(
        store,
        AgentPage(
          service: AgentService(dio: Dio()..httpClientAdapter = adapter),
          tools: tools,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '完成作业');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('将作业标记完成？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('已取消，未修改。'), findsOneWidget);
  });

  testWidgets('未登录也可从个人中心进入设置', (tester) async {
    final store = await memorySettings();
    await tester.pumpWidget(
      app(
        store,
        ProfilePage(isLoggedIn: false, onLogout: () {}, onLogin: () {}),
      ),
    );
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('登录校园账号'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Agent 320px 窄屏、大字体、${brightness.name} 无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await memorySettings(config);
      await tester.pumpWidget(
        app(
          store,
          AgentPage(tools: AgentToolRegistry([])),
          scale: 1.4,
          brightness: brightness,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('校园真实工具注册表阻止未登录查询和任意页面跳转', (tester) async {
    var loggedIn = false;
    var opened = 0;
    late AgentToolRegistry tools;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              tools = buildCampusAgentTools(
                ref,
                isLoggedIn: () async => loggedIn,
                openService: (_) async {
                  opened++;
                },
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    // The registry also exposes read-only service queries and guarded timetable
    // adjustment tools.
    expect(tools.schemas, hasLength(22));
    final blocked = await tools.execute(
      'query_electricity',
      {},
      AgentToolContext(
        cancelToken: CancelToken(),
        confirm: (_, _) async => true,
      ),
    );
    expect(blocked.toString(), contains('请先'));
    expect(opened, 0);
    loggedIn = true;
    final invalid = await tools.execute(
      'open_campus_service',
      {'service': 'https://untrusted.example'},
      AgentToolContext(
        cancelToken: CancelToken(),
        confirm: (_, _) async => true,
      ),
    );
    expect(invalid.toString(), contains('error'));
    expect(opened, 0);
    await tools.execute(
      'open_campus_service',
      {'service': 'electricity'},
      AgentToolContext(
        cancelToken: CancelToken(),
        confirm: (_, _) async => false,
      ),
    );
    expect(opened, 0);
    await tools.execute(
      'open_campus_service',
      {'service': 'electricity'},
      AgentToolContext(
        cancelToken: CancelToken(),
        confirm: (_, _) async => true,
      ),
    );
    expect(opened, 1);
  });

  testWidgets('实际作业工具确认后新增与完成，模型不能伪造 confirmed 绕过', (tester) async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'test-student');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final storage = MemoryHomeworkStorage();
    late AgentToolRegistry tools;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeworkStorageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              tools = buildCampusAgentTools(
                ref,
                isLoggedIn: () async => true,
                openService: (_) async {},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    var confirmations = 0;
    final approved = AgentToolContext(
      cancelToken: CancelToken(),
      confirm: (_, _) async {
        confirmations++;
        return true;
      },
    );
    await tools.execute('add_homework', {
      'title': '伪造确认',
      'confirmed': true,
    }, approved);
    expect(storage.items, isEmpty);
    expect(confirmations, 0);
    await tools.execute(
      'add_homework',
      {'title': '实验报告'},
      AgentToolContext(
        cancelToken: CancelToken(),
        confirm: (_, _) async => false,
      ),
    );
    expect(storage.items, isEmpty);
    final result = await tester.runAsync(
      () => tools.execute('add_homework', {
        'title': '实验报告',
        'courseName': '植物学',
        'endTime': '2099-10-02 18:00:00',
      }, approved),
    );
    expect(result, containsPair('success', true));
    expect(storage.items, hasLength(1));
    expect(confirmations, 1);
    final completed = await tester.runAsync(
      () => tools.execute('complete_homework', {
        'id': storage.items.single.id,
      }, approved),
    );
    expect(completed, containsPair('success', true));
    expect(storage.items.single.status, HomeworkStatus.completed);
    expect(confirmations, 2);
    final synced = storage.items.single.copyWith(
      id: 'chaoxing',
      isManual: false,
      status: HomeworkStatus.pending,
    );
    storage.items.add(synced);
    final denied = await tools.execute('complete_homework', {
      'id': 'chaoxing',
    }, approved);
    expect(denied.toString(), contains('学习通'));
    expect(confirmations, 2);
  });

  test('手动作业仅在持久化成功后更新，不能代交学习通作业', () async {
    final storage = MemoryHomeworkStorage();
    final container = ProviderContainer(
      overrides: [homeworkStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(homeworkProvider.notifier);
    final item = HomeworkModel(
      id: 'manual',
      title: '实验报告',
      courseName: '植物学',
      status: HomeworkStatus.pending,
      studentId: 'test',
      isManual: true,
    );
    await notifier.addManualHomework(item);
    expect(storage.items, hasLength(1));
    await notifier.completeManualHomework('manual');
    expect(storage.items.single.status, HomeworkStatus.completed);
    storage.failWrite = true;
    await expectLater(
      notifier.addManualHomework(item.copyWith(id: 'manual-2')),
      throwsStateError,
    );
    expect(container.read(homeworkProvider).value, hasLength(1));
    storage.failWrite = false;
    await expectLater(
      notifier.addManualHomework(item.copyWith(isManual: false)),
      throwsArgumentError,
    );
  });
}
