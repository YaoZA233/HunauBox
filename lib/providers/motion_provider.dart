import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/motion_settings.dart';

final motionSettingsProvider =
    StateNotifierProvider<MotionSettingsNotifier, MotionSettings>(
      (ref) => MotionSettingsNotifier(),
    );

class MotionSettingsNotifier extends StateNotifier<MotionSettings> {
  MotionSettingsNotifier() : super(const MotionSettings()) {
    ready = _load();
  }

  static const storageKey = 'interaction_motion_settings';
  late final Future<void> ready;
  bool _edited = false;
  Future<void> _writes = Future.value();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (!mounted || _edited || raw == null) return;
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) state = MotionSettings.fromJson(json);
    } catch (_) {
      // An older or damaged preference must not prevent navigation.
    }
  }

  Future<void> update(MotionSettings settings) {
    _edited = true;
    state = settings;
    final raw = jsonEncode(settings.toJson());
    // Keep rapid changes ordered, including edits made before loading finishes.
    final write = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, raw)) {
        throw StateError('无法保存动画设置');
      }
    });
    _writes = write.catchError((Object _) {});
    return write;
  }
}
