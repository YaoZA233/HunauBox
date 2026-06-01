import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageHelper {
  final _storage = const FlutterSecureStorage();
  
  Future<void> saveUsername(String u) async => await _storage.write(key: 'user', value: u);
  Future<void> savePassword(String p) async => await _storage.write(key: 'pwd', value: p);
  Future<String?> getUsername() async => await _storage.read(key: 'user');
  Future<String?> getPassword() async => await _storage.read(key: 'pwd');
  Future<void> clearAll() async => await _storage.deleteAll();
}