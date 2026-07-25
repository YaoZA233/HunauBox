import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/app_constants.dart';
import '../utils/location_helper.dart';

class BusTrackingPage extends StatefulWidget {
  const BusTrackingPage({super.key});

  @override
  State<BusTrackingPage> createState() => _BusTrackingPageState();
}

class _BusTrackingPageState extends State<BusTrackingPage> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  double _progress = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchLocationAndLoad();
  }

  Future<void> _fetchLocationAndLoad() async {
    try {
      final position = await LocationHelper.getCurrentPosition();
      if (position == null) {
        setState(() {
          _errorMessage = '获取定位失败，请检查定位服务与权限';
          _isLoading = false;
        });
        return;
      }

      final gcj02 = LocationHelper.wgs84ToGcj02(position.longitude, position.latitude);
      final url = '${AppConstants.schoolBusUrl}?lat=${gcj02['lat']}&lng=${gcj02['lng']}';

      if (_webViewController != null) {
        await _webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      }
    } catch (error) {
      setState(() {
        _errorMessage = '获取位置失败: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Container(
            height: MediaQuery.of(context).padding.top,
            color: Theme.of(context).colorScheme.surface,
          ),
          Expanded(
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) {
                  return;
                }
                if (_webViewController != null && await _webViewController!.canGoBack()) {
                  await _webViewController!.goBack();
                } else if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Stack(
                children: [
                  InAppWebView(
                    initialSettings: InAppWebViewSettings(
                      useShouldOverrideUrlLoading: true,
                      mediaPlaybackRequiresUserGesture: false,
                      javaScriptCanOpenWindowsAutomatically: true,
                      supportZoom: true,
                      builtInZoomControls: true,
                      displayZoomControls: false,
                      userAgent: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36',
                      allowsInlineMediaPlayback: true,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    onLoadStart: (controller, url) {
                      setState(() => _isLoading = true);
                    },
                    onLoadStop: (controller, url) {
                      setState(() => _isLoading = false);
                    },
                    onProgressChanged: (controller, progress) {
                      setState(() {
                        _progress = progress / 100;
                      });
                    },
                  ),
                  if (_isLoading)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                      ),
                    ),
                  if (_isLoading)
                    Container(
                      color: Colors.white,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  Positioned(
                    top: 8,
                    right: 16,
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black12, width: 0.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (_errorMessage != null) {
                                setState(() {
                                  _isLoading = true;
                                  _errorMessage = null;
                                });
                                _fetchLocationAndLoad();
                              } else {
                                _webViewController?.reload();
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.refresh_rounded, size: 18, color: Colors.black87),
                            ),
                          ),
                          Container(width: 0.5, height: 16, color: Colors.black12),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.pop(context),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.close_rounded, size: 18, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_errorMessage != null)
                    Container(
                      color: Colors.white,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off_rounded, size: 60, color: Colors.grey[200]),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                            const SizedBox(height: 24),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                  _errorMessage = null;
                                });
                                _fetchLocationAndLoad();
                              },
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
