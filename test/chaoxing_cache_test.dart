import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/chaoxing_course.dart';
import 'package:smart_hunan_agri/pages/chaoxing_courses_page.dart';
import 'package:smart_hunan_agri/pages/chaoxing_messages_page.dart';
import 'package:smart_hunan_agri/providers/chaoxing_course_provider.dart';
import 'package:smart_hunan_agri/services/chaoxing_cache_store.dart';
import 'package:smart_hunan_agri/services/chaoxing_messages_service.dart';

class FakeService extends ChaoxingMessagesService {
  FakeService(this.fail);
  final bool fail;
  static int starts = 0;
  @override
  Future<void> start() async {
    starts++;
    if (fail) throw StateError('offline');
  }

  @override
  Future<List<ChaoxingConversation>> conversations() async => const [
    ChaoxingConversation(
      index: 0,
      name: '课程群',
      preview: '老师：通知',
      time: '10-30',
    ),
  ];
  @override
  Future<List<ChaoxingConversation>> refreshConversations() async {
    if (fail) throw StateError('offline');
    return conversations();
  }

  @override
  Future<List<ChaoxingChatMessage>> messages(ChaoxingConversation c) async =>
      const [
        ChaoxingChatMessage(
          sender: '老师',
          text: '缓存的消息正文',
          time: '10-30',
          mine: false,
        ),
      ];
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeService.starts = 0;
  });
  test(
    'account switch keeps caches isolated and rejects stale writes',
    () async {
      var account = 'alice';
      final cache = ChaoxingCacheStore(account: () async => account);
      await cache.write('alice', 'courses', {
        'items': ['alice'],
      });
      account = 'bob';
      expect(await cache.read('courses'), isNull);
      await cache.write('alice', 'courses', {
        'items': ['wrong'],
      });
      await cache.write('bob', 'courses', {
        'items': ['bob'],
      });
      account = 'alice';
      expect((await cache.read('courses'))!['items'], ['alice']);
    },
  );
  testWidgets('successful refresh persists replacement courses', (
    tester,
  ) async {
    final cache = ChaoxingCacheStore(account: () async => 'alice');
    await cache.write('alice', 'courses', {
      'items': [
        const ChaoxingCourse(
          id: '1',
          name: '旧课程',
          url: 'https://mooc1.chaoxing.com/',
        ).toJson(),
      ],
    });
    var calls = 0;
    Future<List<ChaoxingCourse>> fetch() async {
      calls++;
      return const [
        ChaoxingCourse(
          id: '2',
          name: '新课程',
          url: 'https://mooc1.chaoxing.com/',
        ),
      ];
    }

    Widget page() => ProviderScope(
      overrides: [
        chaoxingCacheProvider.overrideWithValue(cache),
        chaoxingCourseFetcherProvider.overrideWithValue(fetch),
      ],
      child: const MaterialApp(home: ChaoxingCoursesPage()),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('旧课程'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.byTooltip('刷新课程'));
    await tester.pumpAndSettle();
    expect(find.text('新课程'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('新课程'), findsOneWidget);
    expect(calls, 1);
  });
  testWidgets('旧空课程缓存重新同步，空刷新不会覆盖有效缓存', (tester) async {
    final cache = ChaoxingCacheStore(account: () async => 'alice');
    await cache.write('alice', 'courses', {'items': []});
    var calls = 0;
    Widget page() => ProviderScope(
      overrides: [
        chaoxingCacheProvider.overrideWithValue(cache),
        chaoxingCourseFetcherProvider.overrideWithValue(() async {
          calls++;
          if (calls > 1) return [];
          return [
            const ChaoxingCourse(
              id: '1:2',
              name: '原有课程',
              url: 'https://mooc1.chaoxing.com/',
            ),
          ];
        }),
      ],
      child: const MaterialApp(home: ChaoxingCoursesPage()),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('原有课程'), findsOneWidget);
    expect(calls, 1);
    await tester.tap(find.byTooltip('刷新课程'));
    await tester.pumpAndSettle();
    expect(find.text('刷新失败，正在显示上次的课程。'), findsOneWidget);
    expect(find.text('原有课程'), findsOneWidget);
    expect((await cache.read('courses'))!['items'], hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('原有课程'), findsOneWidget);
    expect(calls, 2);
  });

  test('确认空课程可缓存，切换账号时不会写入', () async {
    var owner = 'alice';
    final cache = ChaoxingCacheStore(account: () async => owner);
    expect(await fetchAndCacheCourses(cache, () async => []), isEmpty);
    expect((await cache.read('courses'))!['verifiedEmpty'], true);
    await expectLater(
      fetchAndCacheCourses(cache, () async {
        owner = 'bob';
        return [const ChaoxingCourse(id: 'x', name: '课程', url: '')];
      }),
      throwsStateError,
    );
    expect(await cache.read('courses'), isNull);
  });
  testWidgets('courses retain cache across reopen and failed refresh', (
    tester,
  ) async {
    final cache = ChaoxingCacheStore(account: () async => 'alice');
    var calls = 0;
    Future<List<ChaoxingCourse>> fetch() async {
      calls++;
      if (calls > 1) throw StateError('offline');
      return const [
        ChaoxingCourse(
          id: '1:2',
          name: '缓存课程',
          url: 'https://mooc1.chaoxing.com/',
        ),
      ];
    }

    Widget page() => ProviderScope(
      overrides: [
        chaoxingCacheProvider.overrideWithValue(cache),
        chaoxingCourseFetcherProvider.overrideWithValue(fetch),
      ],
      child: const MaterialApp(home: ChaoxingCoursesPage()),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('缓存课程'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('缓存课程'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新课程'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('缓存课程'), findsOneWidget);
    expect(find.text('刷新失败，正在显示上次的课程。'), findsOneWidget);
  });
  testWidgets(
    'message list and opened detail survive offline reopen and refresh failure',
    (tester) async {
      final cache = ChaoxingCacheStore(account: () async => 'alice');
      var offline = false;
      Widget page() => MaterialApp(
        home: ChaoxingMessagesPage(
          cache: cache,
          createService: () => FakeService(offline),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('课程群'));
      await tester.pumpAndSettle();
      expect(find.text('缓存的消息正文'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      offline = true;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(FakeService.starts, 1);
      await tester.tap(find.text('课程群'));
      await tester.pumpAndSettle();
      expect(find.text('缓存的消息正文'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新会话'));
      await tester.pumpAndSettle();
      expect(find.text('缓存的消息正文'), findsOneWidget);
      expect(find.text('消息刷新失败，请返回刷新会话或重试。'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刷新消息'));
      await tester.pumpAndSettle();
      expect(find.text('课程群'), findsOneWidget);
      expect(find.text('刷新失败，正在显示上次的消息。'), findsOneWidget);
    },
  );
}
