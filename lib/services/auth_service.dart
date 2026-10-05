import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../models/app_constants.dart';
import 'app_logger.dart';
import 'secure_storage_helper.dart';
import 'app_cookie_manager.dart';
import 'http_login_service.dart';
import 'sso_auth_exception.dart';
import 'session_cookie_manager.dart';

import 'package:path_provider/path_provider.dart';

class AuthService {
  AuthService({
    HttpLoginService? httpLoginService,
    SecureStorageHelper? storage,
    AppCookieManager? cookies,
  }) : _httpLoginService = httpLoginService ?? HttpLoginService(),
       _storage = storage ?? SecureStorageHelper(),
       _cookies = cookies ?? AppCookieManager();
  static Future<bool>? _silentLoginInProgress;
  final SecureStorageHelper _storage;
  final HttpLoginService _httpLoginService;
  final AppCookieManager _cookies;
  final _logger = AppLogger.instance;
  final dio = Dio();

  bool _cookiesReady = false;
  Future<void> _ensureCookies() async {
    if (_cookiesReady) return;
    await _cookies.initialize();
    SessionCookieManager.install(dio, _cookies.dioCookieJar);
    _cookiesReady = true;
  }

  /// 获取详细的用户资料（姓名、头像）
  Future<Map<String, String?>> fetchFullUserInfo() async {
    try {
      await _ensureCookies();
      String? cookieUid = await AppCookieManager().getCookieValue(
        'https://passport2.chaoxing.com',
        'UID',
      );
      cookieUid ??= await AppCookieManager().getCookieValue(
        'https://passport2.chaoxing.com',
        '_uid',
      );

      String? realName;
      String? avatarUrl;

      // 尝试从门户首页 HTML 解析姓名
      try {
        final response = await dio.get(AppConstants.portalIndexUrl);
        if (response.statusCode == 200 && response.data != null) {
          final String html = response.data.toString();
          final infoTxtMatch = RegExp(
            r'<div class="infoTxt">([\s\S]*?)<\/div>',
          ).firstMatch(html);

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

      return {'realName': realName, 'avatarUrl': avatarUrl};
    } catch (e) {
      _logger.e('❌ Profile retrieval error: $e');
      return {};
    }
  }

  Future<String?> _fetchAvatar(String uid) async {
    try {
      final avatarApiUrl = AppConstants.fusionAvatarUrl(uid);
      final tempDir = await getApplicationDocumentsDirectory();
      final savePath = '${tempDir.path}/avatar_$uid.png';

      String finalUrl = avatarApiUrl;
      int redirectCount = 0;

      while (redirectCount < 5) {
        final headRes = await dio.get(
          finalUrl,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
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
          if (location.contains('cas/login') ||
              location.contains('passport2.chaoxing.com/login')) {
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
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              'Referer': AppConstants.portalBaseUrl,
            },
          ),
        );
        final contentType = downloadRes.headers.value('content-type') ?? '';
        if (!contentType.contains('text/html') &&
            !contentType.contains('application/json')) {
          _logger.d('🖼️ Avatar saved to $savePath');
          return savePath;
        }
      }
    } catch (e) {
      _logger.w('⚠️ Avatar check/download failed: $e');
    }
    return null;
  }

  Future<void> login(String username, String password, BuildContext context) =>
      _login(username, password);

  /// Refresh unified authentication without requiring a page visit.
  Future<bool> silentLogin() {
    return _silentLoginInProgress ??= _silentLogin().whenComplete(() {
      _silentLoginInProgress = null;
    });
  }

  Future<bool> _silentLogin() async {
    final generation = _sessionGeneration;
    try {
      final username = await _storage.getUsername();
      final password = await _storage.getPassword();
      if (username == null ||
          username.isEmpty ||
          password == null ||
          password.isEmpty) {
        return false;
      }
      if (generation != _sessionGeneration) return false;
      await _login(username, password);
      return true;
    } catch (e) {
      _logger.w('统一认证自动刷新失败（${e.runtimeType}）');
      return false;
    }
  }

  static Future<void>? _loginInProgress;
  static String? _loginUsername;
  static String? _loginPassword;
  static int _sessionGeneration = 0;

  /// Logout waits for cookie publishers before clearing, so a late refresh
  /// cannot restore the previous account's session.
  static Future<void> cancelPendingLogins() async {
    _sessionGeneration++;
    try {
      await _silentLoginInProgress;
    } catch (_) {}
    try {
      await _loginInProgress;
    } catch (_) {}
  }

  Future<void> _login(String username, String password) async {
    final generation = _sessionGeneration;
    while (_loginInProgress != null) {
      final pending = _loginInProgress!;
      if (_loginUsername == username && _loginPassword == password) {
        return pending;
      }
      try {
        await pending;
      } catch (_) {}
      if (generation != _sessionGeneration) {
        throw const SsoAuthException('登录已取消');
      }
    }
    _loginUsername = username;
    _loginPassword = password;
    final attempt = _loginWithHttp(username, password, generation);
    _loginInProgress = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_loginInProgress, attempt)) {
        _loginInProgress = null;
        _loginUsername = null;
        _loginPassword = null;
      }
    }
  }

  Future<void> _loginWithHttp(
    String username,
    String password,
    int generation,
  ) async {
    // The attempt owns a new empty jar. A valid portal cookie cannot bypass
    // password authentication while the CAS TGC needed by other apps is stale.
    final result = await _httpLoginService.login(username, password);
    if (generation != _sessionGeneration) throw const SsoAuthException('登录已取消');
    await _cookies.initialize();
    await _cookies.saveHttpLoginCookies(result.cookies);
    if (generation != _sessionGeneration) throw const SsoAuthException('登录已取消');
    await _storage.saveUsername(username);
    await _storage.savePassword(password);
    _logger.i('统一认证已刷新，新会话已同步');
  }
}
