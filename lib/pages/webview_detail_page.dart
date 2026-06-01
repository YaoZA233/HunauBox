import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_cookie_manager.dart';

class WebViewDetailPage extends StatefulWidget {
  final String title;
  final String url;
  final bool showAppBar;
  final bool showWebBack;
  final String? userAgent;
  final String? targetUrl;
  final Color? appBarColor;

  const WebViewDetailPage({
    super.key,
    required this.title,
    required this.url,
    this.showAppBar = true,
    this.showWebBack = false,
    this.userAgent,
    this.targetUrl,
    this.appBarColor,
  });

  @override
  State<WebViewDetailPage> createState() => _WebViewDetailPageState();
}

class _WebViewDetailPageState extends State<WebViewDetailPage> {
  static const int _loadTimeoutSeconds = 60;
  static const String _chaoxingUA =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36 (device:MEIZU 20) Language/zh_CN com.chaoxing.mobile.hunannongyedaxue/ChaoXingStudy_1000257_5.3_android_phone_53_234 (Kalimdor)';
  static const String _defaultUA =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36';

  InAppWebViewController? _webViewController;
  double _progress = 0;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _loadTimeoutTimer;
  late final Future<void> _cookieReady;

  @override
  void initState() {
    super.initState();
    _cookieReady = AppCookieManager().syncMultiDomainCookiesToWebView(widget.url);
    _startLoadTimeout();
  }

  @override
  void dispose() {
    _cancelLoadTimeout();
    _webViewController?.stopLoading();
    super.dispose();
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: _loadTimeoutSeconds), () {
      if (_isLoading && mounted) {
        setState(() {
          _errorMessage = '加载超时，可能是校内网络响应缓慢。';
          _isLoading = false;
        });
      }
    });
  }

  void _cancelLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  String _resolveUserAgent() {
    if (widget.userAgent != null && widget.userAgent!.isNotEmpty) {
      return widget.userAgent!;
    }
    final url = widget.url;
    if (url.contains('chaoxing.com') || url.contains('reserve.chaoxing.com')) {
      return _chaoxingUA;
    }
    return _defaultUA;
  }

  Future<bool> _launchExternalUrl(WebUri uri) async {
    final url = Uri.parse(uri.toString());
    if (!await canLaunchUrl(url)) {
      return false;
    }
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.appBarColor ?? Colors.white;
    final isDarkBackground = bgColor.computeLuminance() < 0.5;
    final iconColor = isDarkBackground ? Colors.white : Colors.black87;
    final dividerColor = isDarkBackground ? Colors.white24 : Colors.black12;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: bgColor,
              foregroundColor: iconColor,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              title: const Text(''),
              centerTitle: true,
              leadingWidth: widget.showWebBack ? 70 : 0,
              leading: widget.showWebBack
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Center(
                        child: Container(
                          height: 32,
                          width: 44,
                          decoration: BoxDecoration(
                            color: isDarkBackground
                                ? Colors.white.withOpacity(0.15)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: dividerColor, width: 0.5),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: iconColor,
                            ),
                            onPressed: () async {
                              if (_webViewController != null &&
                                  await _webViewController!.canGoBack()) {
                                _webViewController!.goBack();
                              } else {
                                if (context.mounted) Navigator.pop(context);
                              }
                            },
                          ),
                        ),
                      ),
                    )
                  : null,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDarkBackground
                          ? Colors.white.withOpacity(0.15)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: dividerColor, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _webViewController?.reload(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: iconColor,
                            ),
                          ),
                        ),
                        Container(width: 0.5, height: 16, color: dividerColor),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: iconColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          if (!widget.showAppBar)
            Container(
              height: MediaQuery.of(context).padding.top,
              color: bgColor,
            ),
          Expanded(
            child: Stack(
              children: [
                FutureBuilder<void>(
                  future: _cookieReady,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        UserScript(
                          source: """
                            (function() {
                              const url = window.location.href;
                              if (!url.includes('chaoxing.com') && !url.includes('hunau.edu.cn') && !url.includes('zhanyun.org')) {
                                return;
                              }
                              window.androidjsbridge = {
                                postNotification: function(name, userInfo) {
                                  try {
                                    window.flutter_inappwebview.callHandler('postNotification', {
                                      name: name,
                                      userInfo: JSON.parse(userInfo)
                                    });
                                  } catch (e) {}
                                }
                              };

                              var probeCount = 0;
                              var timer = setInterval(function() {
                                if (window.jsBridge && window.jsBridge.setDevice) {
                                  window.jsBridge.setDevice('android');
                                  clearInterval(timer);
                                }
                                if (++probeCount > 50) clearInterval(timer);
                              }, 100);
                            })();
                          """,
                          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                        UserScript(
                          source: """
                            (function() {
                              const url = window.location.href;
                              if (!url.includes('chaoxing.com') && !url.includes('hunau.edu.cn') && !url.includes('zhanyun.org')) {
                                return;
                              }
                              window.chaoxing = true;
                              window.is_chaoxing = true;

                              var mockBridge = {
                                version: '1.2.0',
                                onPushNotification: function(id) {},
                                callNative: function(method, args, callback) {
                                  window.flutter_inappwebview.callHandler(method, args).then(function(res) {
                                    if (callback) callback(res);
                                  });
                                },
                                cx_scan: function(args) {
                                  if (window.cx_scan) window.cx_scan(args);
                                }
                              };

                              window.CXJSBridge = mockBridge;
                            })();
                          """,
                          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        supportMultipleWindows: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        useShouldOverrideUrlLoading: true,
                        useHybridComposition: true,
                        supportZoom: true,
                        builtInZoomControls: true,
                        displayZoomControls: false,
                        loadWithOverviewMode: true,
                        useWideViewPort: true,
                        thirdPartyCookiesEnabled: true,
                        sharedCookiesEnabled: true,
                        userAgent: _resolveUserAgent(),
                        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                      ),
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                        controller.addJavaScriptHandler(
                          handlerName: 'postNotification',
                          callback: (args) async {
                            if (args.isEmpty) return null;
                            final data = args[0];
                            if (data is Map) {
                              final name = data['name']?.toString() ?? '';
                              final userInfo = data['userInfo'];
                              if (name == 'CLIENT_OPEN_URL' && userInfo is Map) {
                                final webUrl = userInfo['webUrl']?.toString();
                                if (webUrl != null && webUrl.isNotEmpty) {
                                  final cleanUrl = webUrl.replaceAll('#INNER', '');
                                  await controller.loadUrl(
                                    urlRequest: URLRequest(url: WebUri(cleanUrl)),
                                  );
                                }
                              }
                            }
                            return null;
                          },
                        );
                        controller.addJavaScriptHandler(
                          handlerName: 'cx_scan',
                          callback: (args) async {
                            return {'result': ''};
                          },
                        );
                      },
                      shouldOverrideUrlLoading: (controller, navigationAction) async {
                        final uri = navigationAction.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;
                        final scheme = uri.scheme;
                        if (scheme == 'jsbridge' || scheme == 'chaoxing') {
                          final urlString = uri.toString();
                          if (urlString.contains('postnotificationwithid-')) {
                            final parts = urlString.split('postnotificationwithid-');
                            if (parts.length > 1) {
                              final notificationId = parts[1];
                              final callbackIds = [
                                'postnotificationwithid-$notificationId',
                                'id-$notificationId',
                                notificationId,
                              ];
                              for (final cbId in callbackIds) {
                                final js = """
                                  if (window.CXJSBridge) {
                                    if (CXJSBridge.onPushNotification) CXJSBridge.onPushNotification('$cbId');
                                    if (CXJSBridge._onPushNotification) CXJSBridge._onPushNotification('$cbId');
                                    if (CXJSBridge.handleMessageFromNative) {
                                      try { CXJSBridge.handleMessageFromNative({notificationId: '$cbId', status: true}); } catch(e) {}
                                    }
                                  }
                                """;
                                await controller.evaluateJavascript(source: js);
                              }
                            }
                          }
                          return NavigationActionPolicy.CANCEL;
                        }
                        if (scheme != 'http' && scheme != 'https') {
                          await _launchExternalUrl(uri);
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (controller, createWindowAction) async {
                        final uri = createWindowAction.request.url;
                        if (uri != null) {
                          await controller.loadUrl(
                            urlRequest: URLRequest(url: uri),
                          );
                        }
                        return true;
                      },
                      onLoadStart: (controller, url) {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                          _progress = 0;
                        });
                        _startLoadTimeout();
                      },
                      onLoadStop: (controller, url) async {
                        _cancelLoadTimeout();
                        final urlString = url?.toString() ?? '';

                        if (urlString.contains('bxpt.hunau.edu.cn/relax') &&
                            !urlString.contains('/mobile/') &&
                            !urlString.contains('ticket=') &&
                            !urlString.contains('cas/login')) {
                          await controller.evaluateJavascript(
                            source: "window.location.href = '/relax/mobile/index.html';",
                          );
                          return;
                        }

                        if (widget.targetUrl != null) {
                          if (urlString.contains(widget.targetUrl!)) {
                            setState(() => _isLoading = false);
                          }
                        } else {
                          setState(() => _isLoading = false);
                        }
                      },
                      onProgressChanged: (controller, progress) {
                        setState(() => _progress = progress / 100);
                      },
                      onLoadHttpError: (controller, url, statusCode, description) {
                        if (url != null) {
                          setState(() {
                            _errorMessage = 'HTTP $statusCode: $description';
                            _isLoading = false;
                          });
                        }
                      },
                      onReceivedError: (controller, request, error) {
                        final url = request.url?.toString() ?? '';
                        if (url.startsWith('http')) {
                          setState(() {
                            _errorMessage = error.description;
                            _isLoading = false;
                          });
                        }
                      },
                      onPermissionRequest: (controller, request) async {
                        return PermissionResponse(
                          resources: request.resources,
                          action: PermissionResponseAction.GRANT,
                        );
                      },
                      onGeolocationPermissionsShowPrompt: (controller, origin) async {
                        return GeolocationPermissionShowPromptResponse(
                          origin: origin,
                          allow: true,
                          retain: true,
                        );
                      },
                    );
                  },
                ),
                if (_progress < 1)
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[200],
                  ),
                if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.black54),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                                _isLoading = true;
                              });
                              _webViewController?.reload();
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isLoading)
                  const Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Center(child: SizedBox.shrink()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
