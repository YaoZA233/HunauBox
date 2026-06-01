import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class QuickActionStorage {
  static const String _fileName = 'quick_actions.json';

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<String>> readSelectedIds() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => e.toString()).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveSelectedIds(List<String> ids) async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(ids));
  }
}
