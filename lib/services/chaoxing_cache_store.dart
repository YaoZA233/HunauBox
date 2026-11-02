import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_storage_helper.dart';

class ChaoxingCacheStore {
  ChaoxingCacheStore({Future<String?> Function()? account})
    : _account = account ?? _defaultAccount;
  final Future<String?> Function() _account;
  static Future<String?> _defaultAccount() =>
      SecureStorageHelper().getUsername();
  Future<String?> account() async {
    try {
      return await _account();
    } catch (_) {
      return null;
    }
  }

  String _key(String owner, String resource) =>
      'chaoxing_snapshot_v1:${sha256.convert(utf8.encode(owner))}:$resource';
  Future<Map<String, dynamic>?> read(String resource) async {
    try {
      final owner = await account();
      if (owner == null || owner.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(owner, resource));
      if (raw == null || owner != await account()) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String? owner,
    String resource,
    Map<String, dynamic> value,
  ) async {
    try {
      if (owner == null || owner.isEmpty || owner != await account()) return;
      final prefs = await SharedPreferences.getInstance();
      if (owner != await account()) return;
      await prefs.setString(_key(owner, resource), jsonEncode(value));
    } catch (_) {
      /* Keep fetched data visible if storage is unavailable. */
    }
  }
}
