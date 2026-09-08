import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;

import '../models/app_constants.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_helper.dart';
import '../services/xgxt_login_service.dart';
import '../services/app_cookie_manager.dart';
import '../widgets/login_bottom_sheet.dart';

class XgxtWebViewPage extends StatefulWidget {
  const XgxtWebViewPage({super.key});

  @override
  State<XgxtWebViewPage> createState() => _XgxtWebViewPageState();
}

class _XgxtWebViewPageState extends State<XgxtWebViewPage> {
  double _progress = 0;
  bool _isPreparing = true;
  bool _loginRequired = false;
  String? _errorMessage;
  int _webViewKey = 0;
  late String _initialUrl;
  InAppWebViewController? _webViewController;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  Timer? _loadTimeoutTimer;
  static const int _loadTimeoutSeconds = 60;

  @override
  void initState() {
    super.initState();
    _initialUrl = AppConstants.xgxtWapUrl;
    _prepareSession();
    _startLoadTimeout();
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(Duration(seconds: _loadTimeoutSeconds), () {
      if (_isPreparing && mounted) {
        setState(() {
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
    _webViewController?.stopLoading();
    super.dispose();
  }

  Future<void> _prepareSession() async {
    setState(() {
      _isPreparing = true;
      _loginRequired = false;
      _errorMessage = null;
    });

    final storage = SecureStorageHelper();
    final username = await storage.getUsername();
    final password = await storage.getPassword();

    if (username == null || password == null) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _loginRequired = true;
      });
      return;
    }

    try {
      await AppCookieManager().initialize();

      // 🚀 先检查现有会话是否有效，避免重复登录
      final sessionValid = await _checkSessionValid();
      if (sessionValid) {
        await AppCookieManager().syncMultiDomainCookiesToWebView(
          AppConstants.xgxtBaseUrl,
        );
        _initialUrl = AppConstants.xgxtWapUrl;
        if (!mounted) return;
        _cancelLoadTimeout();
        setState(() {
          _isPreparing = false;
          _loginRequired = false;
          _webViewKey += 1;
        });
        return;
      }

      // 会话过期，执行完整登录
      await AuthService().login(username, password, context);
      final casOk = await XgxtLoginService().performXgxtCasLogin();
      await AppCookieManager().syncMultiDomainCookiesToWebView(
        AppConstants.xgxtBaseUrl,
      );
      _initialUrl = casOk
          ? AppConstants.xgxtWapUrl
          : '${AppConstants.ssoBaseUrl}/cas/login?service=${Uri.encodeComponent(AppConstants.xgxtCasUrl)}';
      if (!mounted) return;
      _cancelLoadTimeout();
      setState(() {
        _isPreparing = false;
        _loginRequired = false;
        _webViewKey += 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _loginRequired = true;
        _errorMessage = '自动登录失败，请手动登录后重试';
      });
    }
  }

  /// 🚀 快速检查学工系统会话是否有效
  Future<bool> _checkSessionValid() async {
    try {
      final dio = Dio();
      dio.interceptors.add(
        dio_cookie.CookieManager(AppCookieManager().dioCookieJar),
      );
      final response = await dio.head(
        AppConstants.xgxtWapUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
      // 如果返回 200 且没有重定向到 CAS 登录页，说明会话有效
      if (response.statusCode == 200) return true;
      final location = response.headers.value('location') ?? '';
      return !location.contains('/cas/login');
    } catch (e) {
      return false;
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
      await AppCookieManager().syncMultiDomainCookiesFromWebView(
        AppConstants.ssoBaseUrl,
      );
      await AppCookieManager().syncMultiDomainCookiesToWebView(
        AppConstants.xgxtBaseUrl,
      );
      _initialUrl =
          '${AppConstants.ssoBaseUrl}/cas/login?service=${Uri.encodeComponent(AppConstants.xgxtCasUrl)}';
      setState(() {
        _loginRequired = false;
        _errorMessage = null;
        _webViewKey += 1;
      });
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
          : _loginRequired
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
                        initialUserScripts: UnmodifiableListView<UserScript>([
                          UserScript(
                            source:
                                "try { localStorage.setItem('token', 'flutter_xgxt'); sessionStorage.setItem('token', 'flutter_xgxt'); } catch(e) {}",
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
                              if (uri == null)
                                return NavigationActionPolicy.ALLOW;
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
                          _webViewController = controller;
                          await AppCookieManager()
                              .syncMultiDomainCookiesToWebView(
                                AppConstants.xgxtBaseUrl,
                              );
                          if (_initialUrl.isNotEmpty) {
                            await controller.loadUrl(
                              urlRequest: URLRequest(url: WebUri(_initialUrl)),
                            );
                          }
                        },
                        onLoadStart: (controller, url) {
                          if (!mounted) return;
                          _startLoadTimeout();
                          setState(() {
                            _isPreparing = false;
                            _errorMessage = null;
                            _progress = 0;
                          });
                        },
                        onLoadStop: (controller, url) async {
                          _cancelLoadTimeout();
                          final urlString = url?.toString() ?? '';
                          if (urlString.contains('authorize') ||
                              urlString.contains('login') ||
                              urlString.contains('ticket=')) {
                            await controller.evaluateJavascript(
                              source: """
                                  (function() {
                                    const keywords = ['授权', '同意', '进入', '确认', 'Continue', 'Authorize', 'Confirm'];
                                    const btns = Array.from(document.querySelectorAll('button, a, input[type="button"]'));
                                    const target = btns.find(el => {
                                      const t = (el.innerText || el.value || '').trim();
                                      return keywords.some(k => t.includes(k));
                                    });
                                    if (target) target.click();
                                  })();
                                """,
                            );
                          }
                          if (!mounted) return;
                          setState(() {
                            _errorMessage = null;
                          });
                        },
                        onProgressChanged: (controller, progress) {
                          setState(() {
                            _progress = progress / 100.0;
                          });
                        },
                        onLoadError: (controller, url, code, message) {
                          if (!mounted) return;
                          _handleLoadError('加载失败: $message');
                        },
                        onLoadHttpError:
                            (controller, url, statusCode, description) {
                              if (!mounted) return;
                              _handleHttpError(statusCode, description);
                            },
                        onReceivedError: (controller, request, error) {
                          if (!mounted) return;
                          _handleLoadError('WebView错误: ${error.description}');
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
                              onPressed: () {
                                setState(() {
                                  _errorMessage = null;
                                  _webViewKey += 1;
                                });
                              },
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
        color: Colors.black.withOpacity(0.4),
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

    if (_retryCount < _maxRetries) {
      _retryCount++;
      setState(() {
        _errorMessage = '加载失败($message)，正在重试... ($_retryCount/$_maxRetries)';
      });

      // 延迟重试，避免频繁请求
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _webViewController != null) {
          _webViewController?.reload();
        }
      });
    } else {
      setState(() {
        _errorMessage = '加载失败，请检查网络连接后重试';
        _retryCount = 0;
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
        setState(() => _loginRequired = true);
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
  Future<void> _handleRefresh() async {
    if (_webViewController != null) {
      setState(() {
        _errorMessage = null;
        _retryCount = 0;
      });
      await _webViewController?.reload();
    }
  }

  Widget _buildLoginRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              '登录后可进入学工系统',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
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
            TextButton(onPressed: _prepareSession, child: const Text('重试自动登录')),
          ],
        ),
      ),
    );
  }
}
