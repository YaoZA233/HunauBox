import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/score_model.dart';
import 'secure_storage_helper.dart';

class ScoreCacheSnapshot {
  const ScoreCacheSnapshot({
    required this.semesters,
    required this.scoresBySemester,
    required this.selectedSemester,
    required this.updatedAt,
  });

  final List<SemesterModel> semesters;
  final Map<String, List<ScoreModel>> scoresBySemester;
  final String? selectedSemester;
  final DateTime? updatedAt;
}

class ScoreCacheStore {
  static const _keyPrefix = 'score_snapshot_v1:';

  Future<String?> account() async {
    try {
      return await SecureStorageHelper().getUsername();
    } catch (_) {
      return null;
    }
  }

  Future<ScoreCacheSnapshot?> read({required String? owner}) async {
    try {
      if (owner == null || owner.isEmpty || owner != await account()) {
        return null;
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyPrefix${Uri.encodeComponent(owner)}');
      if (raw == null || owner != await account()) return null;
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final semesters = (data['semesters'] as List? ?? [])
          .whereType<Map>()
          .map(_semesterFromJson)
          .toList();
      final rawScores = data['scores'] as Map? ?? const {};
      final scores = <String, List<ScoreModel>>{};
      for (final entry in rawScores.entries) {
        if (entry.value is List) {
          scores[entry.key.toString()] = (entry.value as List)
              .whereType<Map>()
              .map(_scoreFromJson)
              .toList();
        }
      }
      return ScoreCacheSnapshot(
        semesters: semesters,
        scoresBySemester: scores,
        selectedSemester: data['selectedSemester']?.toString(),
        updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String? owner,
    required List<SemesterModel> semesters,
    required Map<String, List<ScoreModel>> scoresBySemester,
    required String? selectedSemester,
    required DateTime updatedAt,
  }) async {
    try {
      if (owner == null || owner.isEmpty || owner != await account()) return;
      final prefs = await SharedPreferences.getInstance();
      if (owner != await account()) return;
      await prefs.setString(
        '$_keyPrefix${Uri.encodeComponent(owner)}',
        jsonEncode({
          'semesters': semesters.map(_semesterToJson).toList(),
          'scores': scoresBySemester.map(
            (key, value) => MapEntry(key, value.map(_scoreToJson).toList()),
          ),
          'selectedSemester': selectedSemester,
          'updatedAt': updatedAt.toIso8601String(),
        }),
      );
    } catch (_) {
      // Cache failures must not affect a successful score query.
    }
  }

  Map<String, dynamic> _semesterToJson(SemesterModel value) => {
    'value': value.value,
    'xq': value.xq,
    'name': value.name,
    'isActive': value.isActive,
  };

  SemesterModel _semesterFromJson(Map value) => SemesterModel(
    value: value['value']?.toString() ?? '',
    xq: value['xq']?.toString() ?? '',
    name: value['name']?.toString() ?? '',
    isActive: value['isActive'] == true,
  );

  Map<String, dynamic> _scoreToJson(ScoreModel value) => {
    'courseName': value.courseName,
    'score': value.score,
    'credit': value.credit,
    'dailyScore': value.dailyScore,
    'examType': value.examType,
  };

  ScoreModel _scoreFromJson(Map value) => ScoreModel(
    courseName: value['courseName']?.toString() ?? '',
    score: value['score']?.toString() ?? '',
    credit: value['credit']?.toString(),
    dailyScore: value['dailyScore']?.toString(),
    examType: value['examType']?.toString(),
  );
}
