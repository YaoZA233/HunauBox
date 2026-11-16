import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/chaoxing_course.dart';
import 'package:smart_hunan_agri/providers/chaoxing_course_provider.dart';
import 'package:smart_hunan_agri/services/agent_tool_registry.dart';
import 'package:smart_hunan_agri/services/campus_agent_tools.dart';
import 'package:smart_hunan_agri/services/chaoxing_cache_store.dart';

void main() {
  testWidgets('Agent 空课程刷新不能覆盖已有缓存，旧空缓存不能当作已确认', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cache = ChaoxingCacheStore(account: () async => 'one');
    await cache.write('one', 'courses', {'items': []});
    late AgentToolRegistry tools;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chaoxingCacheProvider.overrideWithValue(cache),
          chaoxingCourseFetcherProvider.overrideWithValue(() async => []),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (_, ref, _) {
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
    final ctx = AgentToolContext(
      cancelToken: CancelToken(),
      confirm: (_, _) async => false,
    );
    expect(
      (await tools.execute('query_chaoxing_courses', {}, ctx) as Map)['error'],
      contains('未确认'),
    );
    await cache.write('one', 'courses', {
      'items': [const ChaoxingCourse(id: '1', name: '原有课程', url: '').toJson()],
    });
    final refresh =
        await tools.execute('query_chaoxing_courses', {
              'forceRefresh': true,
            }, ctx)
            as Map;
    expect(refresh['error'], contains('保留上次'));
    expect((await cache.read('courses'))!['items'], hasLength(1));
  });

  testWidgets('学习通工具读取隔离缓存、筛选分页并保护消息范围', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var owner = 'one';
    var fetches = 0;
    final cache = ChaoxingCacheStore(account: () async => owner);
    late AgentToolRegistry tools;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chaoxingCacheProvider.overrideWithValue(cache),
          chaoxingCourseFetcherProvider.overrideWithValue(() async {
            fetches++;
            return [
              const ChaoxingCourse(
                id: 'id',
                name: '数学',
                url: 'secret-token',
                teacher: '李老师',
                finishedJobs: 1,
                totalJobs: 2,
              ),
              const ChaoxingCourse(
                id: 'other',
                name: '英语',
                url: '',
                finishedJobs: null,
              ),
            ];
          }),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (_, ref, _) {
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
    final ctx = AgentToolContext(
      cancelToken: CancelToken(),
      confirm: (_, _) async => false,
    );
    Future<Map> run(
      String name, [
      Map<String, dynamic> args = const {},
    ]) async => await tools.execute(name, args, ctx) as Map;
    expect((await run('query_chaoxing_courses'))['error'], contains('暂无'));
    expect(fetches, 0);
    final fresh = await run('query_chaoxing_courses', {
      'forceRefresh': true,
      'progress': 'incomplete',
    });
    expect(fetches, 1);
    expect(fresh['totalCount'], 1);
    expect(fresh.toString(), isNot(contains('secret-token')));
    expect(
      (await run('query_chaoxing_courses', {
        'progress': 'unknown',
      }))['totalCount'],
      1,
    );
    expect(
      (await run('query_chaoxing_courses', {'offset': 10}))['courses'],
      isEmpty,
    );
    expect(
      (await run('query_chaoxing_conversations'))['error'],
      contains('暂无'),
    );
    await cache.write(owner, 'messages', {
      'conversations': [
        {'index': 1, 'name': '课程群', 'preview': '通知', 'time': '今天'},
        {'index': 2, 'name': '另一个群', 'preview': '作业'},
      ],
      'details': {
        '1:课程群': [
          {'sender': '老师', 'text': '长' * 650, 'time': '今天', 'mine': false},
        ],
      },
    });
    final list = await run('query_chaoxing_conversations', {'keyword': '通知'});
    expect(list['totalCount'], 1);
    expect((list['conversations'] as List).single['detailCached'], true);
    final messages = await run('query_chaoxing_messages', {
      'conversation': '课程群',
    });
    expect((messages['messages'] as List).single['textTruncated'], true);
    expect(
      (await run('query_chaoxing_messages', {'conversation': '另一个群'}))['error'],
      contains('尚未缓存'),
    );
    expect(
      (await run('query_chaoxing_messages', {'conversation': '群'}))['error'],
      contains('多个'),
    );
    owner = 'two';
    expect((await run('query_chaoxing_courses'))['error'], contains('暂无'));
    expect(
      (await run('query_chaoxing_conversations'))['error'],
      contains('暂无'),
    );
    await cache.write(owner, 'messages', {'conversations': [], 'details': {}});
    expect((await run('query_chaoxing_conversations'))['totalCount'], 0);
  });

  testWidgets('取消或切换账号后，课程刷新不会写入缓存', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var owner = 'one';
    final cache = ChaoxingCacheStore(account: () async => owner);
    var pending = Completer<List<ChaoxingCourse>>();
    late AgentToolRegistry tools;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chaoxingCacheProvider.overrideWithValue(cache),
          chaoxingCourseFetcherProvider.overrideWithValue(() => pending.future),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (_, ref, _) {
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
    final token = CancelToken();
    final ctx = AgentToolContext(
      cancelToken: token,
      confirm: (_, _) async => false,
    );
    final request = tools.execute('query_chaoxing_courses', {
      'forceRefresh': true,
    }, ctx);
    await tester.pump();
    token.cancel();
    pending.complete([]);
    await expectLater(request, throwsA(isA<Exception>()));
    expect(await cache.read('courses'), isNull);
    pending = Completer<List<ChaoxingCourse>>();
    final second = tools.execute(
      'query_chaoxing_courses',
      {'forceRefresh': true},
      AgentToolContext(
        cancelToken: CancelToken(),
        confirm: (_, _) async => false,
      ),
    );
    await tester.pump();
    owner = 'two';
    pending.complete([]);
    expect((await second as Map)['error'], contains('切换'));
    expect(await cache.read('courses'), isNull);
    owner = 'one';
    expect(await cache.read('courses'), isNull);
  });
}
