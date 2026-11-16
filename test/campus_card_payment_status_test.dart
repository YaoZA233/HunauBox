import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/services/campus_card_service.dart';

void main() {
  group('CampusCardService.parseWeChatPayStatusResponse', () {
    test('paySuccess redirect is successful', () {
      final result = CampusCardService.parseWeChatPayStatusResponse(
        location: '/wxpay/paySuccess',
        realPath: '/wxpay/queryWxWapPayStatus',
        body: '',
      );

      expect(result.isSuccess, isTrue);
      expect(result.isPending, isFalse);
    });

    test('paySuccess real path is successful', () {
      final result = CampusCardService.parseWeChatPayStatusResponse(
        location: '',
        realPath: '/wxpay/paySuccess',
        body: '',
      );

      expect(result.isSuccess, isTrue);
      expect(result.isPending, isFalse);
    });

    test('querying message stays pending', () {
      final result = CampusCardService.parseWeChatPayStatusResponse(
        location: '',
        realPath: '/wxpay/queryWxWapPayStatus',
        body: '<p id="message">微信支付订单查询中</p>',
      );

      expect(result.isSuccess, isFalse);
      expect(result.isPending, isTrue);
    });

    test('wait icon stays pending', () {
      final result = CampusCardService.parseWeChatPayStatusResponse(
        location: '',
        realPath: '/wxpay/queryWxWapPayStatus',
        body: '<img src="/images/icon-wait.png">',
      );

      expect(result.isSuccess, isFalse);
      expect(result.isPending, isTrue);
    });

    test('explicit success page is successful', () {
      final result = CampusCardService.parseWeChatPayStatusResponse(
        location: '',
        realPath: '/wxpay/result',
        body: '<h1>充值成功</h1>',
      );

      expect(result.isSuccess, isTrue);
      expect(result.isPending, isFalse);
    });

    test('failure reason is returned', () {
      final result = CampusCardService.parseWeChatPayStatusResponse(
        location: '',
        realPath: '/wxpay/result',
        body: '<p>失败原因</p><p id="message">订单已关闭</p>',
      );

      expect(result.isSuccess, isFalse);
      expect(result.isPending, isFalse);
      expect(result.message, '订单已关闭');
    });

    test('unknown response defaults to pending', () {
      final result = CampusCardService.parseWeChatPayStatusResponse(
        location: '',
        realPath: '/wxpay/queryWxWapPayStatus',
        body: '<html></html>',
      );

      expect(result.isSuccess, isFalse);
      expect(result.isPending, isTrue);
    });
  });
}
