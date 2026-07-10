import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_constants.dart';
import '../services/app_logger.dart';
import '../services/campus_card_service.dart';

class CampusCardPaymentSheet extends StatefulWidget {
  final String amount;
  final String merchantName;
  final CampusCardInfo info;

  const CampusCardPaymentSheet({
    super.key,
    required this.amount,
    required this.merchantName,
    required this.info,
  });

  @override
  State<CampusCardPaymentSheet> createState() => _CampusCardPaymentSheetState();
}

class _CampusCardPaymentSheetState extends State<CampusCardPaymentSheet> {
  final _logger = AppLogger.instance;
  bool _isConfirming = true;
  bool _isPaying = false;
  bool _isSuccess = false;
  String? _error;
  String? _htmlForm;

  Future<void> _launchExternal(Uri uri, String source) async {
    _logger.i('🚀 [校园卡支付] 外部拉起尝试($source): $uri');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) {
        _logger.i('✅ [校园卡支付] 外部拉起结果($source): $launched');
        return;
      }

      _logger.w('⚠️ [校园卡支付] 直接外拉返回 false($source): $uri');

      if (!kIsWeb) {
        final scheme = uri.scheme.toLowerCase();
        if (scheme == 'alipays' || scheme == 'alipay') {
          final intentUri = _buildAlipayIntentUri(uri);
          if (intentUri != null) {
            _logger.i('🧭 [校园卡支付] 尝试 intent 兜底($source): $intentUri');
            final intentLaunched = await launchUrl(intentUri, mode: LaunchMode.externalApplication);
            _logger.i('✅ [校园卡支付] intent 兜底结果($source): $intentLaunched');
            return;
          }
        }
      }
    } catch (e) {
      _logger.e('❌ [校园卡支付] 外部拉起失败($source): $e');
    }
  }

  Uri? _buildAlipayIntentUri(Uri uri) {
    if (uri.scheme.isEmpty || uri.host.isEmpty) return null;
    final intentString = 'intent://${uri.host}${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}#Intent;scheme=${uri.scheme};package=com.eg.android.AlipayGphone;end';
    return Uri.tryParse(intentString);
  }

  Future<void> _startPayment() async {
    _logger.i('🚀 [校园卡支付] 开始提交支付，amount=${widget.amount}, card=${widget.info.idserial}');
    setState(() {
      _isConfirming = false;
      _isPaying = true;
    });

    try {
      final service = CampusCardService.instance;
      _htmlForm = await service.getAlipayForm(double.parse(widget.amount));
      _logger.i('📄 [校园卡支付] 支付表单返回，length=${_htmlForm?.length ?? 0}, containsAlipayScheme=${_htmlForm?.contains('alipays://') == true || _htmlForm?.contains('alipay://') == true}');

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _logger.e('Failed to get alipay form: $e');
      if (mounted) {
        setState(() {
          _isPaying = false;
          _error = e.toString();
        });
      }
    }
  }

  void _handleSuccess() {
    if (_isSuccess) return;
    setState(() {
      _isSuccess = true;
      _isPaying = false;
    });
    CampusCardService.instance.fetchRechargeInfo();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const themeColor = Color(0xFF1677FF);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isSuccess
                    ? Icons.check_circle_outline
                    : (_isPaying ? Icons.hourglass_empty : Icons.payment_outlined),
                size: 20,
                color: _isSuccess ? primaryColor : themeColor,
              ),
              const SizedBox(width: 8),
              Text(
                _isSuccess ? '支付成功' : (_isPaying ? '正在支付...' : '支付确认'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _isSuccess ? primaryColor : themeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '¥${widget.amount}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.merchantName,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              '支付失败: $_error',
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ],
          const SizedBox(height: 32),
          if (_isPaying && !_isSuccess)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(color: themeColor),
                  const SizedBox(height: 16),
                  const Text('请在跳转后的支付宝中完成支付', style: TextStyle(fontSize: 14, color: Colors.black54)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_isConfirming)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                ),
              if (_isConfirming) const SizedBox(width: 16),
              if (_isConfirming)
                TextButton(
                  onPressed: _startPayment,
                  child: const Text('确认支付', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              if (_isSuccess || _error != null)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
            ],
          ),
          if (_htmlForm != null && !_isSuccess)
            SizedBox(
              width: 1,
              height: 1,
              child: Opacity(
                opacity: 0.01,
                child: InAppWebView(
                  initialData: InAppWebViewInitialData(data: _htmlForm!),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    useShouldOverrideUrlLoading: true,
                    supportMultipleWindows: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    userAgent: AppConstants.campusCardUA,
                  ),
                  onLoadStart: (controller, url) async {
                    final urlString = url?.toString() ?? '';
                    _logger.i('🌐 [校园卡支付] WebView loadStart: $urlString');
                    if (urlString.contains('paySuccess')) {
                      _handleSuccess();
                    }
                  },
                  onLoadStop: (controller, url) async {
                    final urlString = url?.toString() ?? '';
                    _logger.i('🏁 [校园卡支付] WebView loadStop: $urlString');
                    if (urlString.contains('paySuccess')) {
                      _handleSuccess();
                    }
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri = navigationAction.request.url;
                    final url = uri?.toString() ?? '';
                    _logger.i('🔀 [校园卡支付] shouldOverrideUrlLoading: $url');

                    if (uri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    final scheme = uri.scheme.toLowerCase();
                    if (scheme != 'http' && scheme != 'https') {
                      await _launchExternal(uri, 'shouldOverrideUrlLoading');
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: (controller, createWindowAction) async {
                    final uri = createWindowAction.request.url;
                    final url = uri?.toString() ?? '';
                    _logger.i('🪟 [校园卡支付] onCreateWindow: $url');
                    if (uri != null) {
                      final scheme = uri.scheme.toLowerCase();
                      if (scheme != 'http' && scheme != 'https') {
                        await _launchExternal(uri, 'onCreateWindow');
                        return false;
                      }
                      await controller.loadUrl(urlRequest: URLRequest(url: uri));
                    }
                    return false;
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
