import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';

import '../models/app_constants.dart';
import '../models/sunshine_models.dart';
import 'app_cookie_manager.dart';
import 'auth_service.dart';
import 'dio_client.dart';
import 'session_cookie_manager.dart';

class SunshineException implements Exception {
  final String message;
  const SunshineException(this.message);
  @override
  String toString() => message;
}

class SunshineService {
  static final _shared = SunshineService._();
  factory SunshineService({
    Dio? dio,
    Future<bool> Function()? reauthenticate,
    Future<void> Function()? syncSsoCookies,
  }) => dio == null && reauthenticate == null && syncSsoCookies == null
      ? _shared
      : SunshineService._(
          dio: dio,
          reauthenticate: reauthenticate,
          syncSsoCookies: syncSsoCookies,
        );

  SunshineService._({
    Dio? dio,
    Future<bool> Function()? reauthenticate,
    Future<void> Function()? syncSsoCookies,
  }) : _dio = dio,
       _reauthenticate = reauthenticate ?? AuthService().silentLogin,
       _syncSsoCookies = syncSsoCookies;
  final Dio? _dio;
  final Future<bool> Function() _reauthenticate;
  final Future<void> Function()? _syncSsoCookies;
  Future<SunshineIdentity>? _recovering;

  Future<Dio> get client async {
    if (_dio != null) return _dio;
    await DioClient().initialize();
    return DioClient().dio;
  }

  String _decode(List<int> bytes, RequestOptions _, ResponseBody response) {
    final charset =
        response.headers[Headers.contentTypeHeader]?.join(' ').toLowerCase() ??
        '';
    if (charset.contains('gbk') || charset.contains('gb2312')) {
      return gbk.decode(bytes);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return gbk.decode(bytes);
    }
  }

  Options get _options => Options(
    responseType: ResponseType.plain,
    contentType: Headers.formUrlEncodedContentType,
    // Adapter redirects hide intermediate Set-Cookie from CookieManager.
    followRedirects: false,
    validateStatus: (s) => s != null && s < 500,
    receiveTimeout: const Duration(seconds: 30),
    // Legacy ASP.NET connections can become unusable after OAuth.
    persistentConnection: false,
    responseDecoder: _decode,
    headers: {
      'Connection': 'close',
      'Referer': '${AppConstants.sunshineBaseUrl}/form.aspx?type=2',
      'X-Requested-With': 'XMLHttpRequest',
    },
  );

  Options get _navigationOptions => _options.copyWith(
    headers: {
      'Connection': 'close',
      'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
      'Referer': AppConstants.sunshineBaseUrl,
    },
  );

  bool _needsLogin(Response response) {
    final status = response.statusCode ?? 0;
    if ((status >= 300 && status < 400) || status == 401 || status == 403) {
      return true;
    }
    if (response.data is! String) return false;
    final text = (response.data as String).trimLeft().toLowerCase();
    // Valid JSON may contain a user's HTML in Content/Remark.
    if (text.startsWith('{') || text.startsWith('[')) return false;
    return text.startsWith('<') ||
        text.contains('cas/login') ||
        text.contains('oauthlogin.aspx');
  }

  Map<String, dynamic> _object(Response response) {
    if (response.statusCode != 200) {
      throw const SunshineException('阳光服务暂时不可用，请稍后重试');
    }
    try {
      final data = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    throw const SunshineException('阳光服务数据格式异常，请稍后重试');
  }

  List<Map<String, dynamic>> _rows(Response response) {
    final rows = _object(response)['rows'];
    if (rows is! List || rows.any((row) => row is! Map)) {
      throw const SunshineException('阳光服务返回的数据格式异常');
    }
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<SunshineIdentity?> _identity(Dio dio) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await dio.get(
          '${AppConstants.sunshineBaseUrl}/form.aspx',
          queryParameters: {'type': '2'},
          options: _navigationOptions,
        );
        return response.statusCode == 200
            ? SunshineIdentity.fromHtml('${response.data}')
            : null;
      } on DioException catch (e) {
        final retryable =
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError;
        if (!retryable || attempt == 1) {
          throw const SunshineException('阳光服务连接失败或响应超时，请稍后重试');
        }
      }
    }
    return null;
  }

  Future<void> _authorize(Dio dio) async {
    var uri = Uri.parse(AppConstants.sunshineAuthorizationUrl);
    // CAS OAuth legitimately revisits the same authorize URL once:
    // authorize -> cas/login -> callbackAuthorize -> authorize -> OAuthLogin.
    // Only a self-redirect or a third visit of the same URL is a real loop.
    final visits = <Uri, int>{};
    for (var i = 0; i < 10; i++) {
      final count = visits.update(uri, (n) => n + 1, ifAbsent: () => 1);
      if (count > 2) throw const SunshineException('阳光服务授权跳转异常，请稍后重试');
      final response = await dio.getUri(uri, options: _navigationOptions);
      if (!const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        return;
      }
      final loc = response.headers.value('location');
      if (loc == null || loc.isEmpty) {
        throw const SunshineException('阳光服务授权跳转不完整');
      }
      var next = uri.resolve(loc);
      // ChillEast upgrades the legacy HTTP callback before sending its code.
      if (next.scheme == 'http' &&
          next.host == Uri.parse(AppConstants.sunshineBaseUrl).host &&
          next.port == 80) {
        next = next.replace(scheme: 'https', port: 443);
      }
      if (next.scheme != 'https' ||
          next.port != 443 ||
          next.userInfo.isNotEmpty ||
          ![
            Uri.parse(AppConstants.ssoBaseUrl).host,
            Uri.parse(AppConstants.sunshineBaseUrl).host,
          ].contains(next.host)) {
        throw const SunshineException('阳光服务返回了非预期的认证跳转');
      }
      if (next == uri) throw const SunshineException('阳光服务授权跳转异常，请稍后重试');
      uri = next;
    }
    throw const SunshineException('阳光服务授权跳转次数超限');
  }

  Future<SunshineIdentity> _ensureIdentity(Dio dio) async {
    final pending = _recovering;
    if (pending != null) return pending;
    final identity = await _identity(dio);
    return identity ?? await _recover(dio);
  }

  Future<SunshineIdentity> _recover(Dio dio) =>
      _recovering ??= _restoreSession(dio)
          .then((identity) async {
            if (_dio == null) {
              await AppCookieManager().replaceWebViewSession([
                AppConstants.sunshineBaseUrl,
                '${AppConstants.sunshineBaseUrl}/form.aspx',
              ]);
            }
            return identity;
          })
          .whenComplete(() {
            _recovering = null;
          });

  Future<SunshineIdentity> _restoreSession(Dio dio) async {
    try {
      for (final interceptor
          in dio.interceptors.whereType<SessionCookieManager>()) {
        await SessionCookieManager.clearHostCookies(interceptor.cookieJar, [
          Uri.parse(AppConstants.sunshineBaseUrl),
          Uri.parse('${AppConstants.sunshineBaseUrl}/form.aspx'),
          Uri.parse('${AppConstants.sunshineBaseUrl}/AJAX/form.ashx'),
          Uri.parse('${AppConstants.sunshineBaseUrl}/OAuthLogin.aspx'),
        ]);
      }
      await _authorize(dio);
      var identity = await _identity(dio);
      if (identity != null) return identity;
      // Only import SSO cookies: stale WebView service cookies must not
      // overwrite fresh HTTP XGXT/ASP sessions from another feature.
      if (_syncSsoCookies != null || _dio == null) {
        await (_syncSsoCookies?.call() ??
            AppCookieManager()
                .syncMultiDomainCookiesFromWebView(AppConstants.ssoBaseUrl, [
                  AppConstants.ssoBaseUrl,
                  '${AppConstants.ssoBaseUrl}/cas/',
                  AppConstants.ssoLoginUrl,
                  '${AppConstants.ssoBaseUrl}/authn/',
                ]));
        await _authorize(dio);
        identity = await _identity(dio);
        if (identity != null) return identity;
      }
      if (!await _reauthenticate()) {
        throw const SunshineException('统一认证未能自动恢复，请在个人中心检查账号或完成验证');
      }
      await _authorize(dio);
      identity = await _identity(dio);
      if (identity != null) return identity;
      throw const SunshineException('阳光服务会话未能恢复，请重新登录后重试');
    } on SunshineException {
      rethrow;
    } on DioException {
      throw const SunshineException('阳光服务授权连接失败，请稍后重试');
    }
  }

  Future<Response> _read(
    Future<Response> Function(Dio) request, {
    bool checked = false,
  }) async {
    final dio = await client;
    if (!checked) await _ensureIdentity(dio);
    var response = await request(dio);
    if (_needsLogin(response)) {
      await _recover(dio);
      response = await request(dio);
    }
    if (_needsLogin(response)) {
      throw const SunshineException('阳光服务会话未能恢复，请重新登录后重试');
    }
    return response;
  }

  Future<SunshineStatistics> fetchStatistics() async =>
      SunshineStatistics.fromJson(
        _object(
          await _read(
            (dio) => dio.post(
              '${AppConstants.sunshineBaseUrl}/AJAX/index.ashx',
              queryParameters: {'AFlag': 'Statistics'},
              options: _options,
            ),
          ),
        ),
      );

  Future<List<SunshineLetter>> fetchLetters() async => _rows(
    await _read(
      (dio) => dio.post(
        '${AppConstants.sunshineBaseUrl}/AJAX/index.ashx',
        data: {'AFlag': 'Suggestion'},
        options: _options,
      ),
    ),
  ).map(SunshineLetter.fromJson).toList();

  Future<SunshineTicketDetail> fetchTicketDetail(String id) async {
    final rows = _rows(
      await _read(
        (dio) => dio.post(
          '${AppConstants.sunshineBaseUrl}/AJAX/form.ashx',
          data: {'AFlag': 'Detail', 'ID': id},
          options: _options,
        ),
      ),
    );
    if (rows.isEmpty) throw const SunshineException('未找到诉求工单详情');
    return SunshineTicketDetail.fromJson(rows.first, id: id);
  }

  Future<SunshineFormData> fetchForm() async {
    await _ensureIdentity(await client);
    final response = await _read(
      (dio) => dio.post(
        '${AppConstants.sunshineBaseUrl}/AJAX/form.ashx',
        data: {'AFlag': 'LoadCompany'},
        options: _options,
      ),
      checked: true,
    );
    final departments = _rows(response)
        .map(SunshineDepartment.fromJson)
        .where((d) => d.code.isNotEmpty && d.name.isNotEmpty)
        .toList();
    if (departments.isEmpty) throw const SunshineException('暂无可用受理单位');
    // Department loading may have renewed the session under a changed account.
    final currentIdentity = await _ensureIdentity(await client);
    return SunshineFormData(currentIdentity, departments);
  }

  /// Renew on a read BEFORE submission; never replay a sent POST.
  Future<String> submit({
    required SunshineIdentity identity,
    required SunshineDepartment department,
    required String type,
    required String title,
    required String content,
    required String phone,
    required String email,
    required String finishTime,
  }) async {
    final dio = await client;
    final current = await _ensureIdentity(dio);
    if (current.cardCode != identity.cardCode) {
      throw const SunshineException('当前登录账号已变化，请重新打开诉求表单');
    }
    try {
      final response = await dio.post(
        '${AppConstants.sunshineBaseUrl}/AJAX/form.ashx',
        queryParameters: {'AFlag': 'insert'},
        data: {
          'type1': type,
          'depid': department.code,
          'depname': department.name,
          'title': title.trim(),
          'content': content.trim(),
          'username': current.name,
          'telphone': phone.trim(),
          'email': email.trim(),
          'finishtime': finishTime,
          'captchas': '',
          'CardCode': current.cardCode,
        },
        options: _options,
      );
      if (response.statusCode != 200 || _needsLogin(response)) return 'unknown';
      final result = '${response.data}'.trim();
      return ['1', '2', 'errer'].contains(result) ? result : 'unknown';
    } on DioException {
      return 'unknown';
    }
  }
}
