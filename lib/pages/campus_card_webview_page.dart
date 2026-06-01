import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/app_constants.dart';
import '../services/campus_card_service.dart';

class CampusCardWebViewPage extends StatefulWidget {
  const CampusCardWebViewPage({super.key});

  @override
  State<CampusCardWebViewPage> createState() => _CampusCardWebViewPageState();
}

class _CampusCardWebViewPageState extends State<CampusCardWebViewPage> {
  double _progress = 0;
  InAppWebViewController? _webViewController;

  @override
  Widget build(BuildContext context) {
    final url = CampusCardService.instance.getCampusCardHomeUrl();

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: MediaQuery.of(context).padding.top,
                color: const Color(0xFF80CBC4),
              ),
              if (_progress < 1)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF80CBC4)),
                ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(url)),
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
