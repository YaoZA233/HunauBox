import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../widgets/campus_loading_mark.dart';
import '../widgets/campus_progress_bar.dart';

import '../models/app_constants.dart';
import '../services/campus_card_service.dart';
import '../services/app_cookie_manager.dart';

class CampusCardWebViewPage extends StatefulWidget {
  const CampusCardWebViewPage({super.key});

  @override
  State<CampusCardWebViewPage> createState() => _CampusCardWebViewPageState();
}

class _CampusCardWebViewPageState extends State<CampusCardWebViewPage> {
  double _progress = 0;
  InAppWebViewController? _webViewController;
  late Future<String> _sessionReady;

  @override
  void initState() {
    super.initState();
    _sessionReady = _prepareSession();
  }

  Future<String> _prepareSession() async {
    final service = CampusCardService.instance;
    if (service.openid == null && await service.authenticate() == null) {
      throw Exception('校园卡授权失败，请稍后重试');
    }
    final url = service.getCampusCardHomeUrl();
    await AppCookieManager().syncMultiDomainCookiesToWebView(url);
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: MediaQuery.of(context).padding.top,
                color: accent,
              ),
              if (_progress < 1)
                CampusProgressBar(
                  value: _progress,
                  backgroundColor: Colors.grey[200],
                  color: accent,
                ),
              Expanded(
                child: FutureBuilder<String>(
                  future: _sessionReady,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: TextButton(
                          onPressed: () => setState(() {
                            _sessionReady = _prepareSession();
                          }),
                          child: const Text('校园卡加载失败，点击重试'),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CampusLoadingMark(size: 36));
                    }
                    return InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(snapshot.data!),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        userAgent: AppConstants.campusCardUA,
                      ),
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                      },
                      onProgressChanged: (controller, progress) {
                        setState(() {
                          _progress = progress / 100.0;
                        });
                      },
                    );
                  },
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
            onTap: () => _webViewController?.reload(),
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
}
