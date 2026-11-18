import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message_model.dart';
import '../services/chaoxing_cache_store.dart';
import '../services/notice_service.dart';
import '../services/app_logger.dart';
import '../services/course_notification_service.dart';
import '../services/unified_capsule_service.dart';

class NoticeState {
  final List<MessageModel> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextLastValue;
  final String? errorMessage;

  NoticeState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextLastValue,
    this.errorMessage,
  });

  NoticeState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextLastValue,
    String? errorMessage,
  }) {
    return NoticeState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextLastValue: nextLastValue ?? this.nextLastValue,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class NoticeNotifier extends StateNotifier<NoticeState> {
  final NoticeService _service = NoticeService();
  final _logger = AppLogger.instance;
  final _cache = ChaoxingCacheStore();
  Set<String> _readOverrides = {};
  String? _readOwner;

  NoticeNotifier() : super(NoticeState()) {
    // 可以在初始化时自动拉取
    refresh();
  }

  Future<void> refresh() async {
    if (state.isLoading) return;

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      nextLastValue: null,
      hasMore: true,
    );

    try {
      final owner = await _cache.account();
      final prefs = await SharedPreferences.getInstance();
      if (owner != null && owner.isNotEmpty) {
        final key =
            'notice_read_overrides_v1:${sha256.convert(utf8.encode(owner))}';
        if (_readOwner != owner) {
          _readOwner = owner;
          _readOverrides = prefs.getStringList(key)?.toSet() ?? {};
        }
      } else {
        _readOwner = null;
        _readOverrides = {};
      }
      final result = await _service.fetchAllMessageList();
      final messages = result.messages.map(_applyReadOverride).toList();
      state = state.copyWith(
        messages: messages,
        nextLastValue: result.nextLastValue,
        hasMore: result.hasMore,
        isLoading: false,
      );
      await CourseNotificationService.instance.notifyNewMessages(messages);
      final capsule = UnifiedCapsuleService.instance;
      final enabled = await capsule.loadEnabledTypes();
      await capsule.patch(
        enabledTypes: enabled,
        messages: messages
            .map(
              (m) => MessageData(
                id: m.uuid.isNotEmpty ? m.uuid : m.idCode,
                title: m.title,
                sender: m.createrName,
                content: m.content,
                time:
                    DateTime.tryParse(m.sendTime)?.millisecondsSinceEpoch ??
                    DateTime.now().millisecondsSinceEpoch,
                read: m.isRead,
              ),
            )
            .toList(),
      );
      _logger.i('Notice refreshed: ${result.messages.length} messages');
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      _logger.e('Failed to refresh notices: $e');
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _service.fetchMessageList(
        lastValue: state.nextLastValue,
      );
      state = state.copyWith(
        messages: [
          ...state.messages,
          ...result.messages.map(_applyReadOverride),
        ],
        nextLastValue: result.nextLastValue,
        hasMore: result.hasMore,
        isLoadingMore: false,
      );
      _logger.i('Notice loaded more: ${result.messages.length} messages');
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
      _logger.e('Failed to load more notices: $e');
    }
  }

  Future<void> markAsRead(String idCode) async {
    final matched = state.messages.where(
      (m) => m.idCode == idCode || m.uuid == idCode,
    );
    final ids =
        matched
            .expand((m) => [m.idCode, m.uuid])
            .where((id) => id.isNotEmpty)
            .toSet()
          ..add(idCode);
    _readOverrides.addAll(ids);
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (m.idCode == idCode || m.uuid == idCode) {
          return m.copyWith(isRead: true, hasRedDot: false);
        }
        return m;
      }).toList(),
    );
    await _persistReadOverrides();
  }

  MessageModel _applyReadOverride(MessageModel message) {
    if (_readOverrides.contains(message.idCode) ||
        _readOverrides.contains(message.uuid)) {
      return message.copyWith(isRead: true, hasRedDot: false);
    }
    return message;
  }

  Future<void> _persistReadOverrides() async {
    final owner = _readOwner ?? await _cache.account();
    if (owner == null || owner.isEmpty || owner != await _cache.account()) {
      return;
    }
    final key =
        'notice_read_overrides_v1:${sha256.convert(utf8.encode(owner))}';
    final prefs = await SharedPreferences.getInstance();
    if (owner == await _cache.account()) {
      await prefs.setStringList(key, _readOverrides.toList());
    }
  }

  void clear() {
    state = NoticeState();
  }
}

final noticeProvider = StateNotifierProvider<NoticeNotifier, NoticeState>((
  ref,
) {
  return NoticeNotifier();
});
