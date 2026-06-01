import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class NavigationSettingsStore {
  NavigationSettingsStore._internal();

  static final NavigationSettingsStore instance = NavigationSettingsStore._internal();

  static const String _fileName = 'navigation_settings.json';
  final ValueNotifier<bool> useFloatingNav = ValueNotifier(false);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final file = await _getFile();
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        useFloatingNav.value = data['useFloatingNav'] == true;
      } catch (e) {
        useFloatingNav.value = false;
      }
    }
    _loaded = true;
  }

  Future<void> save(bool value) async {
    useFloatingNav.value = value;
    final file = await _getFile();
    await file.writeAsString(jsonEncode({'useFloatingNav': value}));
  }

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}
