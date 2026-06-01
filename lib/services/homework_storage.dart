import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/homework_model.dart';
import '../services/app_logger.dart';

class HomeworkStorage {
  final _logger = AppLogger.instance;
  static const String _fileName = 'homework_list.json';

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('\${directory.path}/$_fileName');
  }

  Future<void> saveHomeworkList(List<HomeworkModel> list) async {
    try {
      final file = await _getFile();
      final jsonString = jsonEncode(list.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonString);
      _logger.d('💾 Saved \${list.length} homework items to local storage.');
    } catch (e) {
      _logger.e('❌ Failed to save homework list: \$e');
    }
  }

  Future<List<HomeworkModel>?> readHomeworkList() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return null; // Return null to indicate no local data
      }

      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      
      _logger.d('📖 Read \${jsonList.length} homework items from local storage.');
      return jsonList.map((e) => HomeworkModel.fromJson(e)).toList();
    } catch (e) {
      _logger.e('❌ Failed to read homework list: \$e');
      return null;
    }
  }

  Future<void> deleteHomeworkList() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
        _logger.d('🗑️ Deleted homework list from local storage.');
      }
    } catch (e) {
      _logger.e('❌ Failed to delete homework list: \$e');
    }
  }
}
