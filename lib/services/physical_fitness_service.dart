import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:fast_gbk/fast_gbk.dart';
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
      queryParameters: const {'method': 'validateCode'},
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
    final document = html_parser.parse(_decode(page.data ?? const []));
    final pageText =
        document.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    final tables = <PhysicalFitnessTable>[];
    for (final table in document.querySelectorAll('table')) {
      final rows = table
          .querySelectorAll('tr')
          .map(
            (row) => row
                .querySelectorAll('th,td')
                .map((cell) => cell.text.trim())
                .toList(),
          )
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isEmpty) continue;
      tables.add(
        PhysicalFitnessTable(headers: rows.first, rows: rows.skip(1).toList()),
      );
    }
    final title = document.querySelector('title')?.text.trim() ?? '体测成绩';
    return PhysicalFitnessResult(
      title: title.isEmpty ? '体测成绩' : title,
      message: pageText,
      tables: tables,
    );
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
