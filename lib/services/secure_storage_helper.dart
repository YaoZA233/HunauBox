import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageHelper {
  final _storage = const FlutterSecureStorage();

  Future<void> saveUsername(String u) async =>
      await _storage.write(key: 'user', value: u);
  Future<void> savePassword(String p) async =>
      await _storage.write(key: 'pwd', value: p);
  Future<String?> getUsername() async => await _storage.read(key: 'user');
  Future<String?> getPassword() async => await _storage.read(key: 'pwd');
  Future<void> saveTuitionIdCard(String value) async =>
      await _storage.write(key: 'tuition_id_card', value: value);
  Future<void> saveTuitionName(String value) async =>
      await _storage.write(key: 'tuition_name', value: value);
  Future<String?> getTuitionIdCard() async =>
      await _storage.read(key: 'tuition_id_card');
  Future<String?> getTuitionName() async =>
      await _storage.read(key: 'tuition_name');
  Future<void> saveFitnessStudentId(String value) async =>
      await _storage.write(key: 'fitness_student_id', value: value);
  Future<void> saveFitnessPassword(String value) async =>
      await _storage.write(key: 'fitness_password', value: value);
  Future<String?> getFitnessStudentId() async =>
      await _storage.read(key: 'fitness_student_id');
  Future<String?> getFitnessPassword() async =>
      await _storage.read(key: 'fitness_password');
  Future<void> clearAll() async => await _storage.deleteAll();
}
