import 'package:flutter/material.dart';

import '../models/quick_action_item.dart';
import 'quick_action_storage.dart';

class QuickActionStore {
  QuickActionStore._internal();

  static final QuickActionStore instance = QuickActionStore._internal();

  final ValueNotifier<List<String>> selectedIds = ValueNotifier([]);
  final QuickActionStorage _storage = QuickActionStorage();
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final ids = await _storage.readSelectedIds();
    
    final validIds = ids.where((id) => QuickActionCatalog.byId(id) != null).toList();
    
    if (validIds.length < 8) {
      selectedIds.value = List<String>.from(QuickActionCatalog.defaultIds);
      await _storage.saveSelectedIds(selectedIds.value);
    } else {
      selectedIds.value = validIds.take(8).toList();
    }
    _loaded = true;
  }

  Future<void> save(List<String> ids) async {
    selectedIds.value = ids;
    await _storage.saveSelectedIds(ids);
  }
}
