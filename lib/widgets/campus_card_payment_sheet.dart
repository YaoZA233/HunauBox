import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_constants.dart';
import '../services/app_logger.dart';
import '../services/campus_card_service.dart';

const String kAlipaySvg =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M21.422 15.358c-3.83-1.153-6.055-1.84-6.678-2.062a12.41 12.41 0 0 0 1.32-3.32H12.8V8.872h4v-.68h-4V6.344h-1.536c-.28 0-.312.248-.312.248v1.592H7.2v.68h3.752v1.104H7.88v.616h6.224a10.972 10.972 0 0 1-.888 2.176c-1.408-.464-2.192-.784-3.912-.944-3.256-.312-4.008 1.48-4.128 2.576C5 16.064 6.48 17.424 8.688 17.424s3.68-1.024 5.08-2.72c1.167.558 3.338 1.525 6.514 2.902A9.99 9.99 0 0 1 12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10a9.983 9.983 0 0 1-.578 3.358zm-12.99 1.01c-2.336 0-2.704-1.48-2.584-2.096.12-.616.8-1.416 2.104-1.416 1.496 0 2.832.384 4.44 1.16-1.136 1.48-2.52 2.352-3.96 2.352z"/></svg>''';
const String kWechatSvg =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M8.691 2.188C3.891 2.188 0 5.478 0 9.53c0 2.212 1.17 4.203 3.002 5.55l-.39 1.48c-.07.29.24.52.49.36l2.035-1.114a10.16 10.16 0 0 0 4.265.255c-.858-2.525.405-5.32 2.964-6.494 1.706-.782 3.65-.77 5.342-.036C16.89 5.568 13.143 2.188 8.691 2.188zm-2.42 4.095a1.048 1.048 0 1 1 0 2.096 1.048 1.048 0 0 1 0-2.096zm5.234 0a1.048 1.048 0 1 1 0 2.096 1.048 1.048 0 0 1 0-2.096zm3.834 4.544c-3.993 0-7.23 2.742-7.23 6.124 0 1.843.975 3.502 2.502 4.625l-.325 1.233c-.058.24.2.43.41.3l1.735-.985c.74.202 1.52.312 2.321.312 3.993 0 7.23-2.742 7.23-6.124 0-3.382-3.237-6.124-7.23-6.124zm-2.016 3.41a.873.873 0 1 1 0 1.746.873.873 0 0 1 0-1.746zm4.362 0a.873.873 0 1 1 0 1.746.873.873 0 0 1 0-1.746z"/></svg>''';

class CampusCardPaymentSheet extends StatefulWidget {
  const CampusCardPaymentSheet({
    super.key,
    required this.amount,
    required this.merchantName,
    required this.info,
    this.paymentMethod = PaymentMethod.alipay,
    this.successTitle,
    this.onCardRechargeSuccess,
  });

  final String amount;
  final String merchantName;
  final CampusCardInfo info;
  final PaymentMethod paymentMethod;
  final String? successTitle;
  final Future<void> Function()? onCardRechargeSuccess;

  @override
  State<CampusCardPaymentSheet> createState() => _CampusCardPaymentSheetState();
}

class _CampusCardPaymentSheetState extends State<CampusCardPaymentSheet>
    with WidgetsBindingObserver {
  final _logger = AppLogger.instance;

  bool _isConfirming = true;
  bool _isPaying = false;
  bool _isSuccess = false;
  bool _isCheckingResult = false;
  bool _isExecutingSecondary = false;
  bool _statusCheckInFlight = false;
  bool _primaryPaymentConfirmed = false;
  bool _needsWeChatWebViewFallback = false;
  String? _error;
  String? _secondaryError;
  String? _htmlForm;
  WeChatRechargeOrder? _weChatOrder;
  Timer? _pollingTimer;

  bool get _isWeChat => widget.paymentMethod == PaymentMethod.wechat;
  Color get _themeColor =>
      _isWeChat ? const Color(0xFF07C160) : const Color(0xFF1677FF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_isPaying ||
        _isSuccess ||
        _isExecutingSecondary) {
      return;
    }
    if (_isWeChat) {
      _checkWeChatStatus(isManual: false);
    } else {
      _checkAlipayStatus(isManual: false);
    }
  }

  Future<void> _startPayment() async {
    if (_isPaying || _primaryPaymentConfirmed || _isExecutingSecondary) return;
    setState(() {
      _isConfirming = false;
      _isPaying = true;
      _error = null;
    });

    try {
      final service = CampusCardService.instance;
      final amount = double.parse(widget.amount);
      if (_isWeChat) {
        final order = await service.createWeChatOrder(amount);
        if (!mounted) return;
        _weChatOrder = order;
        final deepLink = await service.getWeChatDeepLink(order.mwebUrl);
        if (!mounted) return;
        final launched = deepLink != null
            ? await _launchExternal(Uri.parse(deepLink), '微信 H5 支付')
            : false;
        _needsWeChatWebViewFallback = !launched;
        _startPollingWeChatStatus();
      } else {
        _htmlForm = await service.getAlipayForm(amount);
      }
      if (mounted) setState(() {});
    } catch (e) {
      _logger.e('创建支付订单失败: $e');
      if (mounted) {
        setState(() {
          _isPaying = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _startPollingWeChatStatus() {
    _pollingTimer?.cancel();
    var pollCount = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      pollCount++;
      if (pollCount > 25 || _primaryPaymentConfirmed || !mounted) {
        timer.cancel();
        return;
      }
      _checkWeChatStatus(isManual: false);
    });
  }

  Future<void> _checkWeChatStatus({bool isManual = true}) async {
    final order = _weChatOrder;
    if (order == null ||
        _primaryPaymentConfirmed ||
        _isExecutingSecondary ||
        _statusCheckInFlight) {
      return;
    }
    _statusCheckInFlight = true;
    if (isManual && mounted) setState(() => _isCheckingResult = true);
    try {
      final service = CampusCardService.instance;
      final result = await service.queryWeChatPayStatus(
        partnerjourno: order.partnerjourno,
        returnurl: order.returnurl,
      );
      if (result.isSuccess) {
        await _handlePrimaryPaymentSuccess();
        return;
      }

      if (result.isPending && isManual) {
        if (await _cardBalanceIncreased()) {
          await _handlePrimaryPaymentSuccess();
          return;
        }
        _showMessage('微信支付仍在处理中，请稍后再确认');
      } else if (!result.isPending && isManual) {
        _showMessage(result.message ?? '微信支付未成功');
      }
    } catch (e) {
      _logger.w('查询微信支付结果失败: $e');
      if (isManual) _showMessage('暂时无法查询支付结果，请稍后重试');
    } finally {
      _statusCheckInFlight = false;
      if (isManual && mounted) setState(() => _isCheckingResult = false);
    }
  }

  Future<void> _checkAlipayStatus({bool isManual = true}) async {
    if (_primaryPaymentConfirmed ||
        _isExecutingSecondary ||
        _statusCheckInFlight) {
      return;
    }
    _statusCheckInFlight = true;
    if (isManual && mounted) setState(() => _isCheckingResult = true);
    try {
      if (await _cardBalanceIncreased()) {
        await _handlePrimaryPaymentSuccess();
      } else if (isManual) {
        _showMessage('暂未检测到支付宝充值到账，请稍后再确认');
      }
    } catch (e) {
      _logger.w('查询支付宝支付结果失败: $e');
      if (isManual) _showMessage('暂时无法查询支付结果，请稍后重试');
    } finally {
      _statusCheckInFlight = false;
      if (isManual && mounted) setState(() => _isCheckingResult = false);
    }
  }

  Future<bool> _cardBalanceIncreased() async {
    final oldBalance = double.tryParse(widget.info.balance);
    if (oldBalance == null) return false;
    final info = await CampusCardService.instance.fetchRechargeInfo();
    final newBalance = double.tryParse(info.balance);
    return newBalance != null && newBalance > oldBalance;
  }

  Future<void> _handlePrimaryPaymentSuccess() async {
    if (_primaryPaymentConfirmed) return;
    _primaryPaymentConfirmed = true;
    _pollingTimer?.cancel();
    await _finishOrRunSecondary();
  }

  Future<void> _finishOrRunSecondary() async {
    final secondary = widget.onCardRechargeSuccess;
    if (secondary == null) {
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _isPaying = false;
        });
      }
      CampusCardService.instance.fetchRechargeInfo();
      return;
    }

    if (mounted) {
      setState(() {
        _isPaying = false;
        _isExecutingSecondary = true;
        _secondaryError = null;
      });
    }
    try {
      await secondary();
      if (mounted) {
        setState(() {
          _isExecutingSecondary = false;
          _isSuccess = true;
        });
      }
      CampusCardService.instance.fetchRechargeInfo();
    } catch (e) {
      _logger.e('校园卡到账后的电费充值失败: $e');
      if (mounted) {
        setState(() {
          _isExecutingSecondary = false;
          _secondaryError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<bool> _launchExternal(Uri uri, String source) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
      if (!kIsWeb &&
          (uri.scheme.toLowerCase() == 'alipay' ||
              uri.scheme.toLowerCase() == 'alipays')) {
        final intent = Uri.tryParse(
          'intent://${uri.host}${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'
          '#Intent;scheme=${uri.scheme};package=com.eg.android.AlipayGphone;end',
        );
        if (intent != null) {
          return launchUrl(intent, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      _logger.w('$source 无法直接拉起，将使用网页兜底: $e');
    }
    return false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = _secondaryError != null
        ? '校园卡已到账，电费充值失败'
        : _isSuccess
        ? (widget.successTitle ?? '支付成功')
        : _isExecutingSecondary
        ? '正在充值电费…'
        : _isPaying
        ? '等待支付结果'
        : '${_isWeChat ? '微信' : '支付宝'}支付确认';

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isSuccess
                      ? Icons.check_circle_outline
                      : _secondaryError != null
                      ? Icons.warning_amber_rounded
                      : _isExecutingSecondary
                      ? Icons.sync_rounded
                      : Icons.payment_outlined,
                  color: _secondaryError != null ? Colors.orange : _themeColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '¥${widget.amount}',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.merchantName} · ${widget.info.name}',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                '支付失败：$_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (_secondaryError != null) ...[
              const SizedBox(height: 16),
              Text(
                '第三方充值已进入校园卡，但自动缴电费失败：$_secondaryError\n可直接重试缴费，不会再次发起微信或支付宝充值。',
                style: TextStyle(color: theme.colorScheme.error, height: 1.45),
              ),
            ],
            if ((_isPaying || _isExecutingSecondary) && !_isSuccess) ...[
              const SizedBox(height: 26),
              Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: _themeColor),
                    const SizedBox(height: 14),
                    Text(
                      _isExecutingSecondary
                          ? '校园卡已到账，正在缴纳电费，请勿关闭'
                          : '请在${_isWeChat ? '微信' : '支付宝'}中完成支付',
                      textAlign: TextAlign.center,
                    ),
                    if (_isPaying && !_isExecutingSecondary) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isCheckingResult
                            ? null
                            : () => _isWeChat
                                  ? _checkWeChatStatus()
                                  : _checkAlipayStatus(),
                        icon: _isCheckingResult
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(_isCheckingResult ? '正在确认' : '我已完成支付'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isConfirming)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                if (_isConfirming)
                  FilledButton(
                    onPressed: _startPayment,
                    style: FilledButton.styleFrom(backgroundColor: _themeColor),
                    child: const Text('确认支付'),
                  ),
                if (_secondaryError != null) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('稍后处理'),
                  ),
                  FilledButton(
                    onPressed: _finishOrRunSecondary,
                    child: const Text('重试缴电费'),
                  ),
                ] else if (_isSuccess || _error != null)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _isSuccess),
                    child: const Text('完成'),
                  ),
              ],
            ),
            if (!_isSuccess &&
                (_htmlForm != null || _needsWeChatWebViewFallback))
              SizedBox(
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0.01,
                  child: InAppWebView(
                    initialData: _htmlForm == null
                        ? null
                        : InAppWebViewInitialData(data: _htmlForm!),
                    initialUrlRequest:
                        _htmlForm == null &&
                            _needsWeChatWebViewFallback &&
                            _weChatOrder != null
                        ? URLRequest(
                            url: WebUri(_weChatOrder!.mwebUrl),
                            headers: {
                              'Referer': 'https://fin-serv.hunau.edu.cn/',
                            },
                          )
                        : null,
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      supportMultipleWindows: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      userAgent: AppConstants.campusCardUA,
                    ),
                    onLoadStart: (controller, url) => _handlePaymentUrl(url),
                    onLoadStop: (controller, url) => _handlePaymentUrl(url),
                    shouldOverrideUrlLoading: (controller, action) async {
                      final uri = action.request.url;
                      if (uri == null) return NavigationActionPolicy.ALLOW;
                      if (uri.path.contains('paySuccess')) {
                        await _handlePrimaryPaymentSuccess();
                        return NavigationActionPolicy.CANCEL;
                      }
                      if (uri.scheme != 'http' && uri.scheme != 'https') {
                        await _launchExternal(uri, '支付网页');
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                    onCreateWindow: (controller, action) async {
                      final uri = action.request.url;
                      if (uri == null) return false;
                      if (uri.scheme != 'http' && uri.scheme != 'https') {
                        await _launchExternal(uri, '支付弹窗');
                      } else {
                        await controller.loadUrl(
                          urlRequest: URLRequest(url: uri),
                        );
                      }
                      return false;
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePaymentUrl(WebUri? url) async {
    if (url?.path.contains('paySuccess') == true) {
      await _handlePrimaryPaymentSuccess();
    }
  }
}
