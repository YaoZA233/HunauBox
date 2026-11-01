import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_cookie_manager.dart';
import 'chaoxing_course_service.dart';

class ChaoxingConversation {
  const ChaoxingConversation({
    required this.index,
    required this.name,
    required this.preview,
    required this.time,
  });
  final int index;
  final String name;
  final String preview;
  final String time;
}

class ChaoxingChatMessage {
  const ChaoxingChatMessage({
    required this.sender,
    required this.text,
    required this.time,
    required this.mine,
  });
  final String sender;
  final String text;
  final String time;
  final bool mine;
}

/// Uses Chaoxing's own WebIM to authenticate and decode its message protocol.
/// Only rendered conversation and message fields are returned to Dart.
class ChaoxingMessagesService {
  static const url = 'https://fe.chaoxing.com/front/webim/index.html';
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  bool _disposed = false;
  final _created = Completer<void>();

  Future<void> start() async {
    await AppCookieManager().initialize();
    await AppCookieManager().injectAllChaoxingCookies();
    for (final url in [
      ChaoxingMessagesService.url,
      'https://learn.chaoxing.com',
      'https://im.chaoxing.com',
    ]) {
      await AppCookieManager().syncMultiDomainCookiesToWebView(url);
    }
    if (_disposed) throw StateError('页面已关闭');
    _view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        sharedCookiesEnabled: true,
        thirdPartyCookiesEnabled: true,
        userAgent: ChaoxingCourseService.desktopUserAgent,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        if (!_created.isCompleted) _created.complete();
      },
    );
    await _view!.run();
    await _created.future.timeout(const Duration(seconds: 15));
  }

  Future<dynamic> _evaluate(String source) async {
    if (_disposed || _controller == null) throw StateError('消息页面尚未准备好');
    final result = await _controller!.evaluateJavascript(source: source);
    if (result is! String) return result;
    try {
      return jsonDecode(result);
    } catch (_) {
      return null;
    }
  }

  Future<List<ChaoxingConversation>> conversations() async {
    for (var attempt = 0; attempt < 60; attempt++) {
      if (_disposed) throw StateError('页面已关闭');
      final data = await _evaluate('''(() => {
        if (!document.querySelector('.conversation-list') || document.querySelector('.conversation-list .skeleton-item')) return null;
        return JSON.stringify(Array.from(document.querySelectorAll('.conversation-item')).map((e, index) => ({
          index, name: e.querySelector('.name')?.innerText?.trim() || '',
          preview: e.querySelector('.desc')?.innerText?.trim() || '',
          time: e.querySelector('.time')?.innerText?.trim() || ''
        })));
      })()''');
      if (data is List) return parseConversations(data);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('学习通消息加载超时，请检查登录状态或网络');
  }

  Future<List<ChaoxingChatMessage>> messages(
    ChaoxingConversation conversation,
  ) async {
    final selected = await _evaluate('''(() => {
      const items = document.querySelectorAll('.conversation-item');
      const item = items[${conversation.index}];
      if (!item || item.querySelector('.name')?.innerText?.trim() !== ${jsonEncode(conversation.name)}) return JSON.stringify(false);
      item.click();
      return JSON.stringify(true);
    })()''');
    if (selected != true) throw StateError('会话列表已变化，请刷新后重试');
    // WebIM changes the header before its asynchronous history request finishes.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (var attempt = 0; attempt < 20; attempt++) {
      if (_disposed) throw StateError('页面已关闭');
      final data = await _evaluate('''(() => {
        const title = document.querySelector('.chat-header .chat-name')?.innerText?.trim();
        const area = document.querySelector('.message-area');
        const selected = document.querySelectorAll('.conversation-item')[${conversation.index}];
        if (!selected?.classList.contains('is-selected') || title !== ${jsonEncode(conversation.name)} || !area || area.querySelector('.load-more-tip')) return null;
        const state = area.querySelector('.empty-state');
        if (state) {
          const status = state.innerText.trim();
          if (!status || /加载|loading/i.test(status) && !/失败|failed/i.test(status)) return null;
          if (/失败|failed|过期|expired/i.test(status)) return JSON.stringify({error: status});
        }
        let time = '';
        const result = [];
        for (const el of area.children) {
          if (el.classList.contains('time-stamp')) time = el.innerText.trim();
          if (!el.classList.contains('message-row')) continue;
          const bubble = el.querySelector('.bubble');
          const attachment = el.querySelector('attachment-item')?.shadowRoot?.querySelector('.attach-item');
          const text = el.querySelector('.bubble-text')?.innerText?.trim() || attachment?.innerText?.trim() || bubble?.innerText?.trim() || '[图片或附件，请在学习通中查看]';
          result.push({sender: el.querySelector('.sender-name')?.innerText?.trim() || '', text, time, mine: el.classList.contains('is-self')});
        }
        return JSON.stringify(result);
      })()''');
      if (data is List) return parseMessages(data);
      if (data is Map && data['error'] != null) {
        throw StateError('学习通消息加载失败，请在网页中查看');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('消息加载超时，请重试');
  }

  static List<ChaoxingConversation> parseConversations(List<dynamic> data) => [
    for (final item in data)
      if (item is Map &&
          item['index'] is int &&
          (item['name']?.toString().trim().isNotEmpty ?? false))
        ChaoxingConversation(
          index: item['index'] as int,
          name: item['name'].toString(),
          preview: item['preview']?.toString() ?? '',
          time: item['time']?.toString() ?? '',
        ),
  ];

  static List<ChaoxingChatMessage> parseMessages(List<dynamic> data) => [
    for (final item in data)
      if (item is Map && (item['text']?.toString().trim().isNotEmpty ?? false))
        ChaoxingChatMessage(
          sender: item['sender']?.toString() ?? '',
          text: item['text'].toString(),
          time: item['time']?.toString() ?? '',
          mine: item['mine'] == true,
        ),
  ];

  Future<void> dispose() async {
    _disposed = true;
    await _view?.dispose();
    _controller = null;
  }
}
