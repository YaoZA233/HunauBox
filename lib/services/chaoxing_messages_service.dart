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
  Map<String, dynamic> toJson() => {
    'index': index,
    'name': name,
    'preview': preview,
    'time': time,
  };
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
  Map<String, dynamic> toJson() => {
    'sender': sender,
    'text': text,
    'time': time,
    'mine': mine,
  };
}

/// Uses Chaoxing's own WebIM to authenticate and decode its message protocol.
/// Only rendered conversation and message fields are returned to Dart.
class ChaoxingMessagesService {
  ChaoxingMessagesService({
    Future<dynamic> Function(String)? evaluate,
    Future<void> Function(Duration)? wait,
  }) : _reader = evaluate,
       _wait = wait ?? Future<void>.delayed;

  final Future<dynamic> Function(String)? _reader;
  final Future<void> Function(Duration) _wait;
  static const url = 'https://fe.chaoxing.com/front/webim/index.html';
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  bool _disposed = false;
  final _created = Completer<void>();
  Completer<void>? _reloaded;

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
      onLoadStop: (controller, uri) {
        if (uri?.host == 'fe.chaoxing.com' && _reloaded?.isCompleted == false) {
          _reloaded!.complete();
        }
      },
    );
    await _view!.run();
    await _created.future.timeout(const Duration(seconds: 15));
  }

  /// Reuse the initialized WebView, but reload the site so the list is fresh.
  Future<List<ChaoxingConversation>> refreshConversations() async {
    final controller = _controller;
    if (_disposed || controller == null) throw StateError('消息页面尚未准备好');
    final reloaded = Completer<void>();
    _reloaded = reloaded;
    try {
      await controller.reload();
      await reloaded.future.timeout(const Duration(seconds: 20));
      if (_disposed) throw StateError('页面已关闭');
      return await conversations();
    } finally {
      if (identical(_reloaded, reloaded)) _reloaded = null;
    }
  }

  Future<dynamic> _evaluate(String source) async {
    if (_disposed) throw StateError('页面已关闭');
    if (_reader != null) return _reader(source);
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
    String? previous;
    var stableReads = 0;
    for (var attempt = 0; attempt < 60; attempt++) {
      if (_disposed) throw StateError('页面已关闭');
      final data = await _evaluate('''(() => {
        if (/passport|login/i.test(location.hostname + location.pathname)) return JSON.stringify({error: 'login'});
        const list = document.querySelector('.conversation-list');
        if (!list || list.querySelector('.skeleton-item, [aria-busy="true"]')) return null;
        const items = Array.from(list.querySelectorAll('.conversation-item')).map((e, index) => ({
          index, name: e.querySelector('.name')?.innerText?.trim() || '',
          preview: e.querySelector('.desc')?.innerText?.trim() || '',
          time: e.querySelector('.time')?.innerText?.trim() || ''
        }));
        return JSON.stringify(items);
      })()''');
      if (data is Map && data['error'] != null) {
        throw StateError('学习通登录已过期，请打开网页重新登录');
      }
      // The container mounts before WebIM authentication and async history
      // complete. An empty/partly rendered list is never a successful snapshot.
      final parsed = data is List ? parseConversations(data) : null;
      if (parsed != null &&
          parsed.isNotEmpty &&
          parsed.length == (data as List).length) {
        final signature = jsonEncode(
          parsed.map((c) => [c.index, c.name]).toList(),
        );
        stableReads = signature == previous ? stableReads + 1 : 1;
        previous = signature;
        if (stableReads >= 3) return parsed;
      } else {
        previous = null;
        stableReads = 0;
      }
      // One recovery reload when the embedded page appears stuck; keep a
      // bounded overall polling budget instead of accepting a false empty list.
      if (attempt == 29 && _controller != null) {
        await _controller!.reload();
        previous = null;
        stableReads = 0;
      }
      await _wait(const Duration(milliseconds: 400));
    }
    throw StateError('学习通尚未返回有效会话，请重试或打开网页检查登录状态');
  }

  Future<List<ChaoxingChatMessage>> messages(
    ChaoxingConversation conversation,
  ) async {
    final selected = await _evaluate('''(() => {
      const items = document.querySelectorAll('.conversation-list .conversation-item');
      const item = items[${conversation.index}];
      if (!item || item.querySelector('.name')?.innerText?.trim() !== ${jsonEncode(conversation.name)}) return JSON.stringify(false);
      item.click();
      return JSON.stringify(true);
    })()''');
    if (selected != true) throw StateError('会话列表已变化，请刷新后重试');
    // WebIM changes the header before its asynchronous history request finishes.
    await _wait(const Duration(milliseconds: 1500));
    for (var attempt = 0; attempt < 20; attempt++) {
      if (_disposed) throw StateError('页面已关闭');
      final data = await _evaluate('''(() => {
        const title = document.querySelector('.chat-header .chat-name')?.innerText?.trim();
        const area = document.querySelector('.message-area');
        const selected = document.querySelectorAll('.conversation-list .conversation-item')[${conversation.index}];
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
      if (data is List) {
        final parsed = parseMessages(data);
        if (parsed.isNotEmpty && parsed.length == data.length) return parsed;
      }
      if (data is Map && data['error'] != null) {
        throw StateError('学习通消息加载失败，请在网页中查看');
      }
      await _wait(const Duration(milliseconds: 500));
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
    if (_reloaded?.isCompleted == false) _reloaded!.complete();
    await _view?.dispose();
    _controller = null;
  }
}
