import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ics_parser.dart';
import 'course_schedule_service.dart';
import 'timetable_storage.dart';
import 'homework_storage.dart';
import '../models/homework_model.dart';
import 'course_notification_settings_store.dart';

/// 统一胶囊通知服务
///
/// 支持多种通知类型：
/// - 课程：上课提醒、教室位置、进度展示
/// - 作业：截止时间、倒计时、紧急提醒
/// - 消息：校园通知、重要消息
/// - 考试：考试提醒、考场信息
/// - 活动：活动提醒、地点时间
class UnifiedCapsuleService {
  UnifiedCapsuleService._();
  static final instance = UnifiedCapsuleService._();
  static const channel = MethodChannel('hunaubox/unified_capsule');

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 通知类型
  static const typesCourse = 'course';
  static const typesHomework = 'homework';
  static const typesMessage = 'message';
  static const typesExam = 'exam';
  static const typesActivity = 'activity';

  /// 获取设备能力信息
  Future<Map<String, dynamic>> capabilities() async {
    if (!supported) return {'supported': false};
    return Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('capabilities') ?? {},
    );
  }

  /// 配置胶囊通知
  Future<void> configure({
    required Set<String> enabledTypes,
    List<CourseData>? courses,
    List<HomeworkData>? homework,
    List<MessageData>? messages,
    List<ExamData>? exams,
    List<ActivityData>? activities,
  }) async {
    if (!supported) return;
    final effectiveTypes = await _effectiveEnabledTypes(enabledTypes);

    await channel.invokeMethod<void>('configure', {
      'enabledTypes': effectiveTypes.toList(),
      'courses': courses?.map((e) => e.toMap()).toList() ?? [],
      'homework': homework?.map((e) => e.toMap()).toList() ?? [],
      'messages': messages?.map((e) => e.toMap()).toList() ?? [],
      'exams': exams?.map((e) => e.toMap()).toList() ?? [],
      'activities': activities?.map((e) => e.toMap()).toList() ?? [],
    });
  }

  /// 刷新通知
  Future<void> refresh() async {
    if (!supported) return;
    await channel.invokeMethod<void>('refresh');
  }

  Future<void> patch({
    Set<String>? enabledTypes,
    List<CourseData>? courses,
    List<HomeworkData>? homework,
    List<MessageData>? messages,
    List<ExamData>? exams,
    List<ActivityData>? activities,
  }) async {
    if (!supported) return;
    final data = <String, dynamic>{};
    if (enabledTypes != null) {
      data['enabledTypes'] = (await _effectiveEnabledTypes(
        enabledTypes,
      )).toList();
    }
    if (courses != null) {
      data['courses'] = courses.map((e) => e.toMap()).toList();
    }
    if (homework != null) {
      data['homework'] = homework.map((e) => e.toMap()).toList();
    }
    if (messages != null) {
      data['messages'] = messages.map((e) => e.toMap()).toList();
    }
    if (exams != null) data['exams'] = exams.map((e) => e.toMap()).toList();
    if (activities != null) {
      data['activities'] = activities.map((e) => e.toMap()).toList();
    }
    await channel.invokeMethod<void>('patch', data);
  }

  Future<void> syncLocal() async {
    if (!supported) return;
    final enabled = await loadEnabledTypes();
    final timetable = TimetableStorage();
    final metadata = await timetable.readMetadata();
    final monday = DateTime.tryParse('${metadata?['firstWeekMonday']}');
    final ics = await timetable.readTimetable();
    final occurrences = monday == null || ics == null
        ? const <CourseOccurrence>[]
        : CourseScheduleService.upcomingOccurrences(
            courses: IcsParser.parse(ics),
            firstWeekMonday: monday,
            from: DateTime.now(),
            adjustments: await timetable.readAdjustments(),
          );
    final homework =
        await HomeworkStorage().readHomeworkList() ?? const <HomeworkModel>[];
    await configure(
      enabledTypes: enabled,
      courses: occurrences
          .map(
            (item) => CourseData(
              id: '${item.course.id}:${item.start.millisecondsSinceEpoch}',
              name: item.course.name,
              room: item.course.classroom.trim().isEmpty
                  ? '教室待定'
                  : item.course.classroom,
              start: item.start.millisecondsSinceEpoch,
              end: item.end.millisecondsSinceEpoch,
              periods:
                  '第 ${item.course.startPeriod}–${item.course.endPeriod} 节',
            ),
          )
          .toList(),
      homework: homework
          .where(
            (item) =>
                item.status == HomeworkStatus.pending && item.endTime != null,
          )
          .map(
            (item) => HomeworkData(
              id: item.id,
              title: item.title,
              course: item.courseName,
              deadline: item.endTime!.millisecondsSinceEpoch,
            ),
          )
          .toList(),
    );
  }

  /// 取消所有通知
  Future<void> cancelAll() async {
    if (!supported) return;
    await channel.invokeMethod<void>('cancelAll');
  }

  /// 保存启用的类型到本地
  Future<void> saveEnabledTypes(Set<String> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('capsule_enabled_types', types.toList());
  }

  /// 读取启用的类型
  Future<Set<String>> loadEnabledTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('capsule_enabled_types');
    final configured = list?.toSet() ?? {typesCourse, typesHomework};
    final effective = await _effectiveEnabledTypes(configured);
    if (!setEquals(configured, effective)) {
      await prefs.setStringList('capsule_enabled_types', effective.toList());
    }
    return effective;
  }

  Future<Set<String>> _effectiveEnabledTypes(Set<String> configured) async {
    final store = CourseNotificationSettingsStore.instance;
    await store.load();
    return resolveEffectiveEnabledTypes(configured, store.settings.value);
  }

  @visibleForTesting
  static Set<String> resolveEffectiveEnabledTypes(
    Set<String> configured,
    CourseNotificationSettings settings,
  ) {
    final types = Set<String>.from(configured);
    if (settings.messageEnabled) types.remove(typesMessage);
    if (settings.homeworkEnabled || settings.homeworkDeadlineEnabled) {
      types.remove(typesHomework);
    }
    return types;
  }

  /// 获取类型显示名称
  String getTypeName(String type) {
    switch (type) {
      case typesCourse:
        return '课程提醒';
      case typesHomework:
        return '作业提醒';
      case typesMessage:
        return '校园通知';
      case typesExam:
        return '考试提醒';
      case typesActivity:
        return '活动提醒';
      default:
        return type;
    }
  }

  /// 获取类型图标
  String getTypeIcon(String type) {
    switch (type) {
      case typesCourse:
        return '📚';
      case typesHomework:
        return '✍️';
      case typesMessage:
        return '📬';
      case typesExam:
        return '📝';
      case typesActivity:
        return '🎉';
      default:
        return '🔔';
    }
  }

  /// 获取类型描述
  String getTypeDescription(String type) {
    switch (type) {
      case typesCourse:
        return '显示课程信息、上课地点、时间和进度';
      case typesHomework:
        return '显示作业截止时间和倒计时，紧急提醒';
      case typesMessage:
        return '显示校园通知、重要消息和公告';
      case typesExam:
        return '显示考试信息、考场位置和倒计时';
      case typesActivity:
        return '显示校园活动、讲座和社团通知';
      default:
        return '';
    }
  }
}

/// 课程数据
class CourseData {
  final String id;
  final String name;
  final String room;
  final int start; // 毫秒时间戳
  final int end; // 毫秒时间戳
  final String periods;

  CourseData({
    required this.id,
    required this.name,
    required this.room,
    required this.start,
    required this.end,
    required this.periods,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'room': room,
    'start': start,
    'end': end,
    'periods': periods,
  };
}

/// 作业数据
class HomeworkData {
  final String id;
  final String title;
  final String course;
  final int deadline; // 毫秒时间戳

  HomeworkData({
    required this.id,
    required this.title,
    required this.course,
    required this.deadline,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'course': course,
    'deadline': deadline,
  };
}

/// 消息数据
class MessageData {
  final String id;
  final String title;
  final String sender;
  final String content;
  final int time; // 毫秒时间戳
  final String priority; // normal, important, urgent
  final bool read;

  MessageData({
    required this.id,
    required this.title,
    required this.sender,
    required this.content,
    required this.time,
    this.priority = 'normal',
    this.read = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'sender': sender,
    'content': content,
    'time': time,
    'priority': priority,
    'read': read,
  };
}

/// 考试数据
class ExamData {
  final String id;
  final String subject;
  final String location;
  final int time; // 毫秒时间戳
  final bool important;

  ExamData({
    required this.id,
    required this.subject,
    required this.location,
    required this.time,
    this.important = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subject': subject,
    'location': location,
    'time': time,
    'important': important,
  };
}

/// 活动数据
class ActivityData {
  final String id;
  final String name;
  final String location;
  final int time; // 毫秒时间戳
  final bool important;

  ActivityData({
    required this.id,
    required this.name,
    required this.location,
    required this.time,
    this.important = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'location': location,
    'time': time,
    'important': important,
  };
}
