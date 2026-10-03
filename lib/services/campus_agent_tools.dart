import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course_model.dart';
import '../models/homework_model.dart';
import '../models/score_model.dart';
import '../models/timetable_adjustment.dart';
import '../models/agent_models.dart';
import '../providers/homework_provider.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';
import 'agent_tool_registry.dart';
import 'app_cookie_manager.dart';
import 'auth_guard.dart';
import 'campus_card_service.dart';
import 'classroom_service.dart';
import 'electricity_service.dart';
import 'notice_service.dart';
import 'questionnaire_service.dart';
import 'score_service.dart';
import 'secure_storage_helper.dart';
import 'timetable_service.dart';
import 'timetable_storage.dart';
import 'sunshine_service.dart';
import 'leave_service.dart';
import 'repair_service.dart';

const agentServiceLabels = <String, String>{
  'timetable': '课表',
  'homework': '作业',
  'notice': '通知',
  'scores': '成绩',
  'classroom': '空教室',
  'campus_card': '校园卡充值',
  'electricity': '电费充值',
  'questionnaire': '学工问卷',
  'sunshine': '阳光服务',
  'leave': '请假申请',
  'repair': '报修平台',
};

String agentClassroomSectionCode(int section) {
  if (section < 1 || section > 6) throw const AgentException('大节必须在 1–6 之间');
  return '${(section * 2 - 1).toString().padLeft(2, '0')}${(section * 2).toString().padLeft(2, '0')}';
}

DateTime parseAgentDeadline(String value) {
  final date = DateTime.tryParse(value);
  if (date == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(value) ||
      date.toIso8601String().substring(0, 19).replaceFirst('T', ' ') != value) {
    throw const AgentException('截止时间必须是有效的 YYYY-MM-DD HH:mm:ss');
  }
  return date;
}

List<CourseModel> filterAgentCourses(
  List<CourseModel> courses,
  Map<String, dynamic> args, {
  required DateTime now,
  DateTime? firstWeekMonday,
}) {
  final today = args['today'] == true;
  final week = today
      ? (firstWeekMonday == null
            ? null
            : DateCalculator.getCurrentWeekNumber(firstWeekMonday, now))
      : args['week'] as int?;
  if (today && week == null) {
    throw const AgentException('课表缺少学期起始日期，请先同步课表，不能准确判断今日课程');
  }
  final day = today ? now.weekday : args['dayOfWeek'] as int?;
  final keyword = (args['courseName'] as String? ?? '').trim().toLowerCase();
  final list = courses
      .where(
        (c) =>
            (day == null || day == c.dayOfWeek) &&
            (week == null || WeekParser.parseWeeks(c.weeks).contains(week)) &&
            (keyword.isEmpty ||
                '${c.name} ${c.teacher} ${c.classroom}'.toLowerCase().contains(
                  keyword,
                )),
      )
      .toList();
  list.sort(
    (a, b) => a.dayOfWeek != b.dayOfWeek
        ? a.dayOfWeek.compareTo(b.dayOfWeek)
        : a.startPeriod.compareTo(b.startPeriod),
  );
  return list;
}

/// 只注册当前项目已有能力；不移植参考仓库的默认代理、Key 或未实现接口。
AgentToolRegistry buildCampusAgentTools(
  WidgetRef ref, {
  required Future<void> Function(String) openService,
  Future<bool> Function()? isLoggedIn,
}) {
  const str = {'type': 'string'};
  const boolean = {'type': 'boolean'};
  final tools = <AgentTool>[];
  void add(
    String name,
    String label,
    String description,
    Future<Object?> Function(Map<String, dynamic>, AgentToolContext) run, {
    Map<String, dynamic> properties = const {},
    List<String> required = const [],
  }) {
    tools.add(
      AgentTool(
        name: name,
        label: label,
        description: description,
        properties: properties,
        requiredFields: required,
        run: (args, ctx) async {
          if (!await (isLoggedIn?.call() ?? AuthGuard.hasSavedCredentials())) {
            throw const AgentException('请先点击右上角头像登录校园账号，再查询校园数据');
          }
          ctx.checkActive();
          return run(args, ctx);
        },
      ),
    );
  }

  add(
    'query_timetable',
    '查询课表',
    '查询本地课表，支持今日、周次、星期、课程关键词；没有数据时提醒同步。',
    (a, ctx) async {
      if (a['forceRefresh'] == true) {
        await TimetableService().downloadAndSaveTimetable();
      }
      ctx.checkActive();
      final storage = TimetableStorage();
      final courses = await storage.readCourseList();
      final meta = await storage.readMetadata();
      if (courses.isEmpty) return {'message': '本地暂无课表，请在课表页面同步当前学期'};
      final filtered = filterAgentCourses(
        courses,
        a,
        now: DateTime.now(),
        firstWeekMonday: DateTime.tryParse(
          meta?['firstWeekMonday']?.toString() ?? '',
        ),
      );
      final adjustments = await storage.readAdjustments();
      final requestedWeek = a['today'] == true
          ? DateCalculator.getCurrentWeekNumber(
              DateTime.tryParse(meta?['firstWeekMonday']?.toString() ?? '')!,
            )
          : a['week'] as int?;
      final effective = <CourseModel>[...filtered];
      if (requestedWeek != null) {
        for (final adjustment in adjustments.where((item) => !item.cancelled && item.targetWeek == requestedWeek)) {
          final original = courses.where((course) => course.id == adjustment.courseId).firstOrNull;
          if (original == null) continue;
          if (adjustment.sourceWeek == requestedWeek) {
            effective.removeWhere((course) => course.id == original.id);
          }
          effective.add(original.copyWith(dayOfWeek: adjustment.targetDay, startPeriod: adjustment.targetStartPeriod, endPeriod: adjustment.targetEndPeriod, periods: '${adjustment.targetStartPeriod}-${adjustment.targetEndPeriod}'));
        }
        effective.sort((a, b) => a.dayOfWeek != b.dayOfWeek ? a.dayOfWeek.compareTo(b.dayOfWeek) : a.startPeriod.compareTo(b.startPeriod));
      }
      return {
        'totalCount': filtered.length,
        'source': '本地课表',
        'savedAt': meta?['savedAt'],
        'currentWeek': meta?['firstWeekMonday'] == null
            ? null
            : DateCalculator.getCurrentWeekNumber(
                DateTime.tryParse(meta!['firstWeekMonday'].toString())!,
              ),
        'adjustments': adjustments
            .where((item) => filtered.any((course) => course.id == item.courseId))
            .map((item) => item.toJson())
            .toList(),
        'courses': filtered.take(100).map((c) => c.toJson()).toList(),
        'effectiveCourses': effective.take(100).map((c) => c.toJson()).toList(),
      };
    },
    properties: {
      'today': boolean,
      'week': {'type': 'integer', 'minimum': 1, 'maximum': 30},
      'dayOfWeek': {'type': 'integer', 'minimum': 1, 'maximum': 7},
      'courseName': str,
      'forceRefresh': boolean,
    },
  );

  add(
    'query_homework',
    '查询作业',
    '查询缓存作业；支持 pending/completed/archived/all，课程及标题关键词。',
    (a, ctx) async {
      if (a['forceRefresh'] == true) {
        await ref.read(homeworkProvider.notifier).refresh();
        ctx.checkActive();
        if (ref.read(homeworkProvider).hasError) {
          throw const AgentException('作业刷新失败，请在作业页面重试');
        }
      }
      final list =
          await ref.read(homeworkStorageProvider).readHomeworkList() ?? [];
      final status = a['status'] ?? 'pending';
      final keyword = (a['keyword'] as String? ?? '').toLowerCase();
      final course = (a['courseName'] as String? ?? '').toLowerCase();
      final filtered = list
          .where(
            (h) =>
                (status == 'all' || h.status.name == status) &&
                h.courseName.toLowerCase().contains(course) &&
                '${h.title} ${h.remarks}'.toLowerCase().contains(keyword),
          )
          .toList();
      filtered.sort(
        (a, b) => a.endTime == null
            ? (b.endTime == null ? 0 : 1)
            : b.endTime == null
            ? -1
            : a.endTime!.compareTo(b.endTime!),
      );
      return {
        'source': '本地缓存',
        'totalCount': filtered.length,
        'homeworkList': filtered
            .take(100)
            .map(
              (h) => {
                'id': h.id,
                'title': h.title,
                'courseName': h.courseName,
                'status': h.status.name,
                'endTime': h.endTime?.toIso8601String(),
                'isManual': h.isManual,
                'remarks': h.remarks,
              },
            )
            .toList(),
      };
    },
    properties: {
      'status': {
        'type': 'string',
        'enum': ['pending', 'completed', 'archived', 'all'],
      },
      'courseName': str,
      'keyword': str,
      'forceRefresh': boolean,
    },
  );

  add(
    'query_timetable_adjustments',
    '查询临时调课',
    '查询已经保存的临时调课和停课规则。返回原课程、源周次以及目标周次、星期和节次。',
    (a, ctx) async {
      final items = await TimetableStorage().readAdjustments();
      final courses = await TimetableStorage().readCourseList();
      final byId = {for (final course in courses) course.id: course};
      final keyword = (a['courseName'] as String? ?? '').trim().toLowerCase();
      final result = items.where((item) {
        final course = byId[item.courseId];
        return keyword.isEmpty ||
            (course != null && course.name.toLowerCase().contains(keyword));
      }).map((item) {
        final course = byId[item.courseId];
        return {
          'courseId': item.courseId,
          'courseName': course?.name ?? item.courseId,
          'sourceWeek': item.sourceWeek,
          'sourceDay': item.sourceDay,
          'targetWeek': item.targetWeek,
          'targetDay': item.targetDay,
          'targetStartPeriod': item.targetStartPeriod,
          'targetEndPeriod': item.targetEndPeriod,
          'cancelled': item.cancelled,
          'note': item.note,
        };
      }).toList();
      return {'totalCount': result.length, 'adjustments': result};
    },
    properties: {'courseName': str},
  );

  add(
    'adjust_timetable',
    'AI 调课',
    '保存一条临时调课或停课规则。必须先查询课表确认课程和源周次，再调用此工具。只修改本机临时安排，不改变教务原始课表；执行前必须让用户确认。星期使用 1=周一到 7=周日，节次使用实际小节编号。停课时 cancelled=true，目标位置仍需传入原课程位置。',
    (a, ctx) async {
      final courseName = (a['courseName'] as String).trim();
      final sourceWeek = a['sourceWeek'] as int;
      final sourceDay = a['sourceDay'] as int?;
      final targetWeek = a['targetWeek'] as int;
      final targetDay = a['targetDay'] as int;
      final targetStart = a['targetStartPeriod'] as int;
      final targetEnd = a['targetEndPeriod'] as int;
      final cancelled = a['cancelled'] == true;
      if (courseName.isEmpty) throw const AgentException('课程名称不能为空');
      if (targetEnd < targetStart) throw const AgentException('结束节次不能早于开始节次');
      if (sourceWeek < 1 || targetWeek < 1 || sourceDay == null || sourceDay < 1 || sourceDay > 7 || targetDay < 1 || targetDay > 7 || targetStart < 1 || targetEnd > 12) {
        throw const AgentException('周次、星期或节次超出有效范围');
      }
      final storage = TimetableStorage();
      final courses = await storage.readCourseList();
      final candidates = courses.where((course) {
        final sameName = course.name.toLowerCase().contains(courseName.toLowerCase());
        final inWeek = WeekParser.parseWeeks(course.weeks).contains(sourceWeek);
        return sameName && inWeek && course.dayOfWeek == sourceDay;
      }).toList();
      if (candidates.isEmpty) throw const AgentException('没有找到符合课程名、源周次和星期的课程，请先查询课表确认参数');
      if (candidates.length > 1) {
        throw AgentException('匹配到多门课程：${candidates.take(5).map((e) => '${e.name}（周${e.dayOfWeek}第${e.periods}节）').join('、')}，请补充更完整的课程名称');
      }
      final course = candidates.single;
      final existing = await storage.readAdjustments();
      final conflicts = courses.where((other) {
        if (other.id == course.id) return false;
        if (!WeekParser.parseWeeks(other.weeks).contains(targetWeek)) return false;
        return other.dayOfWeek == targetDay && other.startPeriod <= targetEnd && other.endPeriod >= targetStart;
      }).map((e) => e.name).toSet().toList();
      final note = (a['note'] as String? ?? '').trim();
      final detail = StringBuffer()
        ..writeln('课程：${course.name}')
        ..writeln('原安排：第$sourceWeek周 星期$sourceDay 第${course.periods}节')
        ..writeln(cancelled ? '调整：本次停课' : '新安排：第$targetWeek周 星期$targetDay 第$targetStart-$targetEnd节')
        ..writeln(note.isEmpty ? '备注：无' : '备注：$note');
      if (conflicts.isNotEmpty) detail.writeln('提示：目标时段已有课程「${conflicts.join('、')}」，请确认是否继续。');
      if (!await ctx.askConfirmation('确认 AI 调课', detail.toString())) return {'cancelled': true, 'message': '用户取消，未修改课表'};
      ctx.checkActive();
      final adjustment = TimetableAdjustment(
        id: '${course.id}_$sourceWeek', courseId: course.id, sourceWeek: sourceWeek, sourceDay: course.dayOfWeek,
        targetWeek: targetWeek, targetDay: targetDay, targetStartPeriod: targetStart, targetEndPeriod: targetEnd, cancelled: cancelled, note: note,
      );
      final replaced = existing.where((item) => !(item.courseId == course.id && item.sourceWeek == sourceWeek)).toList()..add(adjustment);
      await storage.saveAdjustments(replaced);
      return {'success': true, 'courseName': course.name, 'cancelled': cancelled, 'sourceWeek': sourceWeek, 'targetWeek': targetWeek, 'targetDay': targetDay, 'targetStartPeriod': targetStart, 'targetEndPeriod': targetEnd, 'conflicts': conflicts};
    },
    properties: {
      'courseName': str,
      'sourceWeek': {'type': 'integer', 'minimum': 1, 'maximum': 30},
      'sourceDay': {'type': 'integer', 'minimum': 1, 'maximum': 7},
      'targetWeek': {'type': 'integer', 'minimum': 1, 'maximum': 30},
      'targetDay': {'type': 'integer', 'minimum': 1, 'maximum': 7},
      'targetStartPeriod': {'type': 'integer', 'minimum': 1, 'maximum': 12},
      'targetEndPeriod': {'type': 'integer', 'minimum': 1, 'maximum': 12},
      'cancelled': boolean,
      'note': str,
    },
    required: ['courseName', 'sourceWeek', 'sourceDay', 'targetWeek', 'targetDay', 'targetStartPeriod', 'targetEndPeriod'],
  );

  add(
    'restore_timetable_course',
    '恢复原课表',
    '删除指定课程某一源周次的临时调课或停课规则，恢复教务原始安排。执行前必须让用户确认。',
    (a, ctx) async {
      final name = (a['courseName'] as String).trim().toLowerCase();
      final week = a['sourceWeek'] as int;
      final day = a['sourceDay'] as int;
      final storage = TimetableStorage();
      final courses = await storage.readCourseList();
      final matches = courses.where((course) => course.name.toLowerCase().contains(name) && WeekParser.parseWeeks(course.weeks).contains(week) && course.dayOfWeek == day).toList();
      if (matches.length != 1) throw const AgentException('没有唯一匹配到需要恢复的课程，请先查询课表并补充课程名称、周次和星期');
      final course = matches.single;
      final existing = await storage.readAdjustments();
      final found = existing.where((item) => item.courseId == course.id && item.sourceWeek == week).toList();
      if (found.isEmpty) return {'message': '该课程没有保存的临时调课，无需恢复'};
      if (!await ctx.askConfirmation('恢复原课表', '将删除「${course.name}」第$week周星期$day的临时安排，恢复原始课表。')) return {'cancelled': true};
      ctx.checkActive();
      await storage.saveAdjustments(existing.where((item) => !(item.courseId == course.id && item.sourceWeek == week)).toList());
      return {'success': true, 'courseName': course.name, 'sourceWeek': week};
    },
    properties: {
      'courseName': str,
      'sourceWeek': {'type': 'integer', 'minimum': 1, 'maximum': 30},
      'sourceDay': {'type': 'integer', 'minimum': 1, 'maximum': 7},
    },
    required: ['courseName', 'sourceWeek', 'sourceDay'],
  );

  add(
    'add_homework',
    '添加手动作业',
    '新增手动作业，界面确认后保存。截止时间必须换算为绝对时间 YYYY-MM-DD HH:mm:ss。',
    (a, ctx) async {
      final title = (a['title'] as String).trim();
      if (title.isEmpty) throw const AgentException('作业标题不能为空');
      final deadline = a['endTime'] == null
          ? null
          : parseAgentDeadline(a['endTime'] as String);
      if (!await ctx.askConfirmation(
        '添加手动作业',
        '标题：$title\n课程：${a['courseName'] ?? '自定义作业'}\n截止：${a['endTime'] ?? '无'}\n备注：${a['remarks'] ?? '无'}',
      )) {
        return {'cancelled': true, 'message': '用户取消，未新增作业'};
      }
      final user = await SecureStorageHelper().getUsername() ?? '';
      ctx.checkActive();
      final item = HomeworkModel(
        id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        courseName: a['courseName'] as String? ?? '',
        endTime: deadline,
        status: HomeworkStatus.pending,
        studentId: user,
        isManual: true,
        createdAt: DateTime.now(),
        remarks: a['remarks'] as String? ?? '',
      );
      await ref
          .read(homeworkProvider.notifier)
          .addManualHomework(item, checkActive: ctx.checkActive);
      return {
        'success': true,
        'id': item.id,
        'title': title,
        'endTime': item.endTime?.toIso8601String(),
      };
    },
    properties: {
      'title': str,
      'endTime': str,
      'courseName': str,
      'remarks': str,
    },
    required: ['title'],
  );

  add(
    'complete_homework',
    '完成手动作业',
    '按 ID 将手动作业标记完成。学习通作业不可代交，界面确认后修改。',
    (a, ctx) async {
      final items =
          await ref.read(homeworkStorageProvider).readHomeworkList() ?? [];
      final matched = items.where((h) => h.id == a['id']).toList();
      if (matched.isEmpty) throw const AgentException('未找到对应作业，请重新查询');
      final item = matched.first;
      if (!item.isManual) throw const AgentException('学习通作业须前往学习通完成，不能在本地代交');
      if (item.status == HomeworkStatus.completed) {
        return {'message': '该手动作业已经完成，无需再次修改'};
      }
      if (!await ctx.askConfirmation('完成手动作业', '将「${item.title}」标记为已完成？')) {
        return {'cancelled': true};
      }
      await ref
          .read(homeworkProvider.notifier)
          .completeManualHomework(item.id, checkActive: ctx.checkActive);
      return {'success': true, 'id': item.id, 'title': item.title};
    },
    properties: {'id': str},
    required: ['id'],
  );

  add(
    'query_notice',
    '查询通知',
    '读取最近一页校园通知，可用标题关键词筛选，不会标记已读。',
    (a, ctx) async {
      await AppCookieManager().initialize();
      final result = await NoticeService().fetchMessageList();
      final key = (a['keyword'] as String? ?? '').toLowerCase();
      return {
        'hasMore': result.hasMore,
        'notices': result.messages
            .where((m) => m.title.toLowerCase().contains(key))
            .take(30)
            .map(
              (m) => {
                'title': m.title,
                'content': m.content.length > 1500
                    ? m.content.substring(0, 1500)
                    : m.content,
                'sender': m.createrName,
                'sendTime': m.sendTime,
                'isRead': m.isRead,
              },
            )
            .toList(),
      };
    },
    properties: {'keyword': str},
  );

  add(
    'query_scores',
    '查询成绩',
    '查询当前学期成绩，或提供教务 semesterId 查询指定学期。',
    (a, ctx) async {
      final result = await ScoreService.instance.fetchScores(
        xn: a['semesterId'] as String?,
      );
      return {
        'semesters': (result['semesters'] as List<SemesterModel>)
            .map((s) => {'semesterId': s.value, 'name': s.name})
            .toList(),
        'scores': (result['scores'] as List<ScoreModel>)
            .map(
              (s) => {
                'courseName': s.courseName,
                'score': s.score,
                'credit': s.credit,
              },
            )
            .toList(),
      };
    },
    properties: {'semesterId': str},
  );

  add('query_campus_card', '查询校园卡余额', '查询校园卡余额，只读，不创建充值订单。', (a, ctx) async {
    final info = await CampusCardService.instance.fetchRechargeInfo();
    return {'balance': info.balance, 'unit': '元'};
  });

  add(
    'query_electricity',
    '查询电费余额',
    '查询电费页面记住的宿舍余额；未选择宿舍时要求用户先在电费页面选择。不会充值扣款。',
    (a, ctx) async {
      final service = ElectricityService.instance;
      final room = await service.getSavedRoom();
      if (room == null) throw const AgentException('请先在电费页面选择并记住宿舍');
      final info = await service.getBalance(
        areaName: room.areaName,
        buildingName: room.buildingName,
        roomId: room.roomId,
        mertype: room.mertype,
      );
      return {
        'location': '${room.areaName} ${room.buildingName} ${room.roomName}',
        'balance': info.balance,
        'unit': '元',
      };
    },
  );

  add('query_questionnaires', '查询学工问卷', '查询学工问卷列表、待填或已提交状态，不提交答案。', (
    a,
    ctx,
  ) async {
    final list = await QuestionnaireService().fetchList();
    return {
      'questionnaires': list
          .take(60)
          .map(
            (q) => {
              'id': q.dm,
              'title': q.title,
              'status': q.statusLabel,
              'endTime': q.endTime,
            },
          )
          .toList(),
    };
  });

  add(
    'query_questionnaire_detail',
    '查询问卷题目',
    '根据问卷 ID 查询题目，不提供自动提交；填写请打开学工问卷页面。',
    (a, ctx) async {
      final service = QuestionnaireService();
      final list = await service.fetchList();
      final match = list.where((q) => q.dm == a['id']).toList();
      if (match.isEmpty) throw const AgentException('未找到问卷，请刷新列表');
      final detail = await service.fetchDetail(match.first);
      return {
        'title': detail.title,
        'canSubmit': detail.canSubmit,
        'questions': detail.questions
            .take(60)
            .map(
              (q) => {
                'title': q.title,
                'type': q.typeLabel,
                'required': q.required,
                'options': q.options.map((o) => o.name).toList(),
              },
            )
            .toList(),
      };
    },
    properties: {'id': str},
    required: ['id'],
  );

  add(
    'query_empty_classroom_options',
    '查询空教室选项',
    '查询学校支持的楼栋名称和空教室筛选条件。楼栋不明确时先调用此工具，让用户选择。',
    (a, ctx) async {
      final options = await ClassroomService.instance.fetchOptions();
      return {
        'buildings': options.buildings,
        'sections': options.sections,
        'weeks': options.weeks,
        'days': options.days,
      };
    },
  );

  add(
    'query_empty_classrooms',
    '查询空教室',
    '按楼栋、教学周、星期和大节查询空教室，必须明确所有条件。',
    (a, ctx) async {
      final list = await ClassroomService.instance.queryClassrooms(
        building: a['building'] as String,
        week: '${a['week']}',
        jc: agentClassroomSectionCode(a['section'] as int),
        day: '${a['dayOfWeek']}',
      );
      return {
        'classrooms': list
            .take(100)
            .map((c) => {'name': c.jsmc, 'seats': c.zws})
            .toList(),
      };
    },
    properties: {
      'building': str,
      'week': {'type': 'integer', 'minimum': 1, 'maximum': 30},
      'dayOfWeek': {'type': 'integer', 'minimum': 1, 'maximum': 7},
      'section': {'type': 'integer', 'minimum': 1, 'maximum': 6},
    },
    required: ['building', 'week', 'dayOfWeek', 'section'],
  );

  add(
    'query_sunshine',
    '查询阳光服务',
    '查询已提交的阳光服务诉求及办理状态，只读，不提交诉求。',
    (a, ctx) async {
      final items = await SunshineService().fetchLetters();
      final keyword = (a['keyword'] as String? ?? '').trim().toLowerCase();
      final filtered = items.where((item) => keyword.isEmpty || '${item.title} ${item.department} ${item.type}'.toLowerCase().contains(keyword));
      return {'totalCount': filtered.length, 'tickets': filtered.take(50).map((item) => {'id': item.id, 'title': item.title, 'department': item.department, 'type': item.type, 'date': item.date, 'status': item.statusLabel}).toList()};
    },
    properties: {'keyword': str},
  );

  add(
    'query_leave',
    '查询请假申请',
    '查询请假申请记录和审核状态，只读，不提交或撤销。',
    (a, ctx) async {
      final items = await LeaveService().fetchList();
      final keyword = (a['keyword'] as String? ?? '').trim().toLowerCase();
      final filtered = items.where((item) => keyword.isEmpty || '${item.typeName} ${item.reason} ${item.startTime} ${item.endTime}'.toLowerCase().contains(keyword));
      return {'totalCount': filtered.length, 'leaves': filtered.take(50).map((item) => {'id': item.id, 'type': item.typeName, 'startTime': item.startTime, 'endTime': item.endTime, 'duration': item.durationLabel, 'reason': item.reason, 'status': item.statusLabel}).toList()};
    },
    properties: {'keyword': str},
  );

  add(
    'query_repairs',
    '查询报修工单',
    '查询报修平台工单，只读，不创建或取消工单。',
    (a, ctx) async {
      final orders = await RepairService().fetchOrders(ongoing: a['ongoing'] != false);
      final keyword = (a['keyword'] as String? ?? '').trim().toLowerCase();
      final filtered = orders.where((item) => keyword.isEmpty || '${item.title} ${item.description} ${item.catalog} ${item.status}'.toLowerCase().contains(keyword));
      return {'totalCount': filtered.length, 'orders': filtered.take(50).map((item) => {'id': item.id, 'code': item.code, 'title': item.title, 'catalog': item.catalog, 'status': item.status, 'description': item.description, 'department': item.department}).toList()};
    },
    properties: {'ongoing': boolean, 'keyword': str},
  );

  add(
    'open_campus_service',
    '打开校园服务',
    '需要用户手动充值、填写问卷或操作原页面时使用。仅打开指定校园页面，不执行支付或提交。',
    (a, ctx) async {
      final page = a['service'] as String;
      if (!await ctx.askConfirmation(
        '打开${agentServiceLabels[page]}',
        '将进入原功能页面，由你核对并操作。Agent 不会代付或提交。',
      )) {
        return {'cancelled': true};
      }
      await openService(page);
      return {'opened': agentServiceLabels[page], 'message': '已打开页面，未代付、未提交'};
    },
    properties: {
      'service': {'type': 'string', 'enum': agentServiceLabels.keys.toList()},
    },
    required: ['service'],
  );
  return AgentToolRegistry(tools);
}
