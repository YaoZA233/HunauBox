import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_helper.dart';

/// Read-only snapshots are scoped to the logged-in account and business key.
/// They are display data, never proof of a valid payment session.
class FinanceSnapshot {
  const FinanceSnapshot(this.data, this.updatedAt);
  final Map<String, dynamic> data;
  final DateTime updatedAt;
}

class FinanceCacheStore {
  static Future<String?> account() async {
    try {
      return await SecureStorageHelper().getUsername();
    } catch (_) {
      return null;
    }
  }

  static String _key(String account, String resource) =>
      'finance_snapshot_v1:${Uri.encodeComponent(account)}:$resource';

  static Future<FinanceSnapshot?> read(String resource) async {
    try {
      final owner = await account();
      if (owner == null || owner.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(owner, resource));
      if (raw == null || owner != await account()) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return FinanceSnapshot(
        Map<String, dynamic>.from(decoded['data'] as Map),
        DateTime.parse(decoded['updatedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    String? owner,
    String resource,
    Map<String, dynamic> data,
    DateTime updatedAt,
  ) async {
    try {
      if (owner == null || owner.isEmpty || owner != await account()) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(owner, resource),
        jsonEncode({'data': data, 'updatedAt': updatedAt.toIso8601String()}),
      );
    } catch (_) {
      // A disk/cache failure must not turn a successful query into a failure.
    }
  }
}
