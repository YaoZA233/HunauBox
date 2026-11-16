import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:smart_hunan_agri/services/chaoxing_course_service.dart';
import 'support/session_http_adapter.dart';

String card(
  String course,
  String clazz, {
  String host = 'mooc1.chaoxing.com',
}) =>
    '''
<div class="course learnCourse" info="${clazz}_900">
<div class="course-cover"><img src="http://p.ananas.chaoxing.com/cover.jpg"></div>
<div class="course-info"><h3><a href="https://$host/visit/stucoursemiddle?courseid=$course&amp;clazzid=$clazz&amp;cpi=900">
<span class="course-name" title="测试课程$course">测试课程$course</span></a></h3>
<p class="color2">测试大学</p><p class="color3">测试教师</p>
<p>开课时间：2026-09-01～2026-12-31</p></div></div>''';
const folders =
    '<ul id="fileList"><li fileid="7"><h3 class="file-name">完结</h3></li></ul>';
const shell =
    '<input id="courseType" value="1"><input id="stuPageHeader" value="-1">';

void main() {
  test('parses card metadata, entities and optional progress', () {
    final c = ChaoxingCourseService.parseCourses(
      html.parse(card('1', '2')),
      folder: '完结',
    ).single;
    expect(c.name, '测试课程1');
    expect(c.teacher, '测试教师');
    expect(c.school, '测试大学');
    expect(c.folder, '完结');
    expect(c.url, contains('&clazzid=2&cpi=900'));
    expect(c.coverUrl, startsWith('https://'));
    expect(c.schedule, contains('2026-09-01'));
    expect(c.progress, isNull);
    expect(c.withJobs(150, 100).progress, 1);
    expect(c.withJobs(0, 0).progress, isNull);
  });
  test('rejects external course links', () {
    expect(
      ChaoxingCourseService.parseCourses(
        html.parse(card('1', '2', host: 'chaoxing.com.evil.test')),
      ),
      isEmpty,
    );
  });
  test(
    'fetches folders once, deduplicates by course/class and merges progress',
    () async {
      final dio = Dio();
      final requested = <String>[];
      dio.httpClientAdapter = SessionHttpAdapter((r) {
        if (r.path.endsWith('/interaction')) {
          return sessionResponse('$shell$folders');
        }
        if (r.path.endsWith('/courselistdata')) {
          final form = r.data as Map<String, dynamic>;
          expect(form['courseType'], '1');
          expect(form['pageHeader'], '-1');
          requested.add(form['courseFolderId']!);
          return sessionResponse(
            '<div id="courseList">${card('1', '2')}${form['courseFolderId'] == '7' ? card('1', '3') : ''}</div>$folders',
          );
        }
        expect(r.queryParameters['clazzPersonStr'], '2_900,3_900');
        return sessionResponse(
          '{"status":true,"jobArray":[{"clazzId":2,"jobCount":84,"jobFinishCount":30}]}',
        );
      });
      final result = await ChaoxingCourseService(dio).fetchCourses();
      expect(requested, ['0', '7']);
      expect(result.length, 2);
      expect(result.first.finishedJobs, 30);
      expect(result.last.progress, isNull);
    },
  );
  test('progress failure preserves courses', () async {
    final dio = Dio();
    dio.httpClientAdapter = SessionHttpAdapter((r) {
      if (r.path.endsWith('/interaction')) return sessionResponse(shell);
      if (r.path.endsWith('/courselistdata')) {
        return sessionResponse(card('1', '2'));
      }
      return sessionResponse('unavailable', status: 503);
    });
    expect(
      (await ChaoxingCourseService(dio).fetchCourses()).single.progress,
      isNull,
    );
  });
  for (final stage in ['shell', 'list']) {
    test('expired login at $stage is an error', () async {
      final dio = Dio();
      dio.httpClientAdapter = SessionHttpAdapter(
        (r) => sessionResponse(
          stage == 'list' && r.path.endsWith('/interaction')
              ? shell
              : '<form id="loginForm"><input type="password"></form>',
        ),
      );
      await expectLater(
        ChaoxingCourseService(dio).fetchCourses(),
        throwsA(
          isA<ChaoxingCourseException>().having(
            (e) => e.needsLogin,
            'needsLogin',
            true,
          ),
        ),
      );
    });
  }
  test('distinguishes explicit empty state from invalid response', () async {
    for (final empty in [true, false]) {
      final dio = Dio();
      dio.httpClientAdapter = SessionHttpAdapter(
        (r) => sessionResponse(
          r.path.endsWith('/interaction')
              ? shell
              : empty
              ? '<div class="null-data">暂无课程</div>'
              : 'maintenance',
        ),
      );
      if (empty) {
        expect(
          await ChaoxingCourseService(dio, wait: (_) async {}).fetchCourses(),
          isEmpty,
        );
      } else {
        await expectLater(
          ChaoxingCourseService(dio, wait: (_) async {}).fetchCourses(),
          throwsA(isA<ChaoxingCourseException>()),
        );
      }
    }
  });
  test(
    'retries blank list, transient HTTP errors and partially parsed cards',
    () async {
      for (final first in ['blank', 'server', 'malformed']) {
        var attempts = 0;
        final dio = Dio();
        dio.httpClientAdapter = SessionHttpAdapter((r) {
          if (r.path.endsWith('/interaction')) return sessionResponse(shell);
          if (r.path.endsWith('/stu-job-info')) return sessionResponse('{}');
          attempts++;
          if (attempts == 1) {
            if (first == 'server') return sessionResponse('error', status: 503);
            if (first == 'malformed') {
              return sessionResponse(
                '${card('1', '2')}<div class="learnCourse"></div>',
              );
            }
            return sessionResponse('<div id="stuNormalCourseListDiv"></div>');
          }
          return sessionResponse(card('1', '2'));
        });
        final result = await ChaoxingCourseService(
          dio,
          wait: (_) async {},
        ).fetchCourses();
        expect(result.single.name, '测试课程1');
        expect(attempts, 2);
      }
    },
  );

  test(
    'persistent placeholder and hidden empty state are errors, not empty courses',
    () async {
      for (final body in [
        '<div id="courseList"></div>',
        '<div class="null-data" style="display:none">暂无课程</div>',
        '${card('1', '2')}<div class="learnCourse"></div>',
      ]) {
        var attempts = 0;
        final dio = Dio();
        dio.httpClientAdapter = SessionHttpAdapter((r) {
          if (r.path.endsWith('/interaction')) return sessionResponse(shell);
          attempts++;
          return sessionResponse(body);
        });
        await expectLater(
          ChaoxingCourseService(dio, wait: (_) async {}).fetchCourses(),
          throwsA(isA<ChaoxingCourseException>()),
        );
        expect(attempts, 3);
      }
    },
  );
  test('folder failure does not return partial results', () async {
    final dio = Dio();
    dio.httpClientAdapter = SessionHttpAdapter((r) {
      if (r.path.endsWith('/interaction')) {
        return sessionResponse('$shell$folders');
      }
      final form = r.data as Map<String, dynamic>;
      return form['courseFolderId'] == '0'
          ? sessionResponse(card('1', '2'))
          : sessionResponse('error', status: 500);
    });
    await expectLater(
      ChaoxingCourseService(dio).fetchCourses(),
      throwsA(isA<ChaoxingCourseException>()),
    );
  });
}
