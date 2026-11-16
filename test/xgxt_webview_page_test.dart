import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/pages/xgxt_webview_page.dart';
import 'package:smart_hunan_agri/services/xgxt_login_service.dart';

class FakeXgxtLogin extends Fake implements XgxtLoginService {
  FakeXgxtLogin(this.prepare);
  final Future<bool> Function() prepare;
  int calls = 0;
  int publications = 0;
  @override
  Future<bool> ensureSession() {
    calls++;
    return prepare();
  }

  @override
  Future<void> publishBrowserSession() async {
    publications++;
  }
}

class FakeWebPlatform extends InAppWebViewPlatform {
  final views = <FakeWebWidget>[];
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    final view = FakeWebWidget(params);
    views.add(view);
    return view;
  }
}

class FakeWebWidget extends PlatformInAppWebViewWidget {
  FakeWebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: ValueKey('native-webview'));
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

class FakeWebController extends Fake implements InAppWebViewController {
  final loads = <URLRequest>[];
  int reloads = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadUrl) {
      loads.add(invocation.namedArguments[#urlRequest] as URLRequest);
      return Future<void>.value();
    }
    if (invocation.memberName == #reload) {
      reloads++;
      return Future<void>.error(StateError('WebView 连接中断'));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late FakeWebPlatform platform;
  setUp(() {
    platform = FakeWebPlatform();
    InAppWebViewPlatform.instance = platform;
  });

  testWidgets('浏览器落回 SSO 时自动恢复一次，持续失败有界退出', (tester) async {
    final login = FakeXgxtLogin(() async => true);
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    await tester.pumpAndSettle();
    var params = platform.views.last.params;
    final first = FakeWebController();
    params.onWebViewCreated!(first);
    await tester.pump();
    params.onLoadStop!(first, WebUri(AppConstants.ssoLoginUrl));
    await tester.pumpAndSettle();
    expect(login.calls, 2);
    params = platform.views.last.params;
    final second = FakeWebController();
    params.onWebViewCreated!(second);
    await tester.pump();
    params.onLoadStop!(second, WebUri(AppConstants.ssoLoginUrl));
    await tester.pumpAndSettle();
    expect(find.text('学工网页会话未能恢复，请重新登录后重试'), findsOneWidget);
    expect(login.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WebView 重试方法异常被处理，最多重试三次', (tester) async {
    final login = FakeXgxtLogin(() async => true);
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    await tester.pumpAndSettle();
    final params = platform.views.last.params;
    final controller = FakeWebController();
    params.onWebViewCreated!(controller);
    await tester.pump();
    params.onReceivedError!(
      controller,
      WebResourceRequest(
        url: WebUri(AppConstants.xgxtWapUrl),
        isForMainFrame: true,
      ),
      WebResourceError(type: WebResourceErrorType.UNKNOWN, description: '连接中断'),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(controller.reloads, 3);
    expect(find.text('加载失败，请检查网络连接后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    expect(controller.reloads, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('等待会话同步完成再创建浏览器，首次直达主页且不二次清空会话', (tester) async {
    final ready = Completer<bool>();
    final login = FakeXgxtLogin(() => ready.future);
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    expect(platform.views, isEmpty);
    ready.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('native-webview')), findsOneWidget);
    final controller = FakeWebController();
    platform.views.last.params.onWebViewCreated!(controller);
    await tester.pump();
    expect(controller.loads.single.url.toString(), AppConstants.xgxtWapUrl);
    expect(login.calls, 1);
    expect(login.publications, 0);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('主文档 HTTP 错误不被后续 loadStop 清除，过期浏览器回调在退出后被忽略', (tester) async {
    final login = FakeXgxtLogin(() async => true);
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    await tester.pumpAndSettle();
    final params = platform.views.last.params;
    final controller = FakeWebController();
    params.onWebViewCreated!(controller);
    await tester.pump();
    final uri = WebUri(AppConstants.xgxtWapUrl);
    params.onLoadStart!(controller, uri);
    params.onReceivedHttpError!(
      controller,
      WebResourceRequest(url: uri, isForMainFrame: true),
      WebResourceResponse(statusCode: 503, reasonPhrase: 'Unavailable'),
    );
    await tester.pump();
    params.onLoadStop!(controller, uri);
    await tester.pumpAndSettle();
    expect(find.text('服务器暂时不可用，请稍后重试'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    params.onProgressChanged!(controller, 100);
    params.onLoadStart!(controller, uri);
    params.onLoadStop!(controller, uri);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务连接失败显示重新连接，不误导用户重新输入账号密码', (tester) async {
    final login = FakeXgxtLogin(
      () async => throw const XgxtSessionException('学工服务正在维护'),
    );
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法进入学工系统'), findsOneWidget);
    expect(find.text('学工服务正在维护'), findsOneWidget);
    expect(find.text('去登录'), findsNothing);
    await tester.tap(find.text('重新连接'));
    await tester.pumpAndSettle();
    expect(login.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真正未登录时提供登录及自动重试入口', (tester) async {
    final login = FakeXgxtLogin(() async => false);
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录后可进入学工系统'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('重试自动登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('准备会话超时可重试，旧请求返回不覆盖新请求状态', (tester) async {
    final old = Completer<bool>();
    var attempt = 0;
    final login = FakeXgxtLogin(
      () => attempt++ == 0 ? old.future : Future.value(false),
    );
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    await tester.pump(const Duration(seconds: 61));
    expect(find.textContaining('加载超时'), findsOneWidget);
    await tester.tap(find.text('重新连接'));
    await tester.pumpAndSettle();
    expect(login.calls, 2);
    expect(find.text('学工登录未完成，请重新登录后重试'), findsOneWidget);
    old.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('学工登录未完成，请重新登录后重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待登录时离开页面，迟到的结果不会触发 setState after dispose', (tester) async {
    final ready = Completer<bool>();
    final login = FakeXgxtLogin(() => ready.future);
    await tester.pumpWidget(
      MaterialApp(home: XgxtWebViewPage(loginService: login)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    ready.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
