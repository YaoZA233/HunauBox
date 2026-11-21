import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart';

class TuitionPaymentService {
  TuitionPaymentService({Dio? dio}) : _dio = dio ?? Dio();
  static const agency = '430000000-100006001';
  static const _base = 'https://cwcx.hunau.edu.cn/SFPT_CLIENT_API';
  final Dio _dio;
  final String _guestKey = _uuid();
  final String _deviceId = _uuid();
  String? _token;

  Future<Map<String, dynamic>> createSession() async {
    final data = await _request('POST', '/api/query/anonToken', body: const {});
    _token = data['userToken']?.toString();
    if (_token?.isNotEmpty != true) throw Exception('学费查询会话初始化失败');
    return data;
  }

  Future<Map<String, dynamic>> fetchCaptcha() async {
    await _ensureSession();
    try {
      return await _request(
        'GET',
        '/api/common/captcha/create',
        query: const {'type': 'h5_login', 'firstRequired': 'true'},
      );
    } catch (error) {
      if (!error.toString().contains('2004113')) rethrow;
      _token = null;
      await createSession();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return _request(
        'GET',
        '/api/common/captcha/create',
        query: const {'type': 'h5_login', 'firstRequired': 'true'},
      );
    }
  }

  Future<Uint8List> fetchCaptchaImage(String id) async {
    await _ensureSession();
    final r = await _dio.get<List<int>>(
      '$_base/api/common/captcha/$id.gif',
      options: Options(responseType: ResponseType.bytes, headers: _headers()),
    );
    if (r.statusCode != 200 || r.data == null) throw Exception('验证码图片加载失败');
    return Uint8List.fromList(r.data!);
  }

  Future<Map<String, dynamic>> queryStudent({
    required String idCard,
    required String name,
    required String captchaId,
    required String captchaCode,
    String? captchaVerification,
  }) async {
    await _ensureSession();
    final data = await _request(
      'POST',
      '/api/query/doQuery',
      allowApiFailure: true,
      body: {
        'agencyNm': agency,
        'openid': null,
        'username': _sm2(idCard.trim()),
        'xm': _sm2(name.trim()),
        'captchaId': captchaId,
        'captchaCode': captchaCode.trim(),
        'captchaVerification': captchaVerification,
      },
    );
    if (data['success'] != true) {
      throw Exception(_message(data, '身份证号或姓名校验失败，请确认与学校登记信息一致'));
    }
    final token = data['userToken']?.toString();
    if (token?.isNotEmpty == true) _token = token;
    return data;
  }

  Future<List<Map<String, dynamic>>> getFeeTypes() async =>
      _list((await _request('GET', '/api/dm/anno/sflx'))['data']);
  Future<List<Map<String, dynamic>>> getBatches({
    List<String>? typeCodes,
  }) async => _list(
    (await _request(
      'POST',
      '/api/wjpc/list',
      body: {'sfxmlxdm': typeCodes?.join(',')},
    ))['data'],
  );
  Future<List<Map<String, dynamic>>> getMyNotices({
    String status = 'unpaid',
    int? year,
  }) async => _list(
    (await _request(
      'POST',
      '/api/wjpc/myNoticeList',
      body: {'recordStatus': status, 'kjnd': year},
    ))['data'],
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool allowApiFailure = false,
  }) async {
    final r = await _dio.request<dynamic>(
      '$_base$path',
      queryParameters: query,
      data: body,
      options: Options(
        method: method,
        headers: _headers(),
        contentType: Headers.jsonContentType,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (r.statusCode == null || r.statusCode! >= 400)
      throw Exception('学校缴费服务请求失败（HTTP ${r.statusCode}）');
    if (r.data is! Map) throw Exception('学校缴费服务返回格式异常');
    final data = Map<String, dynamic>.from(r.data as Map);
    if (!allowApiFailure && data['success'] == false)
      throw Exception(_message(data, '学校缴费服务拒绝了请求'));
    return data;
  }

  Map<String, String> _headers() => {
    'agencyNm': agency,
    'version': '1.0.0',
    'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
    'nonce': _randomText(16),
    'X-Guest-Key': _guestKey,
    'X-Device-Id': _deviceId,
    'userToken': _token ?? '',
    'kjnd': DateTime.now().year.toString(),
    'Content-Type': 'application/json;charset=UTF-8',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Origin': 'https://cwcx.hunau.edu.cn',
    'Referer': 'https://cwcx.hunau.edu.cn/SFPT_H5/',
  };
  Future<void> _ensureSession() async {
    if (_token == null) await createSession();
  }

  static List<Map<String, dynamic>> _list(dynamic d) => d is List
      ? d.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];
  static String _message(Map<String, dynamic> d, String fallback) {
    final raw = (d['detailMsg'] ?? d['msg'] ?? d['message'])?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;

    final text = raw.toLowerCase();
    if (text.contains('验证码') ||
        text.contains('captcha') ||
        text.contains('verify code')) {
      return '图片验证码错误，请刷新后重试';
    }
    if (text.contains('token') ||
        text.contains('会话') ||
        text.contains('登录失效') ||
        text.contains('2004113')) {
      return '查询会话已失效，请刷新验证码后重试';
    }
    if (text.contains('密码') ||
        text.contains('password') ||
        text.contains('身份') ||
        text.contains('学号') ||
        text.contains('姓名') ||
        text.contains('用户不存在') ||
        text.contains('未找到')) {
      return '身份证号或姓名校验失败，请确认与学校登记信息一致';
    }
    return '缴费平台暂时无法完成身份核验：$raw';
  }

  static String _uuid() {
    final b = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String _randomText(int n) {
    const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(n, (_) => c[r.nextInt(c.length)]).join();
  }

  static String _sm2(String value) {
    const pk =
        '044aca97a20c2d90538e620bde80e438871ee4ebf61417c54a26c95d4fbbef8843e0324b7a90162a36d93110b757d73fd98281effc102ef8c6dcc2d4dc41f2e9f8';
    final h = pk.substring(2);
    final q = (
      BigInt.parse(h.substring(0, 64), radix: 16),
      BigInt.parse(h.substring(64), radix: 16),
    );
    final p = BigInt.parse(
      'FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF',
      radix: 16,
    );
    final a = p - BigInt.from(3);
    final b = BigInt.parse(
      '28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93',
      radix: 16,
    );
    final n = BigInt.parse(
      'FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123',
      radix: 16,
    );
    const gxHex =
        '32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7';
    const gyHex =
        'BC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0';
    final g = (BigInt.parse(gxHex, radix: 16), BigInt.parse(gyHex, radix: 16));
    final m = Uint8List.fromList(utf8.encode(value));
    final random = Random.secure();
    while (true) {
      final kb = List<int>.generate(32, (_) => random.nextInt(256));
      final k =
          BigInt.parse(
            kb.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
            radix: 16,
          ) %
          n;
      if (k == BigInt.zero) continue;
      final c1 = _mul(g, k, p, a, b);
      final shared = _mul(q, k, p, a, b);
      if (c1 == null || shared == null) continue;
      final x2 = _fixed(shared.$1, 32), y2 = _fixed(shared.$2, 32);
      final t = <int>[];
      var ct = 1;
      while (t.length < m.length) {
        t.addAll(
          SM3Digest().process(
            Uint8List.fromList([
              ...x2,
              ...y2,
              (ct >> 24) & 255,
              (ct >> 16) & 255,
              (ct >> 8) & 255,
              ct & 255,
            ]),
          ),
        );
        ct++;
      }
      final c2 = List<int>.generate(m.length, (i) => m[i] ^ t[i]);
      final c3 = SM3Digest().process(Uint8List.fromList([...x2, ...m, ...y2]));
      // sm-crypto mode=1 uses uncompressed C1 || C3 || C2.
      return [
        4,
        ..._fixed(c1.$1, 32),
        ..._fixed(c1.$2, 32),
        ...c3,
        ...c2,
      ].map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    }
  }

  static (BigInt, BigInt)? _mul(
    (BigInt, BigInt)? point,
    BigInt k,
    BigInt p,
    BigInt a,
    BigInt b,
  ) {
    (BigInt, BigInt)? result;
    var addend = point;
    while (k > BigInt.zero) {
      if (k.isOdd) result = _add(result, addend, p, a, b);
      addend = _add(addend, addend, p, a, b);
      k >>= 1;
    }
    return result;
  }

  static (BigInt, BigInt)? _add(
    (BigInt, BigInt)? l,
    (BigInt, BigInt)? r,
    BigInt p,
    BigInt a,
    BigInt b,
  ) {
    if (l == null) return r;
    if (r == null) return l;
    final (x1, y1) = l;
    final (x2, y2) = r;
    if (x1 == x2 && (y1 + y2) % p == BigInt.zero) return null;
    final slope = x1 == x2 && y1 == y2
        ? ((BigInt.from(3) * x1 * x1 + a) * (BigInt.two * y1).modInverse(p)) % p
        : ((y2 - y1).remainder(p) * _mod(x2 - x1, p).modInverse(p)) % p;
    final x3 = _mod(slope * slope - x1 - x2, p);
    final y3 = _mod(slope * (x1 - x3) - y1, p);
    if (_mod(y3 * y3 - (x3 * x3 * x3 + a * x3 + b), p) != BigInt.zero)
      throw StateError('Invalid SM2 point');
    return (x3, y3);
  }

  static BigInt _mod(BigInt value, BigInt modulus) {
    final result = value.remainder(modulus);
    return result.isNegative ? result + modulus : result;
  }

  static List<int> _fixed(BigInt v, int length) {
    final h = v.toRadixString(16).padLeft(length * 2, '0');
    return List<int>.generate(
      length,
      (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16),
    );
  }
}
