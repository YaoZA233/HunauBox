import 'dart:typed_data';
import 'dart:convert';

import 'package:pointycastle/export.dart' as pc;

/// Converts an intranet URL to the university WebVPN proxy URL.
class WebVpnUrlConverter {
  WebVpnUrlConverter._();

  static const _keyAndIv = 'wwwvpnisthebest!';
  static const _vpnBaseUrl = 'https://webvpn.hunau.edu.cn';

  static String convert(String sourceUrl) {
    final uri = Uri.parse(sourceUrl);
    final protocol = uri.scheme.isEmpty ? 'http' : uri.scheme;
    final port = uri.hasPort ? '-${uri.port}' : '';
    final encryptedHost = _encryptHost(uri.host);
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';

    return '$_vpnBaseUrl/$protocol$port/$encryptedHost$path$query$fragment';
  }

  static String _encryptHost(String host) {
    final keyBytes = Uint8List.fromList(utf8.encode(_keyAndIv));
    final ivBytes = Uint8List.fromList(utf8.encode(_keyAndIv));
    var paddedHost = host;
    if (paddedHost.length % 16 != 0) {
      paddedHost += '0' * (16 - paddedHost.length % 16);
    }

    final plainBytes = Uint8List.fromList(utf8.encode(paddedHost));
    final cipher = pc.CFBBlockCipher(pc.AESEngine(), 16)
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(keyBytes), ivBytes));
    final encryptedBytes = Uint8List(plainBytes.length);

    for (var offset = 0; offset < plainBytes.length; offset += 16) {
      cipher.processBlock(plainBytes, offset, encryptedBytes, offset);
    }

    return '${_toHex(ivBytes)}${_toHex(encryptedBytes).substring(0, host.length * 2)}';
  }

  static String _toHex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
