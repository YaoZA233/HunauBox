import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 财务服务平台 dkyw.js 使用的动态 AES-ECB/PKCS7 协议。
class DkywCrypto {
  DkywCrypto._();

  static const _chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  static String genKey([int length = 16]) {
    final random = Random.secure();
    return List.generate(
      length,
      (_) => _chars[random.nextInt(_chars.length)],
    ).join();
  }

  /// 对应网页端 my-encryption.js 的密钥移位和反转逻辑。
  static String handleKey(String key, bool isEncrypt) {
    if (key.length != 16) throw ArgumentError.value(key, 'key', '必须为 16 位');
    if (isEncrypt) {
      final rotated = key.substring(10) + key.substring(0, 10);
      return rotated.split('').reversed.join();
    }

    final reversed = key.split('').reversed.join();
    return reversed.substring(6) + reversed.substring(0, 6);
  }

  /// 返回“16 位变换后密钥 + Base64 密文”。
  static String encryptPayload(dynamic data, {String? key}) {
    final jsonText = data is String ? data : jsonEncode(data);
    final keyText = key ?? genKey();
    final encrypted = _crypt(
      Uint8List.fromList(utf8.encode(jsonText)),
      keyText,
      encrypt: true,
    );
    return '${handleKey(keyText, true)}${base64Encode(encrypted)}';
  }

  static dynamic decryptPayload(String datajson) {
    if (datajson.length <= 16) return datajson;
    final keyText = handleKey(datajson.substring(0, 16), false);
    final cipherText = base64Decode(datajson.substring(16));
    final decrypted = _crypt(cipherText, keyText, encrypt: false);
    final text = utf8.decode(decrypted);
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  /// 兼容 Map、普通 JSON 字符串和 HTML 转义后的 datajson 响应。
  static dynamic decryptServerResponse(dynamic responseData) {
    if (responseData == null) return null;

    if (responseData is Map) {
      final cipher = responseData['datajson'];
      return cipher == null ? responseData : decryptPayload(cipher.toString());
    }

    if (responseData is String) {
      var raw = responseData.trim();
      if (raw.startsWith('"') && raw.endsWith('"') && raw.length > 2) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is String) raw = decoded;
        } catch (_) {
          raw = raw.substring(1, raw.length - 1);
        }
      }

      raw = raw.replaceAll('&quot;', '"').replaceAll('&#34;', '"');
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decryptServerResponse(decoded);
      } catch (_) {}

      final match = RegExp(
        r'''datajson["']?\s*[:=]\s*["']?([A-Za-z0-9+/=]+)''',
      ).firstMatch(raw);
      final cipher = match?.group(1);
      if (cipher != null && cipher.isNotEmpty) return decryptPayload(cipher);
    }

    return responseData;
  }

  static Uint8List _crypt(
    Uint8List input,
    String key, {
    required bool encrypt,
  }) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
    cipher.init(
      encrypt,
      PaddedBlockCipherParameters<KeyParameter, Null>(
        KeyParameter(Uint8List.fromList(utf8.encode(key))),
        null,
      ),
    );
    return cipher.process(input);
  }
}
