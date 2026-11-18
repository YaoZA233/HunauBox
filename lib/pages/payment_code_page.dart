import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_logger.dart';
import '../services/campus_card_service.dart';
import '../widgets/payment_result_sheet.dart';
import '../widgets/campus_loading_mark.dart';
import '../widgets/campus_progress_bar.dart';
import 'campus_card_recharge_page.dart';
import 'campus_card_bill_page.dart';

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
    final qrSize = (MediaQuery.sizeOf(context).width - 72)
        .clamp(220.0, 300.0)
        .toDouble();
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
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.credit_card_outlined, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '湖南农业大学校园卡',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '付款码',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新付款码',
                    onPressed: _isLoading || _isRefreshing
                        ? null
                        : () => _loadPaymentCode(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Center(
                child: Container(
                  width: qrSize,
                  height: qrSize,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isLoading && _qrBytes == null
                        ? CampusLoadingMark(size: 32, color: colors.primary)
                        : _error != null && _qrBytes == null
                        ? Icon(Icons.qr_code_2, color: colors.error, size: 54)
                        : _qrBytes == null
                        ? const SizedBox.shrink()
                        : Image.memory(
                            _qrBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            semanticLabel: '校园卡动态付款二维码',
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _error != null && _qrBytes == null
                    ? _error!
                    : '请将二维码对准扫码设备',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _error != null && _qrBytes == null
                      ? colors.error
                      : colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isRefreshing
                    ? '正在更新付款码…'
                    : '$_refreshCountdown 秒后自动更新',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: CampusProgressBar(
                  value: _refreshCountdown / 60,
                  minHeight: 3,
                  backgroundColor: colors.surfaceContainerHighest,
                  semanticsLabel: '付款码刷新倒计时',
                ),
              ),
              if (_error != null && _qrBytes == null) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                  onPressed: () => _loadPaymentCode(),
                  icon: const Icon(Icons.refresh),
                    label: const Text('重新获取'),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Divider(height: 1, color: colors.outlineVariant),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '校园卡余额',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '¥ ${_balanceText()}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => const CampusCardRechargePage(),
                              ),
                            )
                            .then((_) => _loadPaymentCode());
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('充值'),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('校园卡账单'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CampusCardBillPage()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
