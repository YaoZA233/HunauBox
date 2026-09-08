import 'package:flutter/material.dart';

import 'empty_classroom_page.dart';
import 'campus_card_recharge_page.dart';
import 'campus_card_webview_page.dart';
import 'payment_code_page.dart';
import 'electricity_recharge_page.dart';
import 'network_speed_test_page.dart';
import 'xgxt_webview_page.dart';
import 'timetable_page.dart';
import 'vpn_converter_page.dart';
import 'score_page.dart';
import 'webview_detail_page.dart';
import 'bus_tracking_page.dart';
import 'dorm_service_page.dart';
import '../models/app_constants.dart';
import '../services/auth_guard.dart';

class FunctionPage extends StatelessWidget {
  const FunctionPage({super.key});

  Future<void> _openProtectedPage(BuildContext context, Widget page) async {
    final result = await AuthGuard.ensureLoggedIn(context);
    if (!result.allowed || !context.mounted) return;

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('功能')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '全部功能',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '校园服务、教务与生活工具',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildCategorySection('校卡服务', [
                _FunctionItem(
                  Icons.qr_code_scanner_outlined,
                  '校园卡付款码',
                  '出示付款二维码消费',
                  onTap: () {
                    _openProtectedPage(context, const PaymentCodePage());
                  },
                ),
                _FunctionItem(
                  Icons.add_card_outlined,
                  '校园卡充值',
                  '校园卡在线充值',
                  onTap: () {
                    _openProtectedPage(context, const CampusCardRechargePage());
                  },
                ),
                _FunctionItem(
                  Icons.bolt_outlined,
                  '电费充值',
                  '寝室电费在线充值',
                  onTap: () {
                    _openProtectedPage(
                      context,
                      const ElectricityRechargePage(),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.credit_card_outlined,
                  '校园卡',
                  '查看校园卡信息',
                  onTap: () {
                    _openProtectedPage(context, const CampusCardWebViewPage());
                  },
                ),
                _FunctionItem(
                  Icons.report_problem_outlined,
                  '校园卡挂失登记',
                  '校园卡遗失后在线登记挂失',
                  requiresLogin: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '校园卡挂失登记',
                          url: AppConstants.campusCardLossUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
              ]),
              _buildCategorySection('学习教务', [
                _FunctionItem(
                  Icons.meeting_room_outlined,
                  '空教室',
                  '实时查找空闲教室',
                  onTap: () {
                    _openProtectedPage(context, const EmptyClassroomPage());
                  },
                ),
                _FunctionItem(
                  Icons.connect_without_contact_outlined,
                  '学工系统',
                  '进入学工系统',
                  onTap: () {
                    _openProtectedPage(context, const XgxtWebViewPage());
                  },
                ),
                _FunctionItem(
                  Icons.rate_review_outlined,
                  '教学评价平台',
                  '查看并完成待评价任务',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WebViewDetailPage(
                          title: '教学评价平台',
                          url: AppConstants.teachingEvalUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.workspace_premium_outlined,
                  '成绩查询',
                  '查看课程成绩',
                  onTap: () {
                    _openProtectedPage(context, const ScorePage());
                  },
                ),
                _FunctionItem(
                  Icons.auto_stories_outlined,
                  '课程表',
                  '查看本学期课表',
                  onTap: () {
                    _openProtectedPage(context, const TimetablePage());
                  },
                ),
                _FunctionItem(
                  Icons.calendar_month_outlined,
                  '电子校历',
                  '查看学校校历安排',
                  requiresLogin: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '电子校历',
                          url: AppConstants.schoolCalendarUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.library_books_outlined,
                  '图书荐购',
                  '提交图书采购推荐',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '图书荐购',
                          url: AppConstants.bookRecommendationUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.auto_awesome_outlined,
                  '湖南农业大学DeepSeek大模型',
                  '使用学校提供的 DeepSeek 智能问答服务',
                  requiresLogin: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '湖南农业大学DeepSeek大模型',
                          url: AppConstants.deepSeekUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
              ]),
              _buildCategorySection('校园生活', [
                _FunctionItem(
                  Icons.airport_shuttle_outlined,
                  '实时校车',
                  '基于定位打开校车追踪',
                  onTap: () {
                    _openProtectedPage(context, const BusTrackingPage());
                  },
                ),
                _FunctionItem(
                  Icons.build_circle_outlined,
                  '报修平台',
                  '提交校园报修工单',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '报修平台',
                          url: AppConstants.repairsSsoUrl,
                          userAgent:
                              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36',
                          showWebBack: true,
                          targetUrl: '/relax/mobile/index.html',
                        ),
                      ),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.event_seat_outlined,
                  '场馆预约',
                  '预约场馆资源',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '场馆预约',
                          url: AppConstants.gymReservationUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.apartment_outlined,
                  '学生公寓',
                  '查看宿舍楼、楼层、房间和床号',
                  onTap: () {
                    _openProtectedPage(context, const DormServicePage());
                  },
                ),
                _FunctionItem(
                  Icons.local_activity_outlined,
                  '通识教育大讲堂',
                  '查看并参与通识讲堂活动',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '通识教育大讲堂',
                          url: AppConstants.lecturesUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.celebration_outlined,
                  '活动广场',
                  '查看校园活动与报名信息',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WebViewDetailPage(
                          title: '活动广场',
                          url: AppConstants.activitySquareUrl,
                          showWebBack: true,
                        ),
                      ),
                    );
                  },
                ),
              ]),
              _buildCategorySection('网络工具', [
                _FunctionItem(
                  Icons.vpn_lock_outlined,
                  'VPN转换',
                  '校园网接入与转换',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const VpnConverterPage(),
                      ),
                    );
                  },
                ),
                _FunctionItem(
                  Icons.speed_outlined,
                  '测速工具',
                  '检测当前网络速度',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NetworkSpeedTestPage(),
                      ),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String title, List<_FunctionItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Builder(
            builder: (context) {
              return Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Builder(
            builder: (context) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return _buildListTile(
                      item,
                      isLast: index == items.length - 1,
                      context: context,
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildListTile(
    _FunctionItem item, {
    required bool isLast,
    required BuildContext context,
  }) {
    return InkWell(
      onTap: () async {
        if (item.requiresLogin) {
          final result = await AuthGuard.ensureLoggedIn(context);
          if (!result.allowed || !context.mounted) return;
        }

        item.onTap?.call();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  item.icon,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _FunctionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool requiresLogin;

  _FunctionItem(
    this.icon,
    this.title,
    this.subtitle, {
    this.onTap,
    this.requiresLogin = true,
  });
}
