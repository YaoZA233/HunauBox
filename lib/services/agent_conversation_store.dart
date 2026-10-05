import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_models.dart';

final agentConversationsProvider =
    ChangeNotifierProvider<AgentConversationStore>((ref) {
      final store = AgentConversationStore();
      unawaited(store.load());
      return store;
    });

/// Local chat records contain messages and tool history, never model credentials.
/// Writes are ordered so an older save cannot restore a deleted conversation.
class AgentConversationStore extends ChangeNotifier {
  AgentConversationStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? _readLocal,
       _write = write ?? _writeLocal;

  static const _key = 'campus_agent_conversations_v1';
  static Future<String?> _readLocal() async =>
      (await SharedPreferences.getInstance()).getString(_key);
  static Future<void> _writeLocal(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(_key, value)) {
      throw const AgentException('聊天记录保存失败');
    }
  }

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final _records = <String, AgentConversation>{};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool loaded = false;
  String? loadError;
  String? saveError;
  String? activeId;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<AgentConversation> get conversations =>
      _records.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  AgentConversation? get active => _records[activeId];
  AgentConversation? byId(String id) => _records[id];

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final raw = await _read();
      final restored = <String, AgentConversation>{};
      String? selected;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['version'] != 1) {
          throw const FormatException('Unknown version');
        }
        for (final row in data['conversations'] as List) {
          var conversation = AgentConversation.fromJson(
            Map<String, dynamic>.from(row as Map),
          );
          if (conversation.pending) {
            // The persisted protocol already has an interruption placeholder.
            conversation = conversation.copyWith(
              pending: false,
              messages: [
                ...conversation.messages,
                const AgentDisplayMessage(
                  'assistant',
                  agentInterruptedText,
                  incomplete: true,
                ),
              ],
            );
          }
          restored[conversation.id] = conversation;
        }
        selected = data['activeId'] as String?;
      }
      _records.clear();
      _records.addAll(restored);
      activeId = restored.containsKey(selected) ? selected : null;
      loadError = null;
    } catch (_) {
      // Preserve unreadable storage; never silently overwrite existing chats.
      loadError = '无法读取聊天记录，请重试；原记录未被覆盖';
    }
    loaded = true;
    _notify();
  }

  Future<void> retryLoad() async {
    _loading = null;
    await load();
  }

  Future<void> upsert(AgentConversation conversation) async {
    await load();
    _checkReadable();
    _records[conversation.id] = conversation;
    activeId = conversation.id;
    await _persist();
  }

  Future<void> select(String? id) async {
    await load();
    _checkReadable();
    activeId = _records.containsKey(id) ? id : null;
    await _persist();
  }

  Future<void> rename(String id, String title) async {
    await load();
    _checkReadable();
    final record = _records[id];
    if (record == null || title.trim().isEmpty) return;
    _records[id] = record.copyWith(title: title.trim());
    await _persist();
  }

  Future<void> delete(String id) async {
    await load();
    _checkReadable();
    _records.remove(id);
    if (activeId == id) activeId = null;
    await _persist();
  }

  Future<void> clear() async {
    await load();
    _records.clear();
    activeId = null;
    loadError = null;
    await _persist();
  }

  Future<void> retrySave() async {
    _checkReadable();
    await _persist();
  }

  void _checkReadable() {
    if (loadError != null) throw AgentException(loadError!);
  }

  Future<void> _persist() async {
    final snapshot = jsonEncode({
      'version': 1,
      'activeId': activeId,
      'conversations': _records.values.map((c) => c.toJson()).toList(),
    });
    _notify();
    final writing = _writes.then((_) => _write(snapshot));
    // Keep the queue usable after a failed native write.
    _writes = writing.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await writing;
      saveError = null;
    } catch (_) {
      saveError = '聊天记录尚未保存到设备，请重试保存';
      throw AgentException(saveError!);
    } finally {
      _notify();
    }
  }
}
