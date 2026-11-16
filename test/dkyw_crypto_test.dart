import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/electricity_model.dart';
import 'package:smart_hunan_agri/utils/dkyw_crypto.dart';

void main() {
  group('DkywCrypto', () {
    test('与标准 AES-128-ECB/PKCS7 结果一致', () {
      final encrypted = DkywCrypto.encryptPayload(
        {'factorycode': 'E013'},
        key: '0123456789abcdef',
      );

      expect(
        encrypted,
        '9876543210fedcbaDxW8HcKcpdxG7Hd84F+lToJ4Iwyqaogt5lMYBYmbD+0=',
      );
    });

    test('可以解密服务端 Map 和 HTML 转义响应', () {
      final cipher = DkywCrypto.encryptPayload(
        {
          'success': true,
          'resultData': {'eledetail': '23.50'},
        },
        key: 'abcdefghijklmnop',
      );

      expect(
        DkywCrypto.decryptServerResponse({'datajson': cipher}),
        {
          'success': true,
          'resultData': {'eledetail': '23.50'},
        },
      );

      final escaped = jsonEncode(
        jsonEncode({'datajson': cipher}).replaceAll('"', '&quot;'),
      );
      expect(
        DkywCrypto.decryptServerResponse(escaped),
        {
          'success': true,
          'resultData': {'eledetail': '23.50'},
        },
      );
    });
  });

  test('ElectricityBalanceInfo 兼容新版余额字段', () {
    final info = ElectricityBalanceInfo.fromJson({
      'eledetail': '18.76',
      'accname': '东湖学生宿舍 101',
      'elestatus': '1',
    });

    expect(info.balance, '18.76');
    expect(info.accountName, '东湖学生宿舍 101');
    expect(info.status, 1);
  });
}
