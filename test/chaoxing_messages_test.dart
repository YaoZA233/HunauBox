import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/pages/chaoxing_messages_page.dart';
import 'package:smart_hunan_agri/services/chaoxing_cache_store.dart';
import 'package:smart_hunan_agri/services/chaoxing_messages_service.dart';

class FakeMessagesService extends ChaoxingMessagesService {
  FakeMessagesService({this.fail = false});
  final bool fail;
  bool closed = false;
  int refreshes = 0;
  int emptyReads = 0;
  bool emptyDetails = false;
  @override
  Future<void> start() async {
    if (fail) throw StateError('login');
  }

  @override
  Future<List<ChaoxingConversation>> conversations() async {
    if (emptyReads > 0) {
      emptyReads--;
      return [];
    }
    return const [
      ChaoxingConversation(
        index: 0,
        name: '植物学课程群',
        preview: '老师：请查看作业',
        time: '10-30',
      ),
      ChaoxingConversation(
        index: 1,
        name: '摄影课程群',
        preview: '新通知',
        time: '10-29',
      ),
    ];
  }

  @override
  Future<List<ChaoxingConversation>> refreshConversations() {
    refreshes++;
    return conversations();
  }

  @override
  Future<List<ChaoxingChatMessage>> messages(ChaoxingConversation c) async =>
      emptyDetails
      ? []
      : [
          ChaoxingChatMessage(
            sender: '老师',
            text: '来自${c.name}的消息',
            time: '10-30 12:00',
            mine: false,
          ),
          const ChaoxingChatMessage(
            sender: '老师',
            text: '[图片或附件，请在学习通中查看]',
            time: '',
            mine: false,
          ),
        ];
  @override
  Future<void> dispose() async {
    closed = true;
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'polling rejects transient empty and partly rendered lists until stable',
    () async {
      var calls = 0;
      final service = ChaoxingMessagesService(
        evaluate: (_) async {
          calls++;
          if (calls == 1) return null;
          if (calls == 2) return [];
          if (calls == 3) {
            return [
              {'index': 0, 'name': ''},
            ];
          }
          return [
            {'index': 0, 'name': '课程群', 'preview': '通知'},
          ];
        },
        wait: (_) async {},
      );
      expect((await service.conversations()).single.name, '课程群');
      expect(calls, 6);
      await service.dispose();
    },
  );

  test(
    'persistent empty results and expired login are errors, not zero conversations',
    () async {
      final empty = ChaoxingMessagesService(
        evaluate: (_) async => [],
        wait: (_) async {},
      );
      await expectLater(empty.conversations(), throwsStateError);
      final expired = ChaoxingMessagesService(
        evaluate: (_) async => {'error': 'login'},
        wait: (_) async {},
      );
      await expectLater(expired.conversations(), throwsStateError);
      await empty.dispose();
      await expired.dispose();
    },
  );

  testWidgets('old empty cache is retried and temporary zero result recovers', (
    tester,
  ) async {
    final cache = ChaoxingCacheStore(account: () async => 'alice');
    await cache.write('alice', 'messages', {
      'conversations': [],
      'details': {},
    });
    final service = FakeMessagesService()..emptyReads = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: ChaoxingMessagesPage(cache: cache, createService: () => service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('会话 · 2'), findsOneWidget);
    expect(service.refreshes, 1);
    expect((await cache.read('messages'))!['conversations'], hasLength(2));
  });

  testWidgets('empty refresh preserves list and opened detail across reopen', (
    tester,
  ) async {
    final cache = ChaoxingCacheStore(account: () async => 'alice');
    final service = FakeMessagesService();
    Widget page() => MaterialApp(
      home: ChaoxingMessagesPage(cache: cache, createService: () => service),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('植物学课程群'));
    await tester.pumpAndSettle();
    service.emptyDetails = true;
    await tester.tap(find.byTooltip('刷新会话'));
    await tester.pumpAndSettle();
    expect(find.text('来自植物学课程群的消息'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    service.emptyReads = 2;
    await tester.tap(find.byTooltip('刷新消息'));
    await tester.pumpAndSettle();
    expect(find.text('刷新失败，正在显示上次的消息。'), findsOneWidget);
    expect(find.text('会话 · 2'), findsOneWidget);
    expect((await cache.read('messages'))!['conversations'], hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('植物学课程群'), findsOneWidget);
    await tester.tap(find.text('植物学课程群'));
    await tester.pumpAndSettle();
    expect(find.text('来自植物学课程群的消息'), findsOneWidget);
  });

  testWidgets('first load with no valid list shows recovery instead of zero', (
    tester,
  ) async {
    final service = FakeMessagesService()..emptyReads = 2;
    await tester.pumpWidget(
      MaterialApp(home: ChaoxingMessagesPage(createService: () => service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新同步'), findsOneWidget);
    expect(find.text('会话 · 0'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });
  testWidgets('refresh reuses the existing message service', (tester) async {
    var created = 0;
    final service = FakeMessagesService();
    await tester.pumpWidget(
      MaterialApp(
        home: ChaoxingMessagesPage(
          createService: () {
            created++;
            return service;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新消息'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(service.refreshes, 1);
    expect(service.closed, false);
    expect(find.text('植物学课程群'), findsOneWidget);
  });
  test('validates extracted fields and preserves message order', () {
    final conversations = ChaoxingMessagesService.parseConversations([
      {'index': 0, 'name': '课程群', 'preview': '老师：消息', 'time': '10-30'},
      {'index': 1, 'name': ''},
      {'index': 'bad', 'name': '异常'},
    ]);
    expect(conversations.single.preview, '老师：消息');
    final messages = ChaoxingMessagesService.parseMessages([
      {'sender': '老师', 'text': '第一条', 'time': '10-30', 'mine': false},
      {'text': '附件', 'mine': true},
      {'text': ''},
    ]);
    expect(messages.map((e) => e.text), ['第一条', '附件']);
    expect(messages.last.mine, true);
  });
  testWidgets('search opens the matching conversation and displays messages', (
    tester,
  ) async {
    final services = <FakeMessagesService>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ChaoxingMessagesPage(
          createService: () {
            final service = FakeMessagesService();
            services.add(service);
            return service;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('会话 · 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '植物');
    await tester.pumpAndSettle();
    expect(find.text('摄影课程群'), findsNothing);
    await tester.tap(find.text('植物学课程群'));
    await tester.pumpAndSettle();
    expect(find.text('来自植物学课程群的消息'), findsOneWidget);
    expect(find.text('[图片或附件，请在学习通中查看]'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(services.first.closed, false);
    expect(find.text('植物学课程群'), findsOneWidget);
  });
  testWidgets('failure displays recovery and retry reloads', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChaoxingMessagesPage(
          createService: () => FakeMessagesService(fail: attempts++ == 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('打开学习通 / 登录'), findsOneWidget);
    await tester.tap(find.text('重新同步'));
    await tester.pumpAndSettle();
    expect(find.text('会话 · 2'), findsOneWidget);
  });
  test(
    'empty message history waits for a valid response instead of returning zero',
    () async {
      var calls = 0;
      final service = ChaoxingMessagesService(
        evaluate: (_) async {
          calls++;
          if (calls == 1) return true;
          if (calls < 4) return [];
          return [
            {'sender': '老师', 'text': '已加载的消息'},
          ];
        },
        wait: (_) async {},
      );
      final messages = await service.messages(
        const ChaoxingConversation(
          index: 0,
          name: '课程群',
          preview: '',
          time: '',
        ),
      );
      expect(messages.single.text, '已加载的消息');
      expect(calls, 4);
      await service.dispose();
    },
  );

  testWidgets(
    'cached conversation still opens after live order and preview change',
    (tester) async {
      final cache = ChaoxingCacheStore(account: () async => 'alice');
      await cache.write('alice', 'messages', {
        'conversations': [
          {'index': 99, 'name': '植物学课程群', 'preview': '旧摘要', 'time': '昨天'},
        ],
        'details': {},
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChaoxingMessagesPage(
            cache: cache,
            createService: () => FakeMessagesService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('植物学课程群'));
      await tester.pumpAndSettle();
      expect(find.text('来自植物学课程群的消息'), findsOneWidget);
    },
  );

  for (final size in [
    const Size(320, 700),
    const Size(375, 812),
    const Size(812, 375),
  ]) {
    testWidgets('message list fits $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ChaoxingMessagesPage(
            createService: () => FakeMessagesService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNothing);
      await tester.ensureVisible(find.text('植物学课程群'));
      await tester.tap(find.text('植物学课程群'));
      await tester.pumpAndSettle();
      expect(find.text('来自植物学课程群的消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
