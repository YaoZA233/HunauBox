import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_logger.dart';
import '../services/campus_card_service.dart';
import '../widgets/payment_result_sheet.dart';
import 'campus_card_recharge_page.dart';

/// 校园卡付款码。
///
/// 付款码由校园卡服务端生成，二维码和 paycode 必须定期刷新；页面进入
/// 后每 60 秒刷新一次，并在前台每 3 秒查询一次支付状态。
class PaymentCodePage extends StatefulWidget {
  const PaymentCodePage({super.key});

  @override
  State<PaymentCodePage> createState() => _PaymentCodePageState();
}

class _PaymentCodePageState extends State<PaymentCodePage>
    with WidgetsBindingObserver {
  final _logger = AppLogger.instance;
  final _service = CampusCardService.instance;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isPolling = false;
  String? _error;
  String? _paycode;
  String? _userInfo;
  Uint8List? _qrBytes;
  int _refreshCountdown = 60;
  Timer? _refreshTimer;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPaymentCode();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPaymentCode();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _statusTimer?.cancel();
    }
  }

  Future<void> _loadPaymentCode({bool isSilent = false}) async {
    if (!mounted || _isRefreshing) return;
    _isRefreshing = true;
    if (_qrBytes == null || !isSilent) {
      setState(() {
        if (_qrBytes == null) _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await _service.fetchPaymentCode();
      final encoded = data['qrBase64']?.toString();
      final bytes = encoded == null ? null : base64Decode(encoded);
      if (bytes == null || data['paycode'] == null) {
        throw Exception('解析付款码页面失败');
      }

      if (!mounted) return;
      setState(() {
        _qrBytes = bytes;
        _paycode = data['paycode']?.toString();
        _userInfo = data['info']?.toString();
        _isLoading = false;
        _error = null;
        _refreshCountdown = 60;
      });
      _startTimers();
    } catch (e) {
      _logger.e('加载校园卡付款码失败: $e');
      if (!mounted) return;
      setState(() {
        if (_qrBytes == null || !isSilent) _isLoading = false;
        if (_qrBytes == null || !isSilent) _error = e.toString();
      });
    } finally {
      _isRefreshing = false;
    }
  }

  void _startTimers() {
    _refreshTimer?.cancel();
    _statusTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_refreshCountdown <= 1) {
        _loadPaymentCode(isSilent: true);
      } else {
        setState(() => _refreshCountdown--);
      }
    });
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _queryStatus();
    });
  }

  Future<void> _queryStatus() async {
    final paycode = _paycode;
    if (paycode == null || _isPolling || !mounted) return;
    _isPolling = true;
    try {
      final result = await _service.queryOrderStatus(paycode);
      if (!mounted ||
          result['success'] != true ||
          result['resultData'] is! Map) {
        return;
      }
      final data = Map<String, dynamic>.from(result['resultData'] as Map);
      final status = data['status']?.toString();
      if (status == '1') {
        _showResult(
          PaymentResultType.success,
          amount: _formatAmount(data['txamt']),
          message: data['message']?.toString(),
        );
      } else if (const {'2', '4', '6', '7'}.contains(status)) {
        _showResult(
          PaymentResultType.failure,
          message: data['message']?.toString() ?? '支付失败',
        );
      }
    } catch (e) {
      _logger.w('查询付款码状态失败: $e');
    } finally {
      _isPolling = false;
    }
  }

  String? _formatAmount(dynamic value) {
    final cents = double.tryParse(value?.toString() ?? '');
    return cents == null ? null : (cents / 100).toStringAsFixed(2);
  }

  void _showResult(PaymentResultType type, {String? amount, String? message}) {
    _refreshTimer?.cancel();
    _statusTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PaymentResultSheet(
        type: type,
        merchantName: '校园卡付款',
        amount: amount,
        message: message,
      ),
    ).then((_) {
      if (mounted) _loadPaymentCode();
    });
  }

  String _balanceText() {
    final info = _service.cachedInfo;
    if (info != null && info.balance.isNotEmpty) return info.balance;
    final text = _userInfo;
    if (text == null) return '0.00';
    final match = RegExp(r'余额\s*[：:]\s*([0-9.]+)').firstMatch(text);
    return match?.group(1) ?? '0.00';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园卡付款码'),
        actions: [
          IconButton(
            tooltip: '刷新付款码',
            onPressed: _isLoading || _isRefreshing
                ? null
                : () => _loadPaymentCode(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1677FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.credit_card, color: Colors.white),
                        const SizedBox(width: 10),
                        const Text(
                          '湖南农业大学校园卡',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$_refreshCountdown 秒后刷新',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: 220,
                      height: 220,
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: GestureDetector(
                        onTap: _isLoading ? null : () => _loadPaymentCode(),
                        child: Center(
                          child: _isLoading && _qrBytes == null
                              ? const CircularProgressIndicator(
                                  color: Color(0xFF1677FF),
                                )
                              : _error != null && _qrBytes == null
                              ? const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 48,
                                )
                              : _qrBytes == null
                              ? const SizedBox.shrink()
                              : Image.memory(_qrBytes!, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '请将二维码对准扫码设备',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (_error != null && _qrBytes == null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _loadPaymentCode(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新获取'),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '校园卡余额 ￥${_balanceText()}',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => const CampusCardRechargePage(),
                              ),
                            )
                            .then((_) => _loadPaymentCode());
                      },
                      child: const Text('充值'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '付款码有效期较短，付款前请确认页面已完成刷新。',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
