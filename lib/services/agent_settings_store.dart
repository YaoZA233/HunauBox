import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/agent_models.dart';

final agentSettingsProvider = ChangeNotifierProvider<AgentSettingsStore>((ref) {
  final store = AgentSettingsStore.instance;
  unawaited(store.load());
  return store;
});

/// 整份配置作为单个安全存储记录写入，不把 Key 放进普通偏好、备份或日志。
class AgentSettingsStore extends ChangeNotifier {
  AgentSettingsStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
    Future<void> Function()? delete,
  }) : _read = read ?? (() => _storage.read(key: _key)),
       _write = write ?? ((value) => _storage.write(key: _key, value: value)),
       _delete = delete ?? (() => _storage.delete(key: _key));

  static final instance = AgentSettingsStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'campus_agent_config_v1';
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final Future<void> Function() _delete;
  AgentConfig _config = const AgentConfig();
  AgentConfig get config => _config;
  bool loaded = false;
  bool saving = false;
  String? error;
  Future<void>? _loading;
  Future<void>? _pendingWrite;
  int _version = 0;
  bool _clearing = false;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final saved = await _read();
      _config = saved == null ? const AgentConfig() : AgentConfig.decode(saved);
    } catch (_) {
      _config = const AgentConfig();
      error = '无法读取安全存储，Agent 已保持关闭，请重试';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> retryLoad() async {
    if (saving) return;
    error = null;
    _loading = null;
    await load();
  }

  Future<void> save(AgentConfig next) async {
    await load();
    if (error != null) throw const AgentException('无法读取安全存储，请先重试');
    if (saving) throw const AgentException('配置正在保存，请稍后再试');
    final version = _version;
    saving = true;
    notifyListeners();
    try {
      final write = _write(next.encodeForStorage());
      _pendingWrite = write;
      await write;
      // 退出登录 / 清除期间，迟到的保存不能重新开启 Agent。
      if (version == _version) _config = next;
    } catch (_) {
      throw const AgentException('配置未能保存，请检查设备安全存储后重试');
    } finally {
      _pendingWrite = null;
      saving = _clearing;
      notifyListeners();
    }
  }

  Future<void> setEnabled(bool value) async {
    await load();
    await save(_config.copyWith(enabled: value));
  }

  Future<void> clear() async {
    await load();
    if (_clearing) throw const AgentException('配置正在清除，请稍后再试');
    _clearing = true;
    saving = true;
    _version++;
    // 先关闭内存状态，立即撤销正在进行的模型调用。
    _config = const AgentConfig();
    notifyListeners();
    try {
      try {
        await _pendingWrite;
      } catch (_) {}
      await _delete();
    } finally {
      _clearing = false;
      saving = false;
      notifyListeners();
    }
  }
}
