import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'webvpn_auth_service.dart';

class DormInfo {
  final String dormBuilding;
  final String floor;
  final String room;
  final String bed;
  final DateTime fetchedAt;

  const DormInfo({
    required this.dormBuilding,
    required this.floor,
    required this.room,
    required this.bed,
    required this.fetchedAt,
  });

  bool get hasAny =>
      dormBuilding.isNotEmpty ||
      floor.isNotEmpty ||
      room.isNotEmpty ||
      bed.isNotEmpty;

  bool get hasCoreInfo => dormBuilding.isNotEmpty && bed.isNotEmpty;
}

class DormService {
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36';

  final Dio _dio = Dio();
  bool _cookiesReady = false;

  Future<void> _ensureCookieJar() async {
    if (_cookiesReady) return;
    await AppCookieManager().initialize();
    if (_dio.interceptors.whereType<dio_cookie.CookieManager>().isEmpty) {
      _dio.interceptors.add(
        dio_cookie.CookieManager(AppCookieManager().dioCookieJar),
      );
    }
    _cookiesReady = true;
  }

  Future<DormInfo> fetchDormInfo() async {
    await _ensureCookieJar();
    final webVpnReady = await WebVpnAuthService().ensureSession();
    if (!webVpnReady) {
      throw Exception('WebVPN 自动登录失败，请重新登录后再试');
    }

    await AppCookieManager().syncMultiDomainCookiesFromWebView(
      AppConstants.webvpnBaseUrl,
    );
    await AppCookieManager().syncMultiDomainCookiesToWebView(
      AppConstants.dormServiceUrl,
    );

    // 宿舍信息由页面脚本异步加载，直接请求初始 HTML 只能拿到页面壳。
    final renderedInfo = await _fetchRenderedDormInfo();
    if (renderedInfo?.hasCoreInfo == true) return renderedInfo!;

    final staticInfo = await _fetchStaticDormInfo();
    final info = _mergeInfo(renderedInfo, staticInfo);
    if (!info.hasAny) {
      throw Exception('未能识别宿舍信息，可打开网页核对');
    }
    return info;
  }

  Future<DormInfo?> _fetchRenderedDormInfo() async {
    final completer = Completer<DormInfo?>();
    DormInfo? bestInfo;
    var extractionRunning = false;
    var disposed = false;

    void considerInfo(DormInfo info) {
      if (disposed || !info.hasAny) return;
      bestInfo = _mergeInfo(bestInfo, info);
      if (bestInfo!.hasCoreInfo && !completer.isCompleted) {
        completer.complete(bestInfo);
      }
    }

    final headlessWebView = webview.HeadlessInAppWebView(
      initialUrlRequest: webview.URLRequest(
        url: webview.WebUri(AppConstants.dormServiceUrl),
      ),
      initialUserScripts: UnmodifiableListView<webview.UserScript>([
        webview.UserScript(
          injectionTime: webview.UserScriptInjectionTime.AT_DOCUMENT_START,
          source: '''
            (function() {
              if (window.__dormResponseHookInstalled) return;
              window.__dormResponseHookInstalled = true;

              function reportDormResponse(url, body) {
                if (typeof body !== 'string' || !body || body.length > 1000000) return;
                if (!/(宿舍|楼栋|楼层|房间|床号|床位|dorm|building|floor|room|bed|ldmc|fjh|cwh)/i.test(body)) return;
                try {
                  window.flutter_inappwebview.callHandler('dormResponse', {
                    url: url || '',
                    body: body
                  });
                } catch (e) {}
              }

              if (window.fetch) {
                var originalFetch = window.fetch;
                window.fetch = function() {
                  var args = arguments;
                  return originalFetch.apply(this, args).then(function(response) {
                    try {
                      response.clone().text().then(function(body) {
                        var request = args[0];
                        var url = typeof request === 'string' ? request : (request && request.url);
                        reportDormResponse(url, body);
                      });
                    } catch (e) {}
                    return response;
                  });
                };
              }

              var originalOpen = XMLHttpRequest.prototype.open;
              var originalSend = XMLHttpRequest.prototype.send;
              XMLHttpRequest.prototype.open = function(method, url) {
                this.__dormRequestUrl = url;
                return originalOpen.apply(this, arguments);
              };
              XMLHttpRequest.prototype.send = function() {
                this.addEventListener('load', function() {
                  var body = '';
                  try {
                    body = this.responseText;
                  } catch (e) {
                    try {
                      body = JSON.stringify(this.response);
                    } catch (ignored) {}
                  }
                  reportDormResponse(this.__dormRequestUrl, body);
                });
                return originalSend.apply(this, arguments);
              };
            })();
          ''',
        ),
      ]),
      initialSettings: webview.InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        sharedCookiesEnabled: true,
        thirdPartyCookiesEnabled: true,
        mixedContentMode: webview.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        userAgent: _userAgent,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'dormResponse',
          callback: (arguments) {
            if (disposed || arguments.isEmpty) return null;
            final response = arguments.first;
            if (response is! Map) return null;
            final body = response['body']?.toString() ?? '';
            if (body.isNotEmpty) considerInfo(parseDormPayload(body));
            return null;
          },
        );
      },
      onLoadStop: (controller, url) async {
        if (disposed || extractionRunning || completer.isCompleted) return;
        extractionRunning = true;

        try {
          for (var attempt = 0; attempt < 24; attempt++) {
            if (disposed || completer.isCompleted) return;

            final renderedHtml = await controller.evaluateJavascript(
              source: '''
                (function() {
                  var documents = [document];
                  var frames = document.querySelectorAll('iframe');
                  for (var i = 0; i < frames.length; i++) {
                    try {
                      if (frames[i].contentDocument) {
                        documents.push(frames[i].contentDocument);
                      }
                    } catch (e) {}
                  }
                  return documents.map(function(doc) {
                    return doc.documentElement ? doc.documentElement.outerHTML : '';
                  }).join(' ');
                })();
              ''',
            );

            final html = renderedHtml?.toString() ?? '';
            if (html.isNotEmpty && !_looksLikeLoginPage(html)) {
              considerInfo(parseDormInfo(html));
              if (completer.isCompleted) return;
            }

            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        } finally {
          extractionRunning = false;
        }
      },
    );

    try {
      await headlessWebView.run();
      return await completer.future.timeout(
        const Duration(seconds: 18),
        onTimeout: () => bestInfo,
      );
    } catch (_) {
      return bestInfo;
    } finally {
      disposed = true;
      headlessWebView.dispose();
    }
  }

  Future<DormInfo?> _fetchStaticDormInfo() async {
    final response = await _dio.get<String>(
      AppConstants.dormServiceUrl,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
        headers: const {
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ),
    );

    final html = response.data ?? '';
    if (response.statusCode == null || response.statusCode! >= 400) {
      throw Exception('学生公寓服务响应异常：HTTP ${response.statusCode}');
    }
    if (_looksLikeLoginPage(html)) {
      throw Exception('登录状态未生效，请重新登录后再试');
    }

    final info = parseDormInfo(html);
    return info.hasAny ? info : null;
  }

  bool _looksLikeLoginPage(String html) {
    return html.contains('统一身份认证') ||
        html.contains('/cas/login') ||
        html.contains('login?cas_login') ||
        html.contains('请输入用户名');
  }

  DormInfo parseDormInfo(String html) {
    final values = <String, String>{};
    _collectCreateRowValues(html, values);

    final document = html_parser.parse(html);
    document.querySelectorAll('script,style,noscript').forEach((node) {
      node.remove();
    });

    _collectKeyValueFromTables(document, values);
    _collectKeyValueFromElements(document, values);
    _collectEmbeddedKeyValues(document.body?.text ?? '', values);
    _collectLegacyTextValues(document.body?.text ?? '', values);

    final textLines =
        document.body?.text
            .split(RegExp(r'[\r\n]+'))
            .map(_cleanText)
            .where((line) => line.isNotEmpty)
            .toList() ??
        const <String>[];

    for (var index = 0; index < textLines.length; index++) {
      _collectDelimitedKeyValue(textLines[index], values);
      _collectEmbeddedKeyValues(textLines[index], values);
      _collectLegacyTextValues(textLines[index], values);

      final key = _canonicalKey(textLines[index]);
      if (key != null && index + 1 < textLines.length) {
        _putValue(key, textLines[index + 1], values);
      }
    }

    for (final input in document.querySelectorAll('input,textarea,select')) {
      final key = [
        input.attributes['name'],
        input.attributes['id'],
        input.attributes['placeholder'],
        input.attributes['title'],
        input.attributes['aria-label'],
      ].whereType<String>().join(' ');
      final value = input.attributes['value']?.trim() ?? input.text.trim();
      _putValueFromAttribute(key, value, values);
    }

    return _infoFromValues(values);
  }

  DormInfo parseDormPayload(String payload) {
    final values = <String, String>{};
    final trimmed = payload.trim();

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      final openingParenthesis = trimmed.indexOf('(');
      final closingParenthesis = trimmed.lastIndexOf(')');
      if (openingParenthesis >= 0 && closingParenthesis > openingParenthesis) {
        try {
          decoded = jsonDecode(
            trimmed.substring(openingParenthesis + 1, closingParenthesis),
          );
        } catch (_) {}
      }
    }

    if (decoded != null) _collectJsonValues(decoded, values);
    final htmlInfo = parseDormInfo(payload);
    return _mergeInfo(_infoFromValues(values), htmlInfo);
  }

  void _collectCreateRowValues(String html, Map<String, String> values) {
    final createRowPattern = RegExp(
      r'''view\.createRow\(\s*["']([^"']*)["']\s*,\s*["']([^"']+)["']\s*,\s*["']([^"']*)["']''',
      caseSensitive: false,
    );

    for (final match in createRowPattern.allMatches(html)) {
      final key =
          _canonicalKey(match.group(2) ?? '') ??
          _canonicalDataKey(match.group(1) ?? '');
      if (key != null) _putValue(key, match.group(3) ?? '', values);
    }
  }

  void _collectKeyValueFromTables(
    Document document,
    Map<String, String> values,
  ) {
    for (final table in document.querySelectorAll('table')) {
      final rows = table
          .querySelectorAll('tr')
          .map<List<String>>((row) {
            return row
                .querySelectorAll('th,td')
                .map((cell) => _cleanText(cell.text))
                .where((text) => text.isNotEmpty)
                .toList();
          })
          .where((row) => row.isNotEmpty)
          .toList();

      for (final row in rows) {
        for (var index = 0; index < row.length - 1; index++) {
          final key = _canonicalKey(row[index]);
          if (key != null) _putValue(key, row[index + 1], values);
        }
      }

      for (var rowIndex = 0; rowIndex < rows.length - 1; rowIndex++) {
        final headerRow = rows[rowIndex];
        final valueRow = rows[rowIndex + 1];
        if (headerRow.length != valueRow.length) continue;
        for (var index = 0; index < headerRow.length; index++) {
          final key = _canonicalKey(headerRow[index]);
          if (key != null) _putValue(key, valueRow[index], values);
        }
      }
    }
  }

  void _collectKeyValueFromElements(
    Document document,
    Map<String, String> values,
  ) {
    for (final element in document.querySelectorAll('body *')) {
      final text = _cleanText(element.text);
      _collectDelimitedKeyValue(text, values);
      _collectEmbeddedKeyValues(text, values);

      final children = element.children;
      if (children.length < 2 || children.length > 12) continue;

      for (var index = 0; index < children.length; index++) {
        final key = _canonicalKey(_cleanText(children[index].text));
        if (key == null) continue;

        for (
          var valueIndex = index + 1;
          valueIndex < children.length && valueIndex <= index + 2;
          valueIndex++
        ) {
          final candidate = _cleanText(children[valueIndex].text);
          if (_isSeparator(candidate)) continue;
          if (_canonicalKey(candidate) != null) break;
          if (_putValue(key, candidate, values)) break;
        }
      }
    }
  }

  void _collectDelimitedKeyValue(String text, Map<String, String> values) {
    final match = RegExp(
      r'^\s*(宿舍楼|楼栋|楼号|公寓楼|楼层|所在楼层|房间|房号|寝室|宿舍号|床号|床位)\s*[:：]\s*(.+?)\s*$',
    ).firstMatch(text);
    if (match == null) return;

    final key = _canonicalKey(match.group(1) ?? '');
    if (key != null) _putValue(key, match.group(2) ?? '', values);
  }

  void _collectEmbeddedKeyValues(String text, Map<String, String> values) {
    final normalized = _cleanText(text);
    final patterns = <String, RegExp>{
      '宿舍楼': RegExp(
        r'(?:宿舍楼|楼栋名称|楼栋|楼号|公寓楼)\s*[:：]?\s*([\u4e00-\u9fa5A-Za-z0-9_\-]{2,24}?)(?=\s*(?:所在楼层|楼层|房间名称|房间|房号|寝室|宿舍号|床位号|床号|床位)\s*[:：]?|[,，;；|]|$)',
      ),
      '楼层': RegExp(r'(?:所在楼层|楼层)\s*[:：]?\s*((?:第)?\d{1,3}(?:层|楼)?)'),
      '房间': RegExp(
        r'(?:房间名称|房间|房号|寝室|宿舍号)\s*[:：]?\s*([\u4e00-\u9fa5A-Za-z0-9_\-]{1,24}?)(?=\s*(?:床位号|床号|床位)\s*[:：]?|[,，;；|]|$)',
      ),
      '床号': RegExp(r'(?:床位号|床号|床位)\s*[:：]?\s*(?:第)?(\d{1,2})(?:号床|号|床|床位)?'),
    };

    for (final entry in patterns.entries) {
      for (final match in entry.value.allMatches(normalized)) {
        if (_putValue(entry.key, match.group(1) ?? '', values)) break;
      }
    }
  }

  void _collectLegacyTextValues(String text, Map<String, String> values) {
    final normalized = _cleanText(text);
    final textPatterns = <String, RegExp>{
      '宿舍楼': RegExp(r'(?:宿舍楼|楼栋名称|楼栋|楼号|公寓)\s*[:：]?\s*([^,，;；\s]+)'),
      '楼层': RegExp(r'(?:所在楼层|楼层)\s*[:：]?\s*([^,，;；\s]+)'),
      '房间': RegExp(r'(?:房间名称|房间|房号|寝室|宿舍号)\s*[:：]?\s*([^,，;；\s]+)'),
    };

    for (final entry in textPatterns.entries) {
      for (final match in entry.value.allMatches(normalized)) {
        if (_putValue(entry.key, match.group(1) ?? '', values)) break;
      }
    }

    final bedPattern = RegExp(
      r'(?:床位号|床号|床位)\s*[:：]?\s*(?:获取到\s*)?(?:第)?(\d{1,2})(?:号床|号|床|床位)?',
    );
    for (final match in bedPattern.allMatches(normalized)) {
      if (_putValue('床号', match.group(1) ?? '', values)) break;
    }
  }

  void _collectJsonValues(dynamic node, Map<String, String> values) {
    if (node is List) {
      for (final item in node) {
        _collectJsonValues(item, values);
      }
      return;
    }
    if (node is! Map) return;

    for (final entry in node.entries) {
      final key = _canonicalDataKey(entry.key.toString());
      if (key == null) continue;
      final scalar = _extractScalarValue(entry.value);
      if (scalar != null) _putValue(key, scalar, values);
    }

    for (final value in node.values) {
      _collectJsonValues(value, values);
    }
  }

  String? _extractScalarValue(dynamic value) {
    if (value is String || value is num) return value.toString();
    if (value is! Map) return null;

    const preferredKeys = [
      'name',
      'label',
      'value',
      'text',
      'mc',
      'no',
      'number',
    ];
    for (final key in preferredKeys) {
      final candidate = value[key];
      if (candidate is String || candidate is num) {
        return candidate.toString();
      }
    }
    return null;
  }

  String? _canonicalDataKey(String rawKey) {
    final directKey = _canonicalKey(rawKey);
    if (directKey != null) return directKey;

    final chineseKey = _cleanText(rawKey);
    if (chineseKey.contains('宿舍楼') ||
        chineseKey.contains('楼栋') ||
        chineseKey == '公寓名称') {
      return '宿舍楼';
    }
    if (chineseKey.contains('楼层')) return '楼层';
    if (chineseKey.contains('房间') || chineseKey.contains('房号')) {
      return '房间';
    }
    if (chineseKey.contains('床号') || chineseKey.contains('床位')) {
      return '床号';
    }

    final key = rawKey.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const dataKeys = <String, String>{
      'dormbuilding': '宿舍楼',
      'dormbuildingname': '宿舍楼',
      'building': '宿舍楼',
      'buildingname': '宿舍楼',
      'dormname': '宿舍楼',
      'apartmentname': '宿舍楼',
      'ld': '宿舍楼',
      'ldmc': '宿舍楼',
      'ssl': '宿舍楼',
      'sslmc': '宿舍楼',
      'floor': '楼层',
      'floorname': '楼层',
      'floornumber': '楼层',
      'lc': '楼层',
      'lcmc': '楼层',
      'szlc': '楼层',
      'room': '房间',
      'roomname': '房间',
      'roomno': '房间',
      'roomnumber': '房间',
      'fj': '房间',
      'fjh': '房间',
      'fjmc': '房间',
      'bed': '床号',
      'bedname': '床号',
      'bedno': '床号',
      'bednumber': '床号',
      'berth': '床号',
      'cw': '床号',
      'cwh': '床号',
      'cwmc': '床号',
    };
    return dataKeys[key];
  }

  void _putValueFromAttribute(
    String rawKey,
    String rawValue,
    Map<String, String> values,
  ) {
    final directKey = _canonicalKey(rawKey);
    if (directKey != null) {
      _putValue(directKey, rawValue, values);
      return;
    }

    final key = rawKey.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const attributeKeys = <String, String>{
      'dormbuilding': '宿舍楼',
      'buildingname': '宿舍楼',
      'dormname': '宿舍楼',
      'floor': '楼层',
      'floorname': '楼层',
      'room': '房间',
      'roomno': '房间',
      'roomname': '房间',
      'bed': '床号',
      'bedno': '床号',
      'bedname': '床号',
    };
    final matchedKey = attributeKeys[key];
    if (matchedKey != null) _putValue(matchedKey, rawValue, values);
  }

  String? _canonicalKey(String rawKey) {
    final key = _cleanText(rawKey).replaceFirst(RegExp(r'[:：]$'), '');
    const aliases = <String, String>{
      '宿舍楼': '宿舍楼',
      '宿舍楼名称': '宿舍楼',
      '楼栋': '宿舍楼',
      '楼栋名称': '宿舍楼',
      '楼号': '宿舍楼',
      '公寓楼': '宿舍楼',
      '楼层': '楼层',
      '所在楼层': '楼层',
      '房间': '房间',
      '房间名称': '房间',
      '房号': '房间',
      '寝室': '房间',
      '宿舍号': '房间',
      '床号': '床号',
      '床位': '床号',
      '床位号': '床号',
    };
    return aliases[key];
  }

  bool _putValue(String key, String rawValue, Map<String, String> values) {
    final value = _cleanValue(key, rawValue);
    if (value == null || values.containsKey(key)) return false;
    values[key] = value;
    return true;
  }

  String? _cleanValue(String key, String rawValue) {
    var value = _cleanText(
      rawValue,
    ).replaceFirst(RegExp(r'^[：:\-—]+'), '').trim();
    if (value.isEmpty || value.length > 40 || _canonicalKey(value) != null) {
      return null;
    }

    const invalidValues = {
      '服务平台',
      '学生公寓服务平台',
      '获取到',
      '未获取到',
      '暂无',
      '暂无数据',
      '加载中',
      '查询中',
      '获取失败',
      '未安排',
      '未安排床位',
      '--',
      '-',
    };
    if (invalidValues.contains(value) ||
        value.startsWith('未获取') ||
        value.startsWith('正在获取') ||
        value.startsWith('请先登录')) {
      return null;
    }

    if (key == '宿舍楼' && (value.endsWith('服务平台') || value == '学生公寓')) {
      return null;
    }
    if (key == '宿舍楼' && !RegExp(r'[\u4e00-\u9fa5A-Za-z]').hasMatch(value)) {
      return null;
    }
    if (key == '宿舍楼') {
      const chineseDigits = {
        '1': '一',
        '2': '二',
        '3': '三',
        '4': '四',
        '5': '五',
        '6': '六',
        '7': '七',
        '8': '八',
        '9': '九',
      };
      value = value.replaceAllMapped(
        RegExp(r'^丰泽([1-9])([北南])$'),
        (match) => '丰泽${chineseDigits[match.group(1)]}${match.group(2)}',
      );
    }

    if (key == '床号') {
      final match = RegExp(
        r'^(?:第)?(\d{1,2})(?:号床|号|床|床位)?$',
      ).firstMatch(value);
      if (match == null) return null;
      value = match.group(1)!;
    }

    return value;
  }

  bool _isSeparator(String value) => RegExp(r'^[：:\-—]+$').hasMatch(value);

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  DormInfo _infoFromValues(Map<String, String> values) {
    return DormInfo(
      dormBuilding: values['宿舍楼'] ?? '',
      floor: values['楼层'] ?? '',
      room: values['房间'] ?? '',
      bed: values['床号'] ?? '',
      fetchedAt: DateTime.now(),
    );
  }

  DormInfo _mergeInfo(DormInfo? primary, DormInfo? fallback) {
    String first(String? preferred, String? alternate) {
      return preferred?.isNotEmpty == true ? preferred! : alternate ?? '';
    }

    return DormInfo(
      dormBuilding: first(primary?.dormBuilding, fallback?.dormBuilding),
      floor: first(primary?.floor, fallback?.floor),
      room: first(primary?.room, fallback?.room),
      bed: first(primary?.bed, fallback?.bed),
      fetchedAt: DateTime.now(),
    );
  }
}
