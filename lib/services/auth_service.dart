import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;

import '../models/app_constants.dart';
import 'app_logger.dart';
import 'secure_storage_helper.dart';
import 'app_cookie_manager.dart';

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AuthService {
  final _storage = SecureStorageHelper();
  final _logger = AppLogger.instance;
  final dio = Dio();

  AuthService() {
    dio.interceptors.add(CookieManager(AppCookieManager().dioCookieJar));
  }

  /// 获取详细的用户资料（姓名、头像）
  Future<Map<String, String?>> fetchFullUserInfo() async {
    try {
      String? cookieUid = await AppCookieManager().getCookieValue('https://passport2.chaoxing.com', 'UID');
      cookieUid ??= await AppCookieManager().getCookieValue('https://passport2.chaoxing.com', '_uid');

      String? realName;
      String? avatarUrl;

      // 尝试从门户首页 HTML 解析姓名
      try {
        final response = await dio.get(AppConstants.portalIndexUrl);
        if (response.statusCode == 200 && response.data != null) {
          final String html = response.data.toString();
          final infoTxtMatch = RegExp(r'<div class="infoTxt">([\s\S]*?)<\/div>').firstMatch(html);
          
          if (infoTxtMatch != null) {
            final infoHtml = infoTxtMatch.group(1)!;
            final nameMatch = RegExp(r'<em>(.*?)<\/em>').firstMatch(infoHtml);
            if (nameMatch != null) realName = nameMatch.group(1);
          }
        }
      } catch (e) {
        _logger.w('⚠️ User profile parsing failed: $e');
      }

      // 获取超星头像
      if (cookieUid != null) {
        avatarUrl = await _fetchAvatar(cookieUid);
      }

      return {
        'realName': realName,
        'avatarUrl': avatarUrl,
      };
    } catch (e) {
      _logger.e('❌ Profile retrieval error: $e');
      return {};
    }
  }

  Future<String?> _fetchAvatar(String uid) async {
    try {
      final avatarApiUrl = AppConstants.fusionAvatarUrl(uid);
      final tempDir = await getApplicationDocumentsDirectory();
      final savePath = p.join(tempDir.path, 'avatar_$uid.png');

      String finalUrl = avatarApiUrl;
      int redirectCount = 0;

      while (redirectCount < 5) {
        final headRes = await dio.get(
          finalUrl,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              'Referer': AppConstants.portalBaseUrl,
            },
          ),
        );

        if (headRes.statusCode == 302 || headRes.statusCode == 301) {
          String? location = headRes.headers.value('location');
          if (location == null) break;
          if (location.startsWith('/')) {
            final uri = Uri.parse(finalUrl);
            location = '${uri.scheme}://${uri.host}$location';
          }
          if (location.contains('cas/login') || location.contains('passport2.chaoxing.com/login')) {
            finalUrl = '';
            break;
          }
          finalUrl = location;
          redirectCount++;
        } else {
          break;
        }
      }

      if (finalUrl.isNotEmpty) {
        final downloadRes = await dio.download(
          finalUrl,
          savePath,
          options: Options(
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              'Referer': AppConstants.portalBaseUrl,
            },
          ),
        );
        final contentType = downloadRes.headers.value('content-type') ?? '';
        if (!contentType.contains('text/html') && !contentType.contains('application/json')) {
          _logger.d('🖼️ Avatar saved to $savePath');
          return savePath;
        }
      }
    } catch (e) {
      _logger.w('⚠️ Avatar check/download failed: $e');
    }
    return null;
  }

  Future<void> login(String username, String password, BuildContext context) async {
    _logger.i('🚀 正在尝试为 $username 登录...');

    final completer = Completer<void>();
    webview.HeadlessInAppWebView? webView;

    bool isLoginSubmitted = false;
    bool isLoginSuccess = false;

    final ssoLoginUrl =
        '${AppConstants.ssoLoginUrl}?service=${Uri.encodeComponent('${AppConstants.portalBaseUrl}/login')}';

    webView = webview.HeadlessInAppWebView(
      initialSize: const Size(1080, 1920), // 防止由于 0x0 极小尺寸渲染导致的 Chromium 底层崩溃
      initialUrlRequest: webview.URLRequest(url: webview.WebUri(ssoLoginUrl)),
      initialSettings: webview.InAppWebViewSettings(
        javaScriptEnabled: true, 
        domStorageEnabled: true,
        useShouldOverrideUrlLoading: false,
        userAgent: 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
        mixedContentMode: webview.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        loadsImagesAutomatically: false,
        disableDefaultErrorPage: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
      ),
      onLoadStart: (controller, url) async {
        final urlString = url?.toString() ?? '';
        final isLoginPage = urlString.contains('/cas/login') ||
            urlString.contains('/authn/login.html') ||
            urlString.contains('sso.hunau.edu.cn');
                              
        if (isLoginPage && !isLoginSubmitted && !isLoginSuccess) {
          _logger.d('🔐 检测到 SSO 登录页，准备自动注入...');
          
          final result = await controller.evaluateJavascript(source: '''
            (async function() {
              const sleep = (ms) => new Promise(r => setTimeout(r, ms));
              for (let i = 0; i < 20; i++) {
                if (!document.body) {
                  await sleep(500);
                  continue;
                }

                const findError = () => {
                  const texts = ['密码错误', '账号或密码不正确', '验证码错误', '失败', '非法'];
                  const bodyText = document.body.innerText || '';
                  for (let t of texts) {
                    if (bodyText.includes(t)) return t;
                  }
                  return null;
                };

                const err = findError();
                if (err) return 'LOGIN_ERROR: ' + err;

                const queryInside = (selector) => {
                  let el = document.querySelector(selector);
                  if (el) return el;
                  const frames = document.querySelectorAll('iframe');
                  for (const f of frames) {
                    try {
                      let doc = f.contentDocument || f.contentWindow.document;
                      let e = doc.querySelector(selector);
                      if (e) return e;
                    } catch (e) {}
                  }
                  return null;
                };

                const u = queryInside('input.email-username') || queryInside('input[name="username"]');
                const p = queryInside('input[name="authcode"]') || queryInside('input[type="password"]');
                
                if (u && p) {
                  u.value = '$username';
                  p.value = '$password';

                  let b = queryInside('button.exeActionBtn') ||
                          queryInside('input[type="submit"]') ||
                          queryInside('button[type="submit"]') ||
                          queryInside('.login-btn');

                  if (b) {
                    b.click();
                    return 'SUBMITTED_VIA_CLICK';
                  } else if (u.form) {
                    u.form.submit();
                    return 'SUBMITTED_VIA_FORM';
                  }
                }
                
                await sleep(500);
              }
              return 'NOT_FOUND';
            })();
          ''');

          if (result != null) {
            final resStr = result.toString();
            if (resStr.contains('SUBMITTED')) {
              isLoginSubmitted = true;
            } else if (resStr.contains('LOGIN_ERROR')) {
              if (!completer.isCompleted) completer.completeError(Exception(resStr));
            }
          }
        }
      },
      onLoadStop: (controller, url) async {
        final urlString = url?.toString() ?? '';
        final isPortalSuccess = urlString.contains('portal.hunau.edu.cn') && !urlString.contains('/cas/login');
        
        if (isPortalSuccess && !isLoginSuccess) {
          isLoginSuccess = true;
          _logger.i('✅ 登录成功，同步 Cookie 中...');
          await AppCookieManager().syncMultiDomainCookiesFromWebView();
          await _storage.saveUsername(username);
          await _storage.savePassword(password);
          if (!completer.isCompleted) completer.complete();
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        _logger.d('🌐 [WebView] ${consoleMessage.message}');
      },
    );

    await webView.run();
    try {
      await completer.future.timeout(const Duration(seconds: 60));
    } finally {
      webView.dispose();
    }
  }
}
