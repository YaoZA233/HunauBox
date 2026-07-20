import 'package:flutter/material.dart';

class QuickActionItem {
  final String id;
  final String label;
  final IconData icon;

  const QuickActionItem({
    required this.id,
    required this.label,
    required this.icon,
  });
}

class QuickActionCatalog {
  static const items = <QuickActionItem>[
    QuickActionItem(
      id: 'campus_card_recharge',
      label: '校园卡充值',
      icon: Icons.add_card_outlined,
    ),
    QuickActionItem(
      id: 'ele_recharge',
      label: '电费充值',
      icon: Icons.bolt_outlined,
    ),
    QuickActionItem(
      id: 'campus_card',
      label: '校园卡',
      icon: Icons.credit_card_outlined,
    ),
    QuickActionItem(
      id: 'empty_classroom',
      label: '空教室',
      icon: Icons.meeting_room_outlined,
    ),
    QuickActionItem(
      id: 'xgxt',
      label: '学工系统',
      icon: Icons.connect_without_contact_outlined,
    ),
    QuickActionItem(
      id: 'teaching_eval',
      label: '教学评价平台',
      icon: Icons.rate_review_outlined,
    ),
    QuickActionItem(
      id: 'score',
      label: '成绩查询',
      icon: Icons.workspace_premium_outlined,
    ),
    QuickActionItem(
      id: 'timetable',
      label: '课程表',
      icon: Icons.auto_stories_outlined,
    ),
    QuickActionItem(
      id: 'repair',
      label: '报修平台',
      icon: Icons.build_circle_outlined,
    ),
    QuickActionItem(id: 'gym', label: '场馆预约', icon: Icons.event_seat_outlined),
    QuickActionItem(
      id: 'dorm_service',
      label: '学生公寓',
      icon: Icons.apartment_outlined,
    ),
    QuickActionItem(
      id: 'lecture_hall',
      label: '通识讲堂',
      icon: Icons.local_activity_outlined,
    ),
    QuickActionItem(
      id: 'activity_square',
      label: '活动广场',
      icon: Icons.celebration_outlined,
    ),
    QuickActionItem(
      id: 'school_calendar',
      label: '电子校历',
      icon: Icons.calendar_month_outlined,
    ),
    QuickActionItem(
      id: 'book_recommend',
      label: '图书荐购',
      icon: Icons.library_books_outlined,
    ),
    QuickActionItem(id: 'vpn', label: 'VPN转换', icon: Icons.vpn_lock_outlined),
    QuickActionItem(
      id: 'speed_test',
      label: '测速工具',
      icon: Icons.speed_outlined,
    ),
    QuickActionItem(
      id: 'bus',
      label: '实时校车',
      icon: Icons.airport_shuttle_outlined,
    ),
  ];

  static const defaultIds = <String>[
    'campus_card',
    'campus_card_recharge',
    'ele_recharge',
    'empty_classroom',
    'xgxt',
    'score',
    'timetable',
    'repair',
    'bus',
  ];

  static QuickActionItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
