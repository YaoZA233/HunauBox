import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/app_constants.dart';
import '../models/score_model.dart';
import 'app_logger.dart';
import 'dio_client.dart';
import 'ydjwxt_auth_service.dart';

/// 移动教务系统成绩接口。
///
/// 旧门户的 `/pc/view/scoreIndex` 已下线（HTTP 404），新接口要求超星
/// OAuth 生成的 token，并以 JSON 返回学期和成绩数据。
class ScoreService {
  ScoreService._internal();

  static final ScoreService instance = ScoreService._internal();

  final _logger = AppLogger.instance;
  final _authService = YdjwxtAuthService();

  Future<void> _ensureReady() async {
    await DioClient().initialize();
  }

  Future<List<SemesterModel>> fetchSemesterList({bool isRetry = false}) async {
    try {
      final token = await _authService.getToken(forceRefresh: isRetry);
      await _ensureReady();
      final response = await DioClient().dio.post(
        AppConstants.ydjwxtSemesterListUrl,
        options: _apiOptions(token),
      );

      final data = _decodeMap(response.data);
      if (response.statusCode == 200 && data != null && _isSuccess(data)) {
        final rawList = data['data'];
        final list = rawList is List ? rawList : const [];
        return list
            .whereType<Map>()
            .map((item) {
              final id = item['semesterId']?.toString() ?? '';
              return SemesterModel(
                value: id,
                xq: _semesterPart(id),
                name: item['semesterName']?.toString() ?? id,
                isActive: item['isdqxq']?.toString() == '1',
              );
            })
            .where((semester) => semester.value.isNotEmpty)
            .toList();
      }

      if (!isRetry && _isAuthError(data)) {
        _authService.clearToken();
        return fetchSemesterList(isRetry: true);
      }
      throw Exception(
        data?['Msg']?.toString() ?? '获取学期列表失败: HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      if (!isRetry &&
          (e.response?.statusCode == 401 || e.response?.statusCode == 403)) {
        _authService.clearToken();
        return fetchSemesterList(isRetry: true);
      }
      rethrow;
    } catch (e) {
      _logger.e('获取学期列表失败: $e');
      rethrow;
    }
  }

  /// 保持现有 Provider 的返回结构，同时切换到移动教务接口。
  Future<Map<String, dynamic>> fetchScores({String? xn, String? xq}) async {
    final semesters = await fetchSemesterList();
    if (semesters.isEmpty) {
      return {'semesters': <SemesterModel>[], 'scores': <ScoreModel>[]};
    }

    SemesterModel selected;
    if (xn != null && xn.isNotEmpty) {
      selected = semesters.firstWhere(
        (semester) => semester.value == xn,
        orElse: () => semesters.firstWhere(
          (semester) =>
              semester.value.startsWith('$xn-') &&
              (xq == null || semester.xq == xq),
          orElse: () => semesters.first,
        ),
      );
    } else {
      selected = semesters.firstWhere(
        (semester) => semester.isActive,
        orElse: () => semesters.first,
      );
    }

    final scores = await _fetchScoresForSemester(selected.value);
    return {'semesters': semesters, 'scores': scores};
  }

  /// Loads every semester's scores for the analysis view.
  ///
  /// The semester list is fetched once, then each semester is requested in
  /// parallel so the analysis page can build a complete longitudinal profile.
  Future<Map<SemesterModel, List<ScoreModel>>> fetchAllScores() async {
    final semesters = await fetchSemesterList();
    if (semesters.isEmpty) return <SemesterModel, List<ScoreModel>>{};

    final entries = await Future.wait(
      semesters.map(
        (semester) async =>
            MapEntry(semester, await _fetchScoresForSemester(semester.value)),
      ),
    );
    return Map<SemesterModel, List<ScoreModel>>.fromEntries(entries);
  }

  Future<List<ScoreModel>> _fetchScoresForSemester(
    String semester, {
    bool isRetry = false,
  }) async {
    try {
      final token = await _authService.getToken(forceRefresh: isRetry);
      await _ensureReady();
      final response = await DioClient().dio.post(
        AppConstants.ydjwxtScoreUrl,
        queryParameters: {'semester': semester, 'type': '1'},
        options: _apiOptions(token),
      );

      final data = _decodeMap(response.data);
      if (response.statusCode == 200 && data != null && _isSuccess(data)) {
        final rawStudents = data['data'];
        if (rawStudents is! List || rawStudents.isEmpty) return [];
        final student = rawStudents.first;
        if (student is! Map || student['achievement'] is! List) return [];

        return (student['achievement'] as List).whereType<Map>().map((item) {
          return ScoreModel(
            courseName: item['courseName']?.toString() ?? '未知课程',
            score: item['fraction']?.toString() ?? 'N/A',
            credit: item['credit']?.toString(),
            examType: item['examinationNature']?.toString() ?? '正常考试',
          );
        }).toList();
      }

      if (!isRetry && _isAuthError(data)) {
        _authService.clearToken();
        return _fetchScoresForSemester(semester, isRetry: true);
      }
      throw Exception(
        data?['Msg']?.toString() ?? '获取成绩失败: HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      if (!isRetry &&
          (e.response?.statusCode == 401 || e.response?.statusCode == 403)) {
        _authService.clearToken();
        return _fetchScoresForSemester(semester, isRetry: true);
      }
      rethrow;
    } catch (e) {
      _logger.e('获取成绩失败（学期 $semester）: $e');
      rethrow;
    }
  }

  Options _apiOptions(String token) => Options(
    headers: {
      'token': token,
      'User-Agent': AppConstants.ydjwxtUA,
      'Referer': 'https://ydjwxt.hunau.edu.cn/hnnydx/',
      'Accept': 'application/json, text/plain, */*',
      'Origin': 'https://ydjwxt.hunau.edu.cn',
      'Content-Type': 'application/json',
    },
  );

  Map<String, dynamic>? _decodeMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 非 JSON 响应会在调用方转换为普通网络错误。
      }
    }
    return null;
  }

  bool _isSuccess(Map<String, dynamic> data) => data['code']?.toString() == '1';

  bool _isAuthError(Map<String, dynamic>? data) {
    final code = data?['code']?.toString();
    final message = data?['Msg']?.toString() ?? data?['msg']?.toString() ?? '';
    return code == '401' ||
        code == '-1' ||
        code == '0' ||
        message.contains('登录') ||
        message.toLowerCase().contains('token') ||
        message.contains('失效');
  }

  String _semesterPart(String id) {
    final parts = id.split('-');
    return parts.length >= 3 ? parts.last : '';
  }
}
