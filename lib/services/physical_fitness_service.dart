import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';

class PhysicalFitnessTable {
  const PhysicalFitnessTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

class PhysicalFitnessResult {
  const PhysicalFitnessResult({
    required this.title,
    required this.message,
    required this.tables,
  });

  final String title;
  final String message;
  final List<PhysicalFitnessTable> tables;
}

class PhysicalFitnessService {
  PhysicalFitnessService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.interceptors.add(CookieManager(_cookies));
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 20);
  }

  static const _base = 'http://ndtzcs.hunau.edu.cn';
  static const _secretKey = 'G2UJmsauiQbQuryahBhOKQ==';
  final Dio _dio;
  final CookieJar _cookies = CookieJar();

  Future<Uint8List> fetchCaptcha() async {
    await _dio.get<List<int>>(
      '$_base/wxlogin',
      queryParameters: const {'method': 'login'},
      options: Options(responseType: ResponseType.bytes),
    );
    final response = await _dio.get<List<int>>(
      '$_base/servlet/UpdateDate',
      queryParameters: {
        'method': 'validateCode',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Referer': '$_base/wxlogin?method=login'},
      ),
    );
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('体测验证码加载失败，请点击刷新重试');
    }
    return Uint8List.fromList(response.data!);
  }

  Future<PhysicalFitnessResult> login({
    required String studentId,
    required String password,
    required String captcha,
  }) async {
    final encryptedId = Uri.encodeComponent(_encrypt(studentId.trim()));
    final encryptedPassword = Uri.encodeComponent(_encrypt(password));
    final ajax = await _dio.post<List<int>>(
      '$_base/wxlogin',
      queryParameters: const {'method': 'ajaxLogin'},
      data: {
        'vIDNo': encryptedId,
        'vIDPwd': encryptedPassword,
        'vICode': captcha.trim(),
        'loginFlag': '1',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.bytes,
        headers: {'Referer': '$_base/wxlogin?method=login'},
      ),
    );
    final ajaxMessage = _decode(ajax.data ?? const []);
    if (ajaxMessage.trim() != 'success') {
      throw Exception(
        ajaxMessage.trim().isEmpty ? '体测系统登录失败，请检查账号和验证码' : ajaxMessage.trim(),
      );
    }

    final page = await _dio.post<List<int>>(
      '$_base/wxlogin',
      queryParameters: const {'method': 'login'},
      data: {
        'dIDNo': studentId.trim(),
        'dIDPwd': password,
        'vICode': captcha.trim(),
        'vIDNo': encryptedId,
        'vIDPwd': encryptedPassword,
        'loginType': '0',
        'loginFlag': '1',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.bytes,
        headers: {'Referer': '$_base/wxlogin?method=login'},
      ),
    );
    var document = html_parser.parse(_decode(page.data ?? const []));
    var tables = _extractTables(document);
    if (tables.isEmpty) {
      final scoreDocument = await _findScoreDocument(document);
      if (scoreDocument != null) {
        document = scoreDocument;
        tables = _extractTables(document);
      }
    }
    final pageText =
        document.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    final title = document.querySelector('title')?.text.trim() ?? '体测成绩';
    return PhysicalFitnessResult(
      title: title.isEmpty ? '体测成绩' : title,
      message: tables.isEmpty
          ? (pageText.contains('学生服务平台')
                ? '登录成功，但学校系统没有返回可展示的成绩页面。请点击刷新验证码后重试。'
                : pageText)
          : '',
      tables: tables,
    );
  }

  List<PhysicalFitnessTable> _extractTables(dom.Document document) {
    final tables = <PhysicalFitnessTable>[];
    for (final table in document.querySelectorAll('table')) {
      final rows = table
          .querySelectorAll('tr')
          .where((row) {
            var parent = row.parentNode;
            while (parent != null && !identical(parent, table)) {
              if (parent is dom.Element && parent.localName == 'table') {
                return false;
              }
              parent = parent.parentNode;
            }
            return identical(parent, table);
          })
          .map(
            (row) => row.children
                .where(
                  (cell) => cell.localName == 'th' || cell.localName == 'td',
                )
                .map(_cellText)
                .toList(),
          )
          .where((row) => row.length >= 3 && row.any((cell) => cell.isNotEmpty))
          .toList();
      if (rows.length < 2) continue;
      final text = table.text;
      if (!text.contains('学年总分') && !text.contains('体测项目')) continue;
      tables.add(
        PhysicalFitnessTable(headers: rows.first, rows: rows.skip(1).toList()),
      );
    }
    return tables;
  }

  static String _cellText(dom.Element cell) {
    final parts = <String>[];
    for (final node in cell.nodes) {
      if (node is dom.Text) {
        parts.add(node.data);
      } else if (node is dom.Element && node.localName != 'table') {
        parts.add(node.text);
      }
    }
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<dom.Document?> _findScoreDocument(dom.Document root) async {
    final stuNo = root
        .querySelector('input[name="stuNo"]')
        ?.attributes['value'];
    final schoolId = root
        .querySelector('input[name="schoolid"]')
        ?.attributes['value'];

    // The logged-in menu submits this form instead of linking to a page. The
    // healthscore method is the authoritative route for the current result.
    for (final method in const ['healthscore', 'exercise', 'gymscore']) {
      try {
        final response = await _dio.post<List<int>>(
          '$_base/spQuery',
          data: {
            'method': method,
            if (stuNo != null && stuNo.isNotEmpty) 'stuNo': stuNo,
            if (schoolId != null && schoolId.isNotEmpty) 'schoolid': schoolId,
          },
          options: Options(
            responseType: ResponseType.bytes,
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'Referer': '$_base/wxlogin?method=login',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36',
            },
          ),
        );
        if (response.statusCode != 200 || response.data == null) continue;
        final document = html_parser.parse(_decode(response.data!));
        if (_extractTables(document).isNotEmpty) return document;
      } on DioException {
        // Continue with the menu route discovery below for older deployments.
      }
    }

    final candidates = <String>{};
    void addCandidate(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      var value = raw.trim();
      if (value.startsWith('javascript:')) {
        final match = RegExp(
          r'''(?:['"])((?:https?://|/)[^'"]*(?:spQuery|score|grade)[^'"]*)(?:['"])''',
          caseSensitive: false,
        ).firstMatch(value);
        value = match?.group(1) ?? '';
      }
      if (value.isEmpty) return;
      final lower = value.toLowerCase();
      if (lower.contains('logout') || lower.contains('setpassword')) return;
      if (!(lower.contains('spquery') ||
          lower.contains('score') ||
          lower.contains('grade') ||
          lower.contains('成绩'))) {
        return;
      }
      try {
        final uri = Uri.parse(value);
        candidates.add(
          uri.hasScheme
              ? uri.toString()
              : Uri.parse(_base).resolveUri(uri).toString(),
        );
      } catch (_) {
        // Ignore malformed menu entries and continue discovering the page.
      }
    }

    for (final element in root.querySelectorAll(
      'a[href], frame[src], iframe[src], form[action], [onclick]',
    )) {
      final text = element.text.trim().toLowerCase();
      final attrs = element.attributes;
      addCandidate(attrs['href']);
      addCandidate(attrs['src']);
      addCandidate(attrs['action']);
      addCandidate(attrs['onclick']);
      if (text.contains('体测成绩') || text.contains('成绩')) {
        addCandidate(attrs['href']);
        addCandidate(attrs['src']);
        addCandidate(attrs['action']);
        addCandidate(attrs['onclick']);
      }
    }
    // Some versions build the menu entirely inside a script instead of an
    // anchor. Extract those route strings as a final discovery pass.
    for (final match in RegExp(
      r'''['"]((?:https?://|/)[^'"]*(?:spQuery|score|grade)[^'"]*)['"]''',
      caseSensitive: false,
    ).allMatches(root.outerHtml)) {
      addCandidate(match.group(1));
    }
    // Older deployments use a fixed servlet route with a method name that is
    // only referenced by JavaScript. These are cheap session-bound probes and
    // cover the known variants without rendering the service-platform home.
    for (final method in const [
      'healthscore',
      'score',
      'queryScore',
      'queryscore',
      'scoreQuery',
      'sportScore',
      'sportResult',
      'querySport',
    ]) {
      addCandidate('/spQuery?method=$method');
    }
    for (final url in candidates) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Referer': '$_base/wxlogin?method=login'},
          ),
        );
        if (response.statusCode != 200 || response.data == null) continue;
        final document = html_parser.parse(_decode(response.data!));
        if (_extractTables(document).isNotEmpty) return document;
      } on DioException {
        continue;
      }
    }
    return null;
  }

  String _encrypt(String value) {
    final key = base64Decode(_secretKey);
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))
          ..init(
            true,
            PaddedBlockCipherParameters<KeyParameter, Null>(
              KeyParameter(key),
              null,
            ),
          );
    return base64Encode(cipher.process(Uint8List.fromList(utf8.encode(value))));
  }

  static String _decode(List<int> bytes) {
    final header = ascii
        .decode(bytes.take(600).toList(), allowInvalid: true)
        .toLowerCase();
    if (header.contains('charset=gbk') || header.contains('charset="gbk"')) {
      return gbk.decode(bytes);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return gbk.decode(bytes);
    }
  }
}
