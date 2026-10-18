import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/app_constants.dart';
import '../services/xgxt_login_service.dart';
import '../services/app_cookie_manager.dart';
import '../widgets/login_bottom_sheet.dart';

class XgxtWebViewPage extends StatefulWidget {
  const XgxtWebViewPage({super.key, this.loginService});
  final XgxtLoginService? loginService;

  @override
  State<XgxtWebViewPage> createState() => _XgxtWebViewPageState();
}

class _XgxtWebViewPageState extends State<XgxtWebViewPage> {
  double _progress = 0;
  bool _isPreparing = true;
  bool _loginRequired = false;
  bool _sessionUnavailable = false;
  bool _mainFrameFailed = false;
  String? _errorMessage;
  int _webViewKey = 0;
  late String _initialUrl;
  InAppWebViewController? _webViewController;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  Timer? _loadTimeoutTimer;
  Timer? _retryTimer;
  Future<void>? _preparation;
  int _preparationVersion = 0;
  late final _loginService = widget.loginService ?? XgxtLoginService();
  bool _completingBrowserLogin = false;
  bool _normalizedBrowserLanding = false;
  bool _browserRecoveryAttempted = false;
  static const int _loadTimeoutSeconds = 60;

  @override
  void initState() {
    super.initState();
    _initialUrl = AppConstants.xgxtWapUrl;
    _prepareSession();
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(Duration(seconds: _loadTimeoutSeconds), () {
      if (mounted && (_isPreparing || _progress < 1)) {
        setState(() {
          if (_isPreparing) {
            _preparationVersion++;
            _preparation = null;
            _sessionUnavailable = true;
            _loginRequired = false;
          }
          _errorMessage = '加载超时，可能是校内网络响应缓慢，请重试';
          _isPreparing = false;
        });
      }
    });
  }

  void _cancelLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  @override
  void dispose() {
    _cancelLoadTimeout();
    _retryTimer?.cancel();
    _preparationVersion++;
    _webViewController = null;
    super.dispose();
  }

  Future<void> _prepareSession() {
    if (_preparation != null) return _preparation!;
    final attempt = _prepareVerifiedSession();
    _preparation = attempt;
    return attempt.whenComplete(() {
      if (identical(_preparation, attempt)) _preparation = null;
    });
  }

  Future<void> _prepareVerifiedSession() async {
    if (!mounted) return;
    _cancelLoadTimeout();
    _retryTimer?.cancel();
    final version = ++_preparationVersion;
    _webViewController = null;
    setState(() {
      _isPreparing = true;
      _loginRequired = false;
      _sessionUnavailable = false;
      _mainFrameFailed = false;
      _errorMessage = null;
      _progress = 0;
      _retryCount = 0;
    });
    _startLoadTimeout();
    try {
      final valid = await _loginService.ensureSession();
      if (!mounted || version != _preparationVersion) return;
      _cancelLoadTimeout();
      if (!valid) {
        setState(() {
          _isPreparing = false;
          _loginRequired = true;
          _sessionUnavailable = true;
          _errorMessage = '学工登录未完成，请重新登录后重试';
        });
        return;
      }
      _initialUrl = AppConstants.xgxtWapUrl;
      _normalizedBrowserLanding = false;
      _webViewController = null;
      setState(() {
        _isPreparing = false;
        _loginRequired = false;
        _webViewKey++;
      });
    } catch (e) {
      if (mounted && version == _preparationVersion) {
        _cancelLoadTimeout();
        setState(() {
          _isPreparing = false;
          _sessionUnavailable = true;
          _loginRequired = false;
          _errorMessage = e is XgxtSessionException
              ? e.message
              : '学工会话准备失败，请稍后重试';
        });
      }
    }
  }

  Future<void> _openLoginSheet() async {
    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => const LoginBottomSheet(),
    );

    if (result != null && mounted) {
      _browserRecoveryAttempted = false;
      await _prepareSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: _isPreparing
          ? Stack(
              children: [
                const Center(child: CircularProgressIndicator()),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 16,
                  child: _buildFloatingButtons(),
                ),
              ],
            )
          : _sessionUnavailable
          ? Stack(
              children: [
                _buildLoginRequired(),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 16,
                  child: _buildFloatingButtons(),
                ),
              ],
            )
          : Stack(
              children: [
                Column(
                  children: [
                    Container(
                      height: MediaQuery.of(context).padding.top,
                      color: accent,
                    ),
                    if (_progress < 1)
                      LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    Expanded(
                      child: InAppWebView(
                        key: ValueKey('xgxt-webview-$_webViewKey'),
                        initialUserScripts: UnmodifiableListView([
                          UserScript(
                            source: """
                              try {
                                if (localStorage.getItem('token') === 'flutter_xgxt') localStorage.removeItem('token');
                                if (sessionStorage.getItem('token') === 'flutter_xgxt') sessionStorage.removeItem('token');
                              } catch (e) {}
                            """,
                            injectionTime:
                                UserScriptInjectionTime.AT_DOCUMENT_START,
                          ),
                        ]),
                        initialSettings: InAppWebViewSettings(
                          mixedContentMode:
                              MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                          javaScriptEnabled: true,
                          domStorageEnabled: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          mediaPlaybackRequiresUserGesture: false,
                          allowsInlineMediaPlayback: true,
                          useShouldOverrideUrlLoading: true,
                          supportZoom: true,
                          builtInZoomControls: true,
                          displayZoomControls: false,
                          loadWithOverviewMode: true,
                          useWideViewPort: true,
                          thirdPartyCookiesEnabled: true,
                          sharedCookiesEnabled: true,
                          allowFileAccess: true,
                          allowContentAccess: true,
                          allowFileAccessFromFileURLs: true,
                          allowUniversalAccessFromFileURLs: true,
                          userAgent:
                              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36',
                          cacheMode: CacheMode.LOAD_DEFAULT,
                        ),
                        shouldOverrideUrlLoading:
                            (controller, navigationAction) async {
                              final uri = navigationAction.request.url;
                              if (uri == null) {
                                return NavigationActionPolicy.ALLOW;
                              }
                              final urlString = uri.toString();
                              final scheme = uri.scheme;
                              if (scheme != 'http' && scheme != 'https') {
                                return NavigationActionPolicy.CANCEL;
                              }
                              final whiteList = [
                                'hunau.edu.cn',
                                'chaoxing.com',
                                'authorize',
                                'login',
                              ];
                              final isAllowed = whiteList.any(
                                (d) => urlString.contains(d),
                              );
                              if (!isAllowed) {
                                return NavigationActionPolicy.CANCEL;
                              }
                              return NavigationActionPolicy.ALLOW;
                            },
                        onWebViewCreated: (controller) async {
                          if (!mounted) return;
                          _webViewController = controller;
                          // ensureSession already awaited publication. Clearing
                          // cookies again here races with the live browser.
                          if (_initialUrl.isNotEmpty) {
                            _startLoadTimeout();
                            try {
                              await controller.loadUrl(
                                urlRequest: URLRequest(
                                  url: WebUri(_initialUrl),
                                ),
                              );
                            } catch (_) {
                              if (mounted && controller == _webViewController) {
                                _cancelLoadTimeout();
                                _handleLoadError('页面启动失败');
                              }
                            }
                          }
                        },
                        onLoadStart: (controller, url) {
                          if (!mounted || controller != _webViewController) {
                            return;
                          }
                          _mainFrameFailed = false;
                          _startLoadTimeout();
                          setState(() {
                            _isPreparing = false;
                            _errorMessage = null;
                            _progress = 0;
                          });
                        },
                        onLoadStop: (controller, url) async {
                          if (!mounted || controller != _webViewController) {
                            return;
                          }
                          if (_mainFrameFailed) return;
                          _cancelLoadTimeout();
                          final uri = url == null
                              ? null
                              : Uri.tryParse(url.toString());
                          if (uri?.host ==
                                  Uri.parse(AppConstants.ssoBaseUrl).host &&
                              uri!.path.startsWith('/cas/login')) {
                            await _recoverBrowserSession();
                            return;
                          }
                          if (uri?.host ==
                                  Uri.parse(AppConstants.xgxtBaseUrl).host &&
                              !_completingBrowserLogin) {
                            _completingBrowserLogin = true;
                            try {
                              await AppCookieManager()
                                  .syncMultiDomainCookiesFromWebView(
                                    url.toString(),
                                  );
                              if (!_normalizedBrowserLanding &&
                                  (uri!.path.split(';').first == '/cas' ||
                                      uri.queryParameters.containsKey(
                                        'ticket',
                                      ))) {
                                final valid = await _loginService
                                    .hasValidSession();
                                if (valid &&
                                    mounted &&
                                    controller == _webViewController) {
                                  _normalizedBrowserLanding = true;
                                  await controller.loadUrl(
                                    urlRequest: URLRequest(
                                      url: WebUri(AppConstants.xgxtWapUrl),
                                    ),
                                  );
                                  return;
                                }
                                if (!valid) {
                                  await _recoverBrowserSession();
                                  return;
                                }
                              }
                            } catch (_) {
                              if (mounted && controller == _webViewController) {
                                setState(() => _errorMessage = '学工会话同步失败，请重试');
                              }
                              return;
                            } finally {
                              _completingBrowserLogin = false;
                            }
                          }
                          if (!mounted || controller != _webViewController) {
                            return;
                          }
                          setState(() {
                            _errorMessage = null;
                            _progress = 1;
                            _retryCount = 0;
                          });
                        },
                        onProgressChanged: (controller, progress) {
                          if (!mounted || controller != _webViewController) {
                            return;
                          }
                          setState(() {
                            _progress = progress / 100.0;
                          });
                        },
                        onReceivedError: (controller, request, error) {
                          if (!mounted ||
                              controller != _webViewController ||
                              request.isForMainFrame != true) {
                            return;
                          }
                          _cancelLoadTimeout();
                          _mainFrameFailed = true;
                          _handleLoadError('加载失败: ${error.description}');
                        },
                        onReceivedHttpError: (controller, request, response) {
                          if (!mounted ||
                              controller != _webViewController ||
                              request.isForMainFrame != true) {
                            return;
                          }
                          _cancelLoadTimeout();
                          _mainFrameFailed = true;
                          _handleHttpError(
                            response.statusCode,
                            response.reasonPhrase,
                          );
                        },
                        onPermissionRequest: (controller, request) async {
                          return PermissionResponse(
                            resources: request.resources,
                            action: PermissionResponseAction.GRANT,
                          );
                        },
                        onCreateWindow: (controller, createWindowAction) async {
                          if (createWindowAction.request.url != null) {
                            await controller.loadUrl(
                              urlRequest: createWindowAction.request,
                            );
                          }
                          return true;
                        },
                        onJsPrompt: (controller, jsPromptRequest) async {
                          return JsPromptResponse(handledByClient: false);
                        },
                        onConsoleMessage: (controller, consoleMessage) {
                          // 调试用，生产环境可移除
                        },
                        onReceivedHttpAuthRequest: (controller, request) async {
                          return HttpAuthResponse(
                            username: '',
                            password: '',
                            action: HttpAuthResponseAction.PROCEED,
                          );
                        },
                        onReceivedServerTrustAuthRequest:
                            (controller, challenge) async {
                              return ServerTrustAuthResponse(
                                action: ServerTrustAuthResponseAction.PROCEED,
                              );
                            },
                      ),
                    ),
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: const Color(0xFFFFF4F4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFC62828),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFC62828),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _prepareSession,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 16,
                  child: _buildFloatingButtons(),
                ),
              ],
            ),
    );
  }

  Widget _buildFloatingButtons() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleRefresh,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.refresh_rounded, size: 20, color: Colors.white),
            ),
          ),
          Container(width: 0.5, height: 20, color: Colors.white38),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.close_rounded, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// 处理加载错误，实现自动重试机制
  void _handleLoadError(String message) {
    if (!mounted) return;
    _mainFrameFailed = true;

    if (_retryCount < _maxRetries) {
      _retryCount++;
      setState(() {
        _errorMessage = '加载失败($message)，正在重试... ($_retryCount/$_maxRetries)';
      });

      // 延迟重试，避免频繁请求
      _retryTimer?.cancel();
      final failedController = _webViewController;
      _retryTimer = Timer(const Duration(seconds: 2), () async {
        if (mounted &&
            failedController != null &&
            failedController == _webViewController) {
          try {
            await failedController.reload();
          } catch (_) {
            if (mounted && failedController == _webViewController) {
              _handleLoadError('页面重试失败');
            }
          }
        }
      });
    } else {
      setState(() {
        _errorMessage = '加载失败，请检查网络连接后重试';
      });
    }
  }

  /// 处理HTTP错误
  void _handleHttpError(int? statusCode, String? description) {
    if (!mounted) return;

    String errorMsg;
    switch (statusCode) {
      case 401:
      case 403:
        errorMsg = '登录状态失效，请重新登录';
        setState(() {
          _loginRequired = true;
          _sessionUnavailable = true;
        });
        break;
      case 404:
        errorMsg = '页面不存在';
        break;
      case 500:
      case 502:
      case 503:
        errorMsg = '服务器暂时不可用，请稍后重试';
        break;
      default:
        errorMsg = '学工系统暂不可用（$statusCode）';
    }

    setState(() {
      _errorMessage = errorMsg;
    });
  }

  /// 手动刷新页面
  Future<void> _handleRefresh() {
    _browserRecoveryAttempted = false;
    return _prepareSession();
  }

  Future<void> _recoverBrowserSession() async {
    if (!mounted) return;
    if (_browserRecoveryAttempted) {
      setState(() {
        _loginRequired = true;
        _sessionUnavailable = true;
        _errorMessage = '学工网页会话未能恢复，请重新登录后重试';
      });
      return;
    }
    _browserRecoveryAttempted = true;
    await _prepareSession();
  }

  Widget _buildLoginRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _loginRequired ? Icons.lock_outline : Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _loginRequired ? '登录后可进入学工系统' : '暂时无法进入学工系统',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (_loginRequired)
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _openLoginSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('去登录'),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _prepareSession,
              child: Text(_loginRequired ? '重试自动登录' : '重新连接'),
            ),
          ],
        ),
      ),
    );
  }
}
