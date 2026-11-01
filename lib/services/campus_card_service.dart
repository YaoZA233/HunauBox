import 'dart:async';

import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'session_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';
import '../utils/dkyw_crypto.dart';
import 'finance_cache_store.dart';

enum PaymentMethod { wechat, alipay }

class WeChatRechargeOrder {
  const WeChatRechargeOrder({
    required this.partnerjourno,
    required this.mwebUrl,
    required this.returnurl,
    this.redirectUrl,
    this.prepayId,
  });

  final String partnerjourno;
  final String mwebUrl;
  final String returnurl;
  final String? redirectUrl;
  final String? prepayId;
}

class WeChatPayStatusResult {
  const WeChatPayStatusResult({
    required this.isSuccess,
    required this.isPending,
    this.message,
  });

  final bool isSuccess;
  final bool isPending;
  final String? message;
}

class CampusCardInfo {
  final String name;
  final String idserial;
  final String balance;
  final String? openid;

  CampusCardInfo({
    required this.name,
    required this.idserial,
    required this.balance,
    this.openid,
  });

  @override
  String toString() =>
      'CampusCardInfo(name: $name, idserial: $idserial, balance: $balance)';
}

class CampusCardService {
  /// 使用隔离的 HTTP 客户端验证支付协议，不访问原生 WebView 或真实账户。
  @visibleForTesting
  CampusCardService.forTesting({
    required Dio dio,
    String? openid,
    CampusCardInfo? cachedInfo,
    Future<String?> Function()? authorize,
    required Future<void> Function() clearSession,
    CookieJar? cookieJar,
  }) : _authorizeOverride = authorize,
       _clearSessionOverride = clearSession {
    _dio = dio;
    _openid = openid;
    _cachedInfo = cachedInfo;
    if (cookieJar != null) {
      SessionCookieManager.install(_dio, cookieJar);
      _cookiesReady = true;
    }
  }

  CampusCardService._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        followRedirects: true,
        maxRedirects: 10,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent': AppConstants.campusCardUA,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ),
    );
  }

  static final CampusCardService instance = CampusCardService._internal();

  final _logger = AppLogger.instance;
  late final Dio _dio;
  Future<String?> Function()? _authorizeOverride;
  Future<void> Function()? _clearSessionOverride;
  bool _creatingWeChatOrder = false;
  bool _creatingAlipayOrder = false;
  Future<String?>? _authInProgress;
  Future<CampusCardInfo>? _infoInProgress;
  Future<Map<String, dynamic>>? _paymentCodeInProgress;
  DateTime? infoUpdatedAt;
  CampusCardInfo? _displayInfo;

  Future<FinanceSnapshot?> getStoredCardInfo() =>
      FinanceCacheStore.read('card');

  /// Drain read requests before logout clears cookies and account credentials.
  Future<void> clearSession() async {
    try {
      await _infoInProgress;
    } catch (_) {}
    try {
      await _authInProgress;
    } catch (_) {}
    try {
      await _paymentCodeInProgress;
    } catch (_) {}
    _openid = null;
    _cachedInfo = null;
    _displayInfo = null;
    infoUpdatedAt = null;
  }

  bool _cookiesReady = false;

  String? _openid;
  String? get openid => _openid;

  CampusCardInfo? _cachedInfo;
  CampusCardInfo? get cachedInfo => _cachedInfo;

  /// 清除失效的财务平台会话，保留超星登录态供下一次 OAuth 重新授权。
  Future<void> invalidateSession() async {
    _openid = null;
    _cachedInfo = null;
    if (_clearSessionOverride != null) {
      await _clearSessionOverride!();
      return;
    }
    await AppCookieManager().initialize();
    await SessionCookieManager.clearHostCookies(
      AppCookieManager().dioCookieJar,
      [Uri.parse('https://fin-serv.hunau.edu.cn')],
    );
  }

  Future<String?> authenticate() async {
    if (_authInProgress != null) return _authInProgress!;
    final future = _authenticateHttp();
    _authInProgress = future;
    try {
      return await future;
    } finally {
      if (identical(_authInProgress, future)) _authInProgress = null;
    }
  }

  Future<void> _ensureDioReady() async {
    if (_cookiesReady || _authorizeOverride != null) return;
    await AppCookieManager().initialize();
    SessionCookieManager.install(_dio, AppCookieManager().dioCookieJar);
    _cookiesReady = true;
  }

  Future<String?> _authenticateHttp() async {
    if (_authorizeOverride != null) {
      return _openid = await _authorizeOverride!();
    }
    await _ensureDioReady();
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    var url = Uri.parse(AppConstants.campusCardUrl);
    final cancelToken = CancelToken();
    String? referer;
    try {
      for (var step = 0; step < 10; step++) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) throw TimeoutException('财务授权超时');
        final started = Stopwatch()..start();
        final response = await _dio
            .getUri(
              url,
              cancelToken: cancelToken,
              options: Options(
                followRedirects: false,
                responseType: ResponseType.plain,
                receiveTimeout: remaining,
                headers: {
                  'User-Agent': AppConstants.campusCardUA,
                  'Referer': ?referer,
                },
              ),
            )
            .timeout(
              remaining,
              onTimeout: () {
                cancelToken.cancel('财务授权超时');
                throw TimeoutException('财务授权超时');
              },
            );
        _logger.d(
          '财务授权 $step ${url.host}${url.path}: '
          '${response.statusCode}, ${started.elapsedMilliseconds}ms',
        );
        if (_isInvalidSessionPage(response)) return null;
        final status = response.statusCode ?? 0;
        final location = response.headers.value('location');
        if (status >= 300 && status < 400 && location != null) {
          final next = url.resolve(location);
          if (!['http', 'https'].contains(next.scheme)) return null;
          referer = url.toString();
          url = next;
          continue;
        }
        // Only accept the completed financial homepage, after its Cookie save.
        if (status == 200 &&
            url.host == 'fin-serv.hunau.edu.cn' &&
            url.path.toLowerCase() == '/homecx/openhomepage') {
          final id = url.queryParameters['openid'];
          if (id != null && id.isNotEmpty) return _openid = id;
        }
        return null;
      }
      return null;
    } catch (e) {
      _logger.w('财务 HTTP 授权失败 (${e.runtimeType})');
      return null;
    } finally {
      if (!cancelToken.isCancelled) cancelToken.cancel('授权流程已结束');
    }
  }

  Future<Map<String, dynamic>> fetchPaymentCode({bool isRetry = false}) async {
    if (_paymentCodeInProgress != null) return _paymentCodeInProgress!;
    final future = _fetchPaymentCode(isRetry: isRetry);
    _paymentCodeInProgress = future;
    try {
      return await future;
    } finally {
      if (identical(_paymentCodeInProgress, future)) {
        _paymentCodeInProgress = null;
      }
    }
  }

  Future<Map<String, dynamic>> _fetchPaymentCode({bool isRetry = false}) async {
    await _ensureDioReady();
    if (_openid == null) {
      final authResult = await authenticate();
      if (authResult == null) throw Exception('授权失败，无法获取付款码');
    }

    final url =
        'https://fin-serv.hunau.edu.cn/virtualcard/openVirtualcard?openid=$_openid&displayflag=1&id=27';

    _logger.i('📡 Fetching payment code from: $url (Retry: $isRetry)');

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer':
                'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=$_openid&usertype=2',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();

        if (_isInvalidSessionPage(response)) {
          _logger.w('⚠️ Session expired detected in fetchPaymentCode');
          if (!isRetry) {
            await invalidateSession();
            return _fetchPaymentCode(isRetry: true);
          }
          await invalidateSession();
          throw _CampusCardSessionExpired();
        }

        final qrMatch = RegExp(
          r'id="qrcode".*?src="data:image/png;base64,(.*?)"',
          dotAll: true,
        ).firstMatch(html);
        final qrBase64 = qrMatch
            ?.group(1)
            ?.replaceAll('\n', '')
            .replaceAll('\r', '')
            .trim();

        final codeMatch = RegExp(r'id="code"\s+value="(.*?)"').firstMatch(html);
        final paycode = codeMatch?.group(1);

        final infoMatch = RegExp(r'<p class="bdb">(.*?)<\/p>').firstMatch(html);
        final infoText = infoMatch?.group(1);

        if (infoText != null) {
          _parseAndCacheInfo(infoText);
        } else {
          _logger.d('🔍 Standard info text not found, trying deep scan...');
          _deepScanInfo(html);
        }

        if (qrBase64 == null || paycode == null) {
          _logger.e('❌ Failed to parse QR code or paycode from HTML');
          throw Exception('解析付款码页面失败');
        }

        return {
          'qrBase64': qrBase64,
          'paycode': paycode,
          'info': infoText ?? _cachedInfo?.toString(),
          'openid': _openid,
        };
      }

      throw Exception('网络请求失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ fetchPaymentCode error: $e');
      rethrow;
    }
  }

  Future<CampusCardInfo> fetchRechargeInfo({bool isRetry = false}) async {
    if (_infoInProgress != null) return _infoInProgress!;
    final future = _refreshInfo(isRetry: isRetry);
    _infoInProgress = future;
    try {
      return await future;
    } finally {
      if (identical(_infoInProgress, future)) _infoInProgress = null;
    }
  }

  Future<CampusCardInfo> _refreshInfo({bool isRetry = false}) async {
    final owner = await FinanceCacheStore.account();
    final elapsed = Stopwatch()..start();
    try {
      final info = await _fetchRechargeInfo(isRetry: isRetry);
      infoUpdatedAt = DateTime.now();
      _displayInfo = info;
      await FinanceCacheStore.write(owner, 'card', {
        'name': info.name,
        'idserial': info.idserial,
        'balance': info.balance,
      }, infoUpdatedAt!);
      return info;
    } catch (e) {
      _logger.w('校园卡余额更新失败 (${e.runtimeType})');
      rethrow;
    } finally {
      _logger.d('校园卡余额查询耗时 ${elapsed.elapsedMilliseconds}ms');
    }
  }

  CampusCardInfo? get displayInfo => _displayInfo ?? _cachedInfo;

  Future<CampusCardInfo> _fetchRechargeInfo({bool isRetry = false}) async {
    await _ensureDioReady();
    if (_openid == null) {
      final authResult = await authenticate();
      if (authResult == null) throw Exception('授权失败');
    }

    final url =
        'https://fin-serv.hunau.edu.cn/virtualcard/openVirtualcard?openid=$_openid&displayflag=1&id=27';

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer':
                'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=$_openid&usertype=2',
          },
        ),
      );

      if (_isInvalidSessionPage(response)) {
        _logger.w('⚠️ Session expired detected in fetchRechargeInfo');
        if (!isRetry) {
          await invalidateSession();
          return _fetchRechargeInfo(isRetry: true);
        }
        await invalidateSession();
        throw Exception('财务平台会话失效，请重新登录后重试');
      }

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();

        // 只接受本次页面中的卡片信息，不能用旧缓存掩盖失效页面。
        _cachedInfo = null;
        final infoMatch = RegExp(r'<p class="bdb">(.*?)<\/p>').firstMatch(html);
        final infoText = infoMatch?.group(1);

        if (infoText != null) {
          _parseAndCacheInfo(infoText);
        }

        if (_cachedInfo == null) {
          _logger.d('📡 Performing deep scan for balance...');
          _deepScanInfo(html);
        }

        if (_cachedInfo == null) {
          _logger.d('付款码页无卡片信息，尝试充值页');
          final homeResponse = await _dio.get(
            'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid&displayflag=1&id=28',
            options: Options(
              headers: {'User-Agent': AppConstants.campusCardUA},
            ),
          );
          if (_isInvalidSessionPage(homeResponse)) {
            throw _CampusCardSessionExpired();
          }
          if (homeResponse.data != null) {
            final text = RegExp(
              r'<p class="bdb">(.*?)<\/p>',
            ).firstMatch(homeResponse.data.toString())?.group(1);
            if (text != null) _parseAndCacheInfo(text);
            _deepScanInfo(homeResponse.data.toString());
          }
        }

        if (_cachedInfo == null) {
          throw Exception('无法获取卡片信息');
        }

        return _cachedInfo!;
      }
      throw Exception('网络请求失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ fetchRechargeInfo error: $e');
      if (!isRetry && e is _CampusCardSessionExpired) {
        await invalidateSession();
        return _fetchRechargeInfo(isRetry: true);
      }
      rethrow;
    }
  }

  Future<String> getAlipayForm(double amount) async {
    if (!amount.isFinite ||
        amount < 1 ||
        amount > 1000 ||
        amount != amount.roundToDouble()) {
      throw Exception('充值金额必须是 1–1000 元的整数');
    }
    if (_creatingAlipayOrder) throw Exception('充值订单正在创建，请勿重复提交');
    _creatingAlipayOrder = true;
    try {
      final info = await fetchRechargeInfo();
      try {
        await _postCardPayJson('/myaccount/userlastbind', {
          'payinfo': {'cardpayWay': '4'},
          'idserial': info.idserial,
        });
      } on _CampusCardSessionExpired {
        rethrow;
      } catch (_) {
        _logger.w('记录支付方式失败，继续请求支付宝订单');
      }
      final data = await _postCardPayJson('/alipay/transferFromAlipay2Card', {
        'txamt': amount.toStringAsFixed(0),
        'payWay': '4',
        'openid': _openid,
        'idserial': info.idserial,
      });
      final result = data['resultData'];
      if (data['success']?.toString() == 'true' && result is Map) {
        final html = result['htmlpost']?.toString();
        if (html != null && html.trim().isNotEmpty) return html;
      }
      throw Exception(data['message'] ?? data['msg'] ?? '未取得支付宝订单，请先查看充值记录');
    } on DioException {
      throw Exception('充值请求未能确认，请先查看充值记录，勿重复支付');
    } finally {
      _creatingAlipayOrder = false;
    }
  }

  /// 创建校园卡微信 H5 充值订单。
  Future<WeChatRechargeOrder> createWeChatOrder(double amount) async {
    if (!amount.isFinite ||
        amount < 1 ||
        amount > 1000 ||
        amount != amount.roundToDouble()) {
      throw Exception('充值金额必须是 1–1000 元的整数');
    }
    if (_creatingWeChatOrder) {
      throw Exception('微信充值订单正在创建，请勿重复提交');
    }
    _creatingWeChatOrder = true;
    try {
      // 即使已有 OpenID，也必须用只读请求确认会话仍有效再发起订单。
      final info = await fetchRechargeInfo();
      if (_openid == null || _openid!.isEmpty || info.idserial.isEmpty) {
        throw Exception('无法获取有效的校园卡充值信息');
      }
      // 记录本次支付方式；此接口失败不影响后续下单。
      try {
        await _postCardPayJson('/myaccount/userlastbind', {
          'payinfo': {'cardpayWay': '1'},
          'idserial': info.idserial,
        });
      } on _CampusCardSessionExpired {
        rethrow;
      } catch (e) {
        _logger.w('记录微信支付方式失败（不影响下单）: $e');
      }

      // 下单 POST 不自动重试：超时可能发生在服务端已创建订单之后。
      final data = await _postCardPayJson('/wxpay/transferFromWx2Card', {
        'txamt': amount.toStringAsFixed(0),
        'payWay': '1',
        'openid': _openid,
        'idserial': info.idserial,
        'tradetype': 'WAP',
      });

      if (data['success'] != true) {
        final message = data['message']?.toString().trim();
        throw Exception(
          message == null || message.isEmpty
              ? '财务平台拒绝创建微信充值订单'
              : '创建微信充值订单失败：$message',
        );
      }
      final result = data['resultData'];
      if (result is! Map) {
        throw Exception('微信订单响应缺少订单信息，请先确认充值记录再重试');
      }
      final journo = result['partnerjourno']?.toString().trim() ?? '';
      final mwebUrl = result['mweb_url']?.toString().trim() ?? '';
      final returnurl = _normalizeWeChatReturnUrl(
        result['returnurl']?.toString() ?? '',
      );
      final paymentUri = Uri.tryParse(mwebUrl);
      final returnUri = Uri.tryParse(returnurl);
      if (journo.isEmpty ||
          paymentUri?.scheme != 'https' ||
          paymentUri?.host != 'wx.tenpay.com' ||
          returnUri?.scheme != 'https' ||
          returnUri?.host != 'fin-serv.hunau.edu.cn') {
        throw Exception('微信订单响应不完整或支付地址异常，请先确认充值记录再重试');
      }
      return WeChatRechargeOrder(
        partnerjourno: journo,
        mwebUrl: mwebUrl,
        returnurl: returnurl,
        redirectUrl: result['redirect_url']?.toString(),
        prepayId: result['prepay_id']?.toString(),
      );
    } on DioException catch (e) {
      _logger.e('微信充值请求网络异常: ${e.type}');
      throw Exception('微信充值请求未能确认，请先查看充值记录，勿重复支付');
    } catch (e) {
      _logger.e('创建微信充值订单失败: $e');
      rethrow;
    } finally {
      _creatingWeChatOrder = false;
    }
  }

  Future<Map<String, dynamic>> _postCardPayJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post(
      'https://fin-serv.hunau.edu.cn$path',
      queryParameters: {'openid': _openid, 'connect_redirect': '1'},
      // 与当前 dkyw.request.ajax 一致，JSON 请求也需要 datajson 封装。
      data: {'datajson': DkywCrypto.encryptPayload(payload)},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': AppConstants.campusCardUA,
          'Referer':
              'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid&displayflag=1&id=28',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );
    if (_isInvalidSessionPage(response)) {
      await invalidateSession();
      throw _CampusCardSessionExpired();
    }
    if (response.statusCode != 200) {
      throw Exception('充值接口请求失败（HTTP ${response.statusCode}），请先确认充值记录');
    }
    dynamic decoded;
    try {
      decoded = DkywCrypto.decryptServerResponse(response.data);
    } catch (_) {
      throw Exception('充值接口响应解密失败，请先确认充值记录再重试');
    }
    if (decoded is! Map) {
      throw Exception('充值接口返回格式异常，请先确认充值记录再重试');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static bool _isInvalidSessionPage(Response<dynamic> response) {
    final html = response.data?.toString() ?? '';
    return response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.realUri.path.contains('errorPage') ||
        response.realUri.path.contains('/login') ||
        html.contains('资源受限') ||
        html.contains('页面丢失') ||
        ((html.contains('cas/login') || html.contains('统一身份认证')) &&
            !html.contains('idserial'));
  }

  static String _normalizeWeChatReturnUrl(String value) {
    var url = value.trim();
    // 平台会返回一次或两次编码；已是 URL 时不再解码其查询参数。
    for (
      var i = 0;
      i < 3 && !url.startsWith('http://') && !url.startsWith('https://');
      i++
    ) {
      try {
        final decoded = Uri.decodeComponent(url);
        if (decoded == url) break;
        url = decoded;
      } catch (_) {
        break;
      }
    }
    return url.startsWith('http://')
        ? url.replaceFirst('http://', 'https://')
        : url;
  }

  /// 从微信 H5 支付页提取用于唤起客户端的 weixin:// 地址。
  Future<String?> getWeChatDeepLink(String mwebUrl) async {
    try {
      final response = await _dio.get(
        mwebUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://fin-serv.hunau.edu.cn/',
            'User-Agent': AppConstants.campusCardUA,
          },
        ),
      );
      final html = response.data?.toString() ?? '';
      return RegExp(
        r'''(weixin://wap/pay\?[^"'\s<>\)]+)''',
      ).firstMatch(html)?.group(1);
    } catch (e) {
      _logger.w('提取微信唤起链接失败，将使用 H5 兜底: $e');
      return null;
    }
  }

  Future<WeChatPayStatusResult> queryWeChatPayStatus({
    required String partnerjourno,
    required String returnurl,
  }) async {
    if (_openid == null) throw Exception('未授权 (OpenID 为空)');
    try {
      final response = await _dio.get(
        'https://fin-serv.hunau.edu.cn/wxpay/queryWxWapPayStatus',
        queryParameters: {
          'partnerjourno': partnerjourno,
          'openid': _openid,
          'returnurl': returnurl,
        },
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer':
                'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid',
          },
        ),
      );
      return parseWeChatPayStatusResponse(
        location: response.headers.value('location') ?? '',
        realPath: response.realUri.path,
        body: response.data?.toString() ?? '',
      );
    } catch (e) {
      _logger.w('查询微信支付状态失败，将保持待确认状态: $e');
      return WeChatPayStatusResult(
        isSuccess: false,
        isPending: true,
        message: e.toString(),
      );
    }
  }

  /// 将查询页严格分类，避免把“订单查询中”误判为支付成功。
  static WeChatPayStatusResult parseWeChatPayStatusResponse({
    required String location,
    required String realPath,
    required String body,
  }) {
    if (location.contains('paySuccess') || realPath.contains('paySuccess')) {
      return const WeChatPayStatusResult(isSuccess: true, isPending: false);
    }
    if (body.contains('微信支付订单查询中') || body.contains('icon-wait.png')) {
      return const WeChatPayStatusResult(isSuccess: false, isPending: true);
    }
    final explicitSuccess =
        (body.contains('支付成功') || body.contains('充值成功')) &&
        !body.contains('失败原因') &&
        !body.contains('static.css');
    if (explicitSuccess) {
      return const WeChatPayStatusResult(isSuccess: true, isPending: false);
    }

    final reason = RegExp(
      r'id="message"[^>]*>([^<]+)</p>',
    ).firstMatch(body)?.group(1)?.trim();
    if (reason != null && reason.isNotEmpty && reason != '微信支付订单查询中') {
      return WeChatPayStatusResult(
        isSuccess: false,
        isPending: false,
        message: reason,
      );
    }
    return const WeChatPayStatusResult(isSuccess: false, isPending: true);
  }

  Future<Map<String, dynamic>> queryOrderStatus(String paycode) async {
    if (_openid == null) throw Exception('未授权 (OpenID 为空)');

    const url = 'https://fin-serv.hunau.edu.cn/virtualcard/queryOrderStatus';
    final payload = {'paycode': paycode, 'openid': _openid};

    try {
      final response = await _dio.get(
        url,
        queryParameters: {
          'openid': _openid,
          'connect_redirect': '1',
          'datajson': DkywCrypto.encryptPayload(payload),
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                'https://fin-serv.hunau.edu.cn/virtualcard/openVirtualcard?openid=$_openid&displayflag=1&id=27',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = DkywCrypto.decryptServerResponse(response.data);
        if (data is Map) return Map<String, dynamic>.from(data);
        throw Exception('查询状态失败：响应格式异常');
      }

      throw Exception('查询状态失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ queryOrderStatus error: $e');
      rethrow;
    }
  }

  String getCampusCardHomeUrl() {
    if (_openid == null) return AppConstants.campusCardUrl;
    return 'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=$_openid&usertype=2';
  }

  void _parseAndCacheInfo(String infoText) {
    try {
      _logger.d('🔍 Parsing info text: $infoText');
      final regExp = RegExp(r'([^：:\s]+)[：:]([0-9]+).*?余额[：:]([0-9.]+)');
      final match = regExp.firstMatch(infoText);

      if (match != null) {
        _cachedInfo = CampusCardInfo(
          name: match.group(1)!.trim(),
          idserial: match.group(2)!.trim(),
          balance: match.group(3)!.trim(),
          openid: _openid,
        );
        _logger.i('✅ Parsed Card Info: $_cachedInfo');
      } else {
        _logger.w('⚠️ Regex did not match info text: $infoText');
      }
    } catch (e) {
      _logger.w('⚠️ Error parsing info text: $e');
    }
  }

  void _deepScanInfo(String html) {
    try {
      final nameMatch =
          RegExp(r'id="username"\s+value="([^"]+)"').firstMatch(html) ??
          RegExp(r'name="username"\s+value="([^"]+)"').firstMatch(html);
      final idMatch =
          RegExp(r'id="idserial"\s+value="([^"]+)"').firstMatch(html) ??
          RegExp(r'name="idserial"\s+value="([^"]+)"').firstMatch(html);

      final balanceDeepMatch =
          RegExp(
            r'余额(?:<\/?[^>]+>|[：:\s])*([0-9]+\.[0-9]+)',
          ).firstMatch(html) ??
          RegExp(r'([0-9]+\.[0-9]+)元').firstMatch(html);

      if (nameMatch != null && idMatch != null) {
        final name = nameMatch.group(1)!.trim();
        final idserial = idMatch.group(1)!.trim();
        final balance =
            balanceDeepMatch?.group(1) ?? _cachedInfo?.balance ?? '0.00';

        _cachedInfo = CampusCardInfo(
          name: name,
          idserial: idserial,
          balance: balance,
          openid: _openid,
        );
        _logger.i('✅ Deep scan success: $_cachedInfo');
      }
    } catch (e) {
      _logger.w('⚠️ Deep scan error: $e');
    }
  }
}

class _CampusCardSessionExpired implements Exception {
  @override
  String toString() => 'Exception: 财务平台会话失效，请重新登录后重试';
}
