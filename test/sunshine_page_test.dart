import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/pages/sunshine_page.dart';
import 'package:smart_hunan_agri/services/sunshine_service.dart';

import 'support/session_http_adapter.dart';
import 'sunshine_service_test.dart' show SunshineFixture;

void main() {
  testWidgets('阳光表单加载失败可返回和重试，不停留在无限加载', (tester) async {
    final fixture = SunshineFixture()..renewalSucceeds = false;
    await tester.pumpWidget(
      MaterialApp(home: SunshineFormPage(service: fixture.service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('提交诉求'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    fixture.renewalSucceeds = true;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('写下你想推动的改变'), findsOneWidget);
    expect(find.text('重新加载'), findsNothing);
  });

  testWidgets('阳光列表展示可操作的登录错误和重试入口', (tester) async {
    final fixture = SunshineFixture()..renewalSucceeds = false;
    await tester.pumpWidget(
      MaterialApp(home: SunshinePage(service: fixture.service)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('统一认证未能自动恢复'), findsOneWidget);
    fixture.renewalSucceeds = true;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('测试诉求'), findsOneWidget);
  });

  testWidgets('提交返回手机号校验失败保留表单，不提示成功', (tester) async {
    final fixture = SunshineFixture(validSunshine: true)..submitResult = '2';
    await tester.pumpWidget(
      MaterialApp(home: SunshineFormPage(service: fixture.service)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '标题');
    await tester.enterText(find.byType(TextField).at(1), '具体内容');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('确认提交'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(find.text('手机号或验证码校验失败，请检查后重试'), findsOneWidget);
    expect(find.text('诉求提交成功'), findsNothing);
    expect(find.text('确认提交'), findsOneWidget);
    expect(fixture.writes, 1);
  });

  testWidgets('阳光表单网络超时展示友好错误', (tester) async {
    final service = SunshineService(
      dio: Dio()
        ..httpClientAdapter = SessionHttpAdapter(
          (r) => throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          ),
        ),
    );
    await tester.pumpWidget(
      MaterialApp(home: SunshineFormPage(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('响应超时'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });
}
