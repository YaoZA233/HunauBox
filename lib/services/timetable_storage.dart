import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/course_model.dart';

class TimetableStorage {
  static const String _fileName = 'current_timetable.ics';
  static const String _metaFileName = 'timetable_meta.json';
  static const String _courseListFileName = 'courses.json';

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<bool> hasLocalTimetable() async {
    try {
      final file = await _getFile();
      return file.exists();
    } catch (e) {
      return false;
    }
  }

  Future<void> saveTimetable(String icsContent) async {
    try {
      final file = await _getFile();
      await file.writeAsString(icsContent);
    } catch (e) {
      throw Exception('保存课表失败: $e');
    }
  }

  Future<String?> readTimetable() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        return file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteTimetable() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      return;
    }
  }

  Future<String?> getTimetableFilePath() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> saveMetadata({
    required String semester,
    required DateTime firstWeekMonday,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metaFile = File('${directory.path}/$_metaFileName');

      final metadata = {
        'semester': semester,
        'firstWeekMonday': firstWeekMonday.toIso8601String(),
        'savedAt': DateTime.now().toIso8601String(),
      };

      await metaFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      throw Exception('保存课表元数据失败: $e');
    }
  }

  Future<Map<String, dynamic>?> readMetadata() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metaFile = File('${directory.path}/$_metaFileName');

      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteMetadata() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metaFile = File('${directory.path}/$_metaFileName');

      if (await metaFile.exists()) {
        await metaFile.delete();
      }
    } catch (e) {
      return;
    }
  }

  Future<void> saveCourseList(List<CourseModel> courses) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_courseListFileName');
      final jsonList = courses.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      throw Exception('保存课程列表失败: $e');
    }
  }

  Future<List<CourseModel>> readCourseList() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_courseListFileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList
            .map((j) => CourseModel.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteCourseList() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_courseListFileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      return;
    }
  }
}
