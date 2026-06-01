import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;

import '../models/app_constants.dart';
import '../models/course_model.dart';
import '../services/app_logger.dart';
import '../services/secure_storage_helper.dart';
import '../services/timetable_storage.dart';
import '../utils/ics_generator.dart';
import '../utils/timetable_html_parser.dart';

class TimetableService {
  final _logger = AppLogger.instance;

  Future<List<CourseModel>> fetchTimetable(String semester) async {
    final html = await _fetchTimetableHtml(semester);
    return TimetableHtmlParser.parseTimetable(html);
  }

  Future<List<CourseModel>> downloadAndSaveTimetable({
    required String semester,
    required DateTime firstWeekMonday,
  }) async {
    final html = await _fetchTimetableHtml(semester);
    final courses = TimetableHtmlParser.parseTimetable(html);

    if (courses.isEmpty) {
      throw Exception('未解析到任何课程');
    }

    final icsContent = IcsGenerator.generate(courses, firstWeekMonday);
    final storage = TimetableStorage();
    await storage.saveTimetable(icsContent);
    await storage.saveCourseList(courses);
    await storage.saveMetadata(
      semester: semester,
      firstWeekMonday: firstWeekMonday,
    );

    return courses;
  }

  Future<String> _fetchTimetableHtml(String semester) async {
    final storage = SecureStorageHelper();
    final username = await storage.getUsername();
    final password = await storage.getPassword();

    if (username == null || password == null) {
      throw Exception('请先登录以保存凭据');
    }

    final completer = Completer<String>();
    bool completed = false;
    bool loginInjected = false;
    bool syncTriggered = false;

    final cookieManager = webview.CookieManager.instance();

    final headlessWebView = webview.HeadlessInAppWebView(
      initialUrlRequest: webview.URLRequest(url: webview.WebUri(AppConstants.webvpnPortalUrl)),
      initialSettings: webview.InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useHybridComposition: true,
        mixedContentMode: webview.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ),
      onLoadStop: (controller, url) async {
        if (completed) return;
        final urlString = url?.toString() ?? '';

        if ((urlString.contains('/cas/login') || urlString.contains('sso.hunau.edu.cn')) && !loginInjected) {
          await Future.delayed(const Duration(seconds: 2));

          final jsUsername = jsonEncode(username);
          final jsPassword = jsonEncode(password);

          final injectionResult = await controller.evaluateJavascript(source: '''
            (async function() {
              const sleep = (ms) => new Promise(r => setTimeout(r, ms));
              for (let i = 0; i < 15; i++) {
                const queryInFrames = (selector) => {
                  let el = document.querySelector(selector);
                  if (el) return el;
                  const frames = document.querySelectorAll('iframe');
                  for (let f of frames) {
                    try {
                      let doc = f.contentDocument || f.contentWindow.document;
                      let e = doc.querySelector(selector);
                      if (e) return e;
                    } catch (err) {}
                  }
                  return null;
                };

                const userInput = queryInFrames('input.email-username') || queryInFrames('input[name="username"]');
                const passInput = queryInFrames('input[name="authcode"]') || queryInFrames('input[type="password"]');
                const loginBtn = queryInFrames('button.exeActionBtn') || queryInFrames('.login-btn');

                if (userInput && passInput && loginBtn) {
                  userInput.value = $jsUsername;
                  passInput.value = $jsPassword;
                  loginBtn.click();
                  return 'INJECTED_AND_CLICKED';
                }
                await sleep(1000);
              }
              return 'NOT_FOUND';
            })();
          ''');

          if (injectionResult == 'INJECTED_AND_CLICKED') {
            loginInjected = true;
          }
        }

        if (urlString.contains('/fusion/') && !syncTriggered) {
          final cookies = await cookieManager.getCookies(url: url!);
          final hasTicket = cookies.any((c) => c.name == 'wengine_vpn_ticketwebvpn_hunau_edu_cn');

          if (hasTicket) {
            syncTriggered = true;
            await Future.delayed(const Duration(seconds: 2));
            await controller.loadUrl(urlRequest: webview.URLRequest(
              url: webview.WebUri(AppConstants.webvpnCookieSyncUrl),
            ));
          }
        }

        if (urlString.contains('wengine-vpn/cookie')) {
          await controller.loadUrl(urlRequest: webview.URLRequest(
            url: webview.WebUri(AppConstants.jwxtSsoUrl),
          ));
          return;
        }

        if (urlString.contains('sso.jsp')) {
          await controller.evaluateJavascript(source: "window.location.href = 'framework/xsMainV.jsp';");
          await Future.delayed(const Duration(seconds: 3));
          final currentUrl = await controller.getUrl();
          if (currentUrl != null && currentUrl.toString().contains('sso.jsp')) {
            await controller.loadUrl(urlRequest: webview.URLRequest(
              url: webview.WebUri(AppConstants.jwxtFrameworkUrl),
            ));
          }
          return;
        }

        if (!urlString.contains('wengine-vpn/cookie') &&
            !urlString.contains('sso.jsp') &&
            (urlString.contains('framework') || urlString.contains('xsMain'))) {
          await Future.delayed(const Duration(seconds: 6));
          await controller.loadUrl(urlRequest: webview.URLRequest(
            url: webview.WebUri(AppConstants.jwxtTimetableUrl(semester)),
          ));
        }

        if (urlString.contains('xskb_list.do')) {
          for (int attempt = 1; attempt <= 10; attempt++) {
            await Future.delayed(const Duration(seconds: 2));
            final htmlStr = (await controller.getHtml()) ?? '';

            if (htmlStr.contains('timetable') || htmlStr.contains('kbcontent') || htmlStr.contains('节次')) {
              completed = true;
              completer.complete(htmlStr);
              return;
            }

            if (htmlStr.contains('flag1":2') || htmlStr.contains('请先登录') || htmlStr.contains('请重新登录')) {
              await controller.reload();
            }
          }

          if (!completed) {
            completer.completeError(Exception('课表页面加载超时'));
          }
        }
      },
    );

    await headlessWebView.run();

    try {
      return await completer.future.timeout(const Duration(seconds: 90));
    } catch (e) {
      _logger.e('❌ Timetable fetch failed: $e');
      rethrow;
    } finally {
      headlessWebView.dispose();
    }
  }
}
