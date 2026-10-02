import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/app_constants.dart';
import '../models/course_model.dart';
import '../models/timetable_adjustment.dart';
import '../utils/ics_generator.dart';
import '../utils/ydjwxt_json_parser.dart';
import 'app_logger.dart';
import 'course_notification_service.dart';
import 'dio_client.dart';
import 'timetable_storage.dart';
import 'ydjwxt_auth_service.dart';

class TimetableSyncResult {
  const TimetableSyncResult({
    required this.courses,
    required this.firstWeekMonday,
    required this.semester,
  });

  final List<CourseModel> courses;
  final DateTime firstWeekMonday;
  final String semester;
}

/// 通过移动教务 JSON 接口同步当前学期课表。
class TimetableService {
  final _logger = AppLogger.instance;
  final _authService = YdjwxtAuthService();

  Future<TimetableSyncResult> downloadAndSaveTimetable({
    void Function(String progress)? onProgress,
  }) async {
    onProgress?.call('正在验证移动教务身份…');
    await DioClient().initialize();

    var token = await _authService.getToken();
    List<Map<String, dynamic>> weeks;
    try {
      weeks = await _fetchAllWeeks(token, onProgress);
    } on _YdjwxtAuthException {
      _logger.w('移动教务 token 已失效，刷新后重试');
      _authService.clearToken();
      token = await _authService.getToken(forceRefresh: true);
      weeks = await _fetchAllWeeks(token, onProgress);
    }

    onProgress?.call('正在整理课程数据…');
    final firstWeekMonday = weeks
        .map(YdjwxtJsonParser.extractFirstWeekMonday)
        .whereType<DateTime>()
        .firstOrNull;
    if (firstWeekMonday == null) {
      throw Exception('移动教务未返回本学期日期，暂时无法生成课表');
    }

    final courses = YdjwxtJsonParser.mergeWeeks(
      weeks.map(YdjwxtJsonParser.parseWeekJson),
    );
    if (courses.isEmpty) {
      throw Exception('当前学期未获取到课程，请确认移动教务中已有课表');
    }

    final semester = await _fetchCurrentSemester(token);
    final icsContent = IcsGenerator.generate(courses, firstWeekMonday);
    final storage = TimetableStorage();
    final backup = await _TimetableBackup.capture(storage);

    onProgress?.call('正在保存课表…');
    try {
      await storage.saveTimetable(icsContent);
      await storage.saveCourseList(courses);
      // A fresh remote timetable is a new baseline; old temporary overrides
      // could point at stale course ids or weeks.
      await storage.deleteAdjustments();
      await storage.saveMetadata(
        semester: semester,
        firstWeekMonday: firstWeekMonday,
      );
    } catch (_) {
      await backup.restore(storage);
      rethrow;
    }

    try {
      await CourseNotificationService.instance.rescheduleIfEnabled();
    } catch (e) {
      // 课表已经完整保存，通知重排失败不应让用户误以为同步失败。
      _logger.w('课表同步成功，但课程通知重排失败: $e');
    }

    onProgress?.call('同步完成');
    return TimetableSyncResult(
      courses: courses,
      firstWeekMonday: firstWeekMonday,
      semester: semester,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllWeeks(
    String token,
    void Function(String progress)? onProgress,
  ) async {
    onProgress?.call('正在获取当前学期课表…');
    return Future.wait(
      List.generate(20, (index) => _fetchWeek(index + 1, token)),
    );
  }

  Future<Map<String, dynamic>> _fetchWeek(int week, String token) async {
    try {
      final response = await DioClient().dio.post(
        AppConstants.ydjwxtTimetableUrl,
        queryParameters: {'week': week, 'kbjcmsid': ''},
        options: _apiOptions(token),
      );
      final body = _decodeMap(response.data);

      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          _isAuthError(body)) {
        throw const _YdjwxtAuthException();
      }
      if (response.statusCode == 200 && _isSuccess(body)) return body!;

      final message = body?['Msg']?.toString() ??
          body?['msg']?.toString() ??
          'HTTP ${response.statusCode}';
      throw Exception('获取第 $week 周课表失败：$message');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const _YdjwxtAuthException();
      }
      throw Exception('获取第 $week 周课表失败：${e.message}');
    }
  }

  Future<String> _fetchCurrentSemester(String token) async {
    try {
      final response = await DioClient().dio.post(
        AppConstants.ydjwxtSemesterListUrl,
        options: _apiOptions(token),
      );
      final body = _decodeMap(response.data);
      final rawList = body?['data'];
      if (response.statusCode == 200 && _isSuccess(body) && rawList is List) {
        Map<dynamic, dynamic>? active;
        for (final item in rawList.whereType<Map>()) {
          if (item['isdqxq']?.toString() == '1') {
            active = item;
            break;
          }
        }
        active ??= rawList.whereType<Map>().firstOrNull;
        final id = active?['semesterId']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    } catch (e) {
      _logger.w('未能读取当前学期标识，将根据日期生成: $e');
    }
    return _semesterFromDate(DateTime.now());
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
      } catch (_) {}
    }
    return null;
  }

  bool _isSuccess(Map<String, dynamic>? body) =>
      body?['code']?.toString() == '1';

  bool _isAuthError(Map<String, dynamic>? body) {
    if (body == null) return false;
    final code = body['code']?.toString();
    final message =
        body['Msg']?.toString() ?? body['msg']?.toString() ?? '';
    return code == '401' ||
        code == '-1' ||
        message.contains('登录') ||
        message.contains('失效') ||
        message.toLowerCase().contains('token');
  }

  String _semesterFromDate(DateTime date) {
    if (date.month >= 7) return '${date.year}-${date.year + 1}-1';
    return '${date.year - 1}-${date.year}-2';
  }
}

class _YdjwxtAuthException implements Exception {
  const _YdjwxtAuthException();
}

class _TimetableBackup {
  const _TimetableBackup({this.ics, this.metadata, required this.courses, required this.adjustments});

  final String? ics;
  final Map<String, dynamic>? metadata;
  final List<CourseModel> courses;
  final List<TimetableAdjustment> adjustments;

  static Future<_TimetableBackup> capture(TimetableStorage storage) async {
    return _TimetableBackup(
      ics: await storage.readTimetable(),
      metadata: await storage.readMetadata(),
      courses: await storage.readCourseList(),
      adjustments: await storage.readAdjustments(),
    );
  }

  Future<void> restore(TimetableStorage storage) async {
    try {
      if (ics == null) {
        await storage.deleteTimetable();
      } else {
        await storage.saveTimetable(ics!);
      }

      final semester = metadata?['semester'];
      final firstMonday = metadata?['firstWeekMonday'];
      if (semester is String && firstMonday is String) {
        await storage.saveMetadata(
          semester: semester,
          firstWeekMonday: DateTime.parse(firstMonday),
        );
      } else {
        await storage.deleteMetadata();
      }

      if (courses.isEmpty) {
        await storage.deleteCourseList();
      } else {
        await storage.saveCourseList(courses);
      }

      await storage.saveAdjustments(adjustments);
    } catch (e) {
      AppLogger.instance.e('恢复旧课表失败: $e');
    }
  }
}
