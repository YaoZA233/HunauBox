import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DormStorage {
  static const _fileName = 'dorm_info.json';

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<Map<String, dynamic>?> read(String accountId) async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return null;

      final root = jsonDecode(await file.readAsString());
      if (root is! Map) return null;
      final accounts = root['accounts'];
      if (accounts is! Map || accounts[accountId] is! Map) return null;
      return Map<String, dynamic>.from(accounts[accountId] as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String accountId, Map<String, dynamic> data) async {
    try {
      final file = await _getFile();
      final existing = await _readAll(file);
      final accounts = existing['accounts'] as Map<String, dynamic>;
      accounts[accountId] = data;
      await file.writeAsString(jsonEncode(existing));
    } catch (_) {
      // A cache write must never prevent the current dorm result from showing.
    }
  }

  Future<Map<String, dynamic>> _readAll(File file) async {
    if (!await file.exists()) return {'accounts': <String, dynamic>{}};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['accounts'] is Map) {
        return {
          'accounts': Map<String, dynamic>.from(decoded['accounts'] as Map),
        };
      }
    } catch (_) {}
    return {'accounts': <String, dynamic>{}};
  }
}
