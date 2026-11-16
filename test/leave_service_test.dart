import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/services/leave_service.dart';

import 'support/session_http_adapter.dart';

void main() {
  test('提交结果为未知HTML不自动重放，避免重复申请', () async {
    var renewals = 0;
    final adapter = SessionHttpAdapter(
      (_) => sessionResponse('<html>服务器返回异常</html>'),
    );
    final service = LeaveService(
      dio: Dio()..httpClientAdapter = adapter,
      reauthenticate: () async {
        renewals++;
        return true;
      },
    );
    await expectLater(
      service.submit(fields: {'qjsy': '事假'}),
      throwsA(
        isA<LeaveException>().having(
          (e) => e.message,
          'message',
          contains('确认操作结果'),
        ),
      ),
    );
    expect(adapter.requests.length, 1);
    expect(renewals, 0);
  });
  for (final body in [
    '{}',
    '{"day":"异常","hour":2}',
    '{"day":0,"hour":24}',
    '[]',
  ]) {
    test('无效时长$body不能当作0天0小时提交', () async {
      final adapter = SessionHttpAdapter((_) => sessionResponse(body));
      await expectLater(
        LeaveService(
          dio: Dio()..httpClientAdapter = adapter,
        ).calculate('2026-10-12 09:00', '2026-10-13 10:00'),
        throwsA(isA<LeaveException>()),
      );
    });
  }

  for (final status in [302, 401, 403, 200]) {
    test('请假 $status 登录过期自动恢复并只重试一次', () async {
      var renewed = false;
      var renewals = 0;
      final adapter = SessionHttpAdapter(
        (_) => renewed
            ? sessionResponse('{"aaData":[]}')
            : sessionResponse(
                '<!DOCTYPE html><HTML>统一认证</HTML>',
                status: status,
              ),
      );
      final service = LeaveService(
        dio: Dio()..httpClientAdapter = adapter,
        reauthenticate: () async {
          renewals++;
          renewed = true;
          return true;
        },
      );
      expect(await service.fetchList(), isEmpty);
      expect(adapter.requests.length, 2);
      expect(renewals, 1);
    });
  }

  test('恢复后仍返回登录页给出明确错误，不循环重试', () async {
    var renewals = 0;
    final adapter = SessionHttpAdapter(
      (_) => sessionResponse('<HTML>统一认证登录</HTML>'),
    );
    final service = LeaveService(
      dio: Dio()..httpClientAdapter = adapter,
      reauthenticate: () async {
        renewals++;
        return true;
      },
    );
    await expectLater(
      service.fetchList(),
      throwsA(
        isA<LeaveException>().having(
          (e) => e.message,
          'message',
          contains('学工登录已失效'),
        ),
      ),
    );
    expect(renewals, 1);
    expect(adapter.requests.length, 2);
  });

  test('刷新失败不再次访问业务接口', () async {
    final adapter = SessionHttpAdapter((_) => sessionResponse('', status: 401));
    await expectLater(
      LeaveService(
        dio: Dio()..httpClientAdapter = adapter,
        reauthenticate: () async => false,
      ).fetchTypes(),
      throwsA(isA<LeaveException>()),
    );
    expect(adapter.requests.length, 1);
  });

  test('附件提交过期重试时重建 multipart，文件仍完整', () async {
    final directory = await Directory.systemTemp.createTemp('leave-session-');
    final attachment = File('${directory.path}/proof.txt');
    await attachment.writeAsString('attachment-proof');
    try {
      var posts = 0;
      final adapter = SessionHttpAdapter(
        (_) => posts++ == 0
            ? sessionResponse('', status: 302, location: '/cas/login')
            : sessionResponse('{"result":true}'),
      );
      await LeaveService(
        dio: Dio()..httpClientAdapter = adapter,
        reauthenticate: () async => true,
      ).submit(fields: {'qjsy': '病假'}, attachmentPath: attachment.path);
      expect(posts, 2);
      expect(
        adapter.bodies.every((body) => body.contains('attachment-proof')),
        isTrue,
      );
      expect(
        adapter.bodies.every((body) => body.contains('filename="proof.txt"')),
        isTrue,
      );
      expect(
        identical(adapter.requests[0].data, adapter.requests[1].data),
        isFalse,
      );
    } finally {
      await attachment.delete();
      await directory.delete();
    }
  });
}
