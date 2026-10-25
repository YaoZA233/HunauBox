import 'package:flutter/material.dart';

import '../models/app_constants.dart';
import '../services/auth_guard.dart';
import '../widgets/app_ui_kit.dart';
import 'bus_tracking_page.dart';
import 'campus_card_bill_page.dart';
import 'campus_card_recharge_page.dart';
import 'campus_card_webview_page.dart';
import 'dorm_service_page.dart';
import 'electricity_recharge_page.dart';
import 'empty_classroom_page.dart';
import 'exam_page.dart';
import 'leave_page.dart';
import 'network_speed_test_page.dart';
import 'payment_code_page.dart';
import 'questionnaire_list_page.dart';
import 'repair_page.dart';
import 'score_page.dart';
import 'sunshine_page.dart';
import 'timetable_page.dart';
import 'vpn_converter_page.dart';
import 'webview_detail_page.dart';
import 'xgxt_webview_page.dart';

class FunctionPage extends StatelessWidget {
  const FunctionPage({super.key});

  Future<void> _openProtected(BuildContext context, Widget page) async {
    final result = await AuthGuard.ensureLoggedIn(context);
    if (!result.allowed || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('功能')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务与工具',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '全部功能',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                  ),
                ],
              ),
            ),
          ),

          // ── 校卡与生活服务 ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppCellGroup(
              title: '校卡与生活服务',
              cells: [
                AppCell(
                  icon: Icons.receipt_long_outlined,
                  title: '校园卡账单',
                  subtitle: '查询消费、充值、补助与转账记录',
                  onTap: () => _openProtected(context, const CampusCardBillPage()),
                ),
                AppCell(
                  icon: Icons.qr_code_scanner_outlined,
                  title: '校园卡付款码',
                  subtitle: '出示付款二维码直接消费',
                  onTap: () => _openProtected(context, const PaymentCodePage()),
                ),
                AppCell(
                  icon: Icons.add_card_outlined,
                  title: '校园卡充值',
                  subtitle: '校园一卡通在线充值服务',
                  onTap: () => _openProtected(context, const CampusCardRechargePage()),
                ),
                AppCell(
                  icon: Icons.bolt_outlined,
                  title: '电费充值',
                  subtitle: '寝室电费实时查询与快捷缴费',
                  onTap: () => _openProtected(context, const ElectricityRechargePage()),
                ),
                AppCell(
                  icon: Icons.credit_card_outlined,
                  title: '校园卡服务',
                  subtitle: '一卡通管理、挂失与流水查询',
                  onTap: () => _openProtected(context, const CampusCardWebViewPage()),
                ),
                AppCell(
                  icon: Icons.report_problem_outlined,
                  title: '校园卡挂失',
                  subtitle: '快速办理校园卡挂失登记',
                  onTap: () => _openProtected(
                    context,
                    const WebViewDetailPage(
                      title: '校园卡挂失登记',
                      url: AppConstants.campusCardLossUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
                AppCell(
                  icon: Icons.airport_shuttle_outlined,
                  title: '实时校车',
                  subtitle: '校内通勤车辆实时动态与班次时刻',
                  onTap: () => _openPage(context, const BusTrackingPage()),
                ),
              ],
            ),
          ),

          // ── 教务与学业 ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppCellGroup(
              title: '教务与学业',
              cells: [
                AppCell(
                  icon: Icons.calendar_month_outlined,
                  title: '课表查询',
                  subtitle: '学期课程时间与教室安排',
                  onTap: () => _openProtected(context, const TimetablePage()),
                ),
                AppCell(
                  icon: Icons.workspace_premium_outlined,
                  title: '成绩查询',
                  subtitle: '学期期末成绩与绩点分析',
                  onTap: () => _openProtected(context, const ScorePage()),
                ),
                AppCell(
                  icon: Icons.event_note_outlined,
                  title: '考试安排',
                  subtitle: '期末考场、座号与时间安排',
                  onTap: () => _openProtected(context, const ExamPage()),
                ),
                AppCell(
                  icon: Icons.meeting_room_outlined,
                  title: '空教室查询',
                  subtitle: '自习、研讨空闲教学场地检索',
                  onTap: () => _openProtected(context, const EmptyClassroomPage()),
                ),
                AppCell(
                  icon: Icons.rate_review_outlined,
                  title: '教学评价平台',
                  subtitle: '学期课程与任课教师线上评教',
                  onTap: () => _openProtected(
                    context,
                    WebViewDetailPage(
                      title: '教学评价平台',
                      url: AppConstants.teachingEvalUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
                AppCell(
                  icon: Icons.calendar_today_outlined,
                  title: '电子校历',
                  subtitle: '学校学年学期时间进度表',
                  onTap: () => _openPage(
                    context,
                    const WebViewDetailPage(
                      title: '电子校历',
                      url: AppConstants.schoolCalendarUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 学生工作与宿舍 ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppCellGroup(
              title: '学生工作与事务',
              cells: [
                AppCell(
                  icon: Icons.connect_without_contact_outlined,
                  title: '学工系统',
                  subtitle: '学工一体化业务办理门户',
                  onTap: () => _openProtected(context, const XgxtWebViewPage()),
                ),
                AppCell(
                  icon: Icons.fact_check_outlined,
                  title: '学工问卷',
                  subtitle: '调查问卷填写与信息采集',
                  onTap: () => _openProtected(context, const QuestionnaireListPage()),
                ),
                AppCell(
                  icon: Icons.wb_sunny_outlined,
                  title: '阳光校园',
                  subtitle: '阳光心理、咨询与服务',
                  onTap: () => _openProtected(context, const SunshinePage()),
                ),
                AppCell(
                  icon: Icons.assignment_return_outlined,
                  title: '请假审批',
                  subtitle: '节假日与事假离校出校申请',
                  onTap: () => _openProtected(context, const LeavePage()),
                ),
                AppCell(
                  icon: Icons.apartment_outlined,
                  title: '学生公寓',
                  subtitle: '宿舍分配、调整与公寓综合服务',
                  onTap: () => _openProtected(context, const DormServicePage()),
                ),
                AppCell(
                  icon: Icons.build_circle_outlined,
                  title: '后勤报修平台',
                  subtitle: '寝室与公共设施维修报障',
                  onTap: () => _openProtected(context, const RepairPage()),
                ),
              ],
            ),
          ),

          // ── 校园生活与工具 ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppCellGroup(
              title: '校园生活与网络工具',
              cells: [
                AppCell(
                  icon: Icons.event_seat_outlined,
                  title: '场馆预约',
                  subtitle: '体育馆、羽毛球场等活动场地预约',
                  onTap: () => _openPage(
                    context,
                    const WebViewDetailPage(
                      title: '场馆预约',
                      url: AppConstants.gymReservationUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
                AppCell(
                  icon: Icons.local_activity_outlined,
                  title: '通识大讲堂',
                  subtitle: '学术讲座、通识报告预约与打卡',
                  onTap: () => _openPage(
                    context,
                    const WebViewDetailPage(
                      title: '通识教育大讲堂',
                      url: AppConstants.lecturesUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
                AppCell(
                  icon: Icons.celebration_outlined,
                  title: '活动广场',
                  subtitle: '校园文化与社团活动发布平台',
                  onTap: () => _openPage(
                    context,
                    const WebViewDetailPage(
                      title: '活动广场',
                      url: AppConstants.activitySquareUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
                AppCell(
                  icon: Icons.library_books_outlined,
                  title: '图书荐购',
                  subtitle: '向校图书馆推荐采购新书文献',
                  onTap: () => _openPage(
                    context,
                    const WebViewDetailPage(
                      title: '图书荐购',
                      url: AppConstants.bookRecommendationUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
                AppCell(
                  icon: Icons.auto_awesome_outlined,
                  title: 'DeepSeek大模型',
                  subtitle: '学校部署的 AI 助手服务平台',
                  onTap: () => _openPage(
                    context,
                    const WebViewDetailPage(
                      title: '湖南农业大学DeepSeek大模型',
                      url: AppConstants.deepSeekUrl,
                      showWebBack: true,
                    ),
                  ),
                ),
                AppCell(
                  icon: Icons.vpn_lock_outlined,
                  title: 'VPN转换',
                  subtitle: '校外访问校内知网与内网系统转换',
                  onTap: () => _openPage(context, const VpnConverterPage()),
                ),
                AppCell(
                  icon: Icons.speed_outlined,
                  title: '测速工具',
                  subtitle: '校园网与宽带网络测速',
                  onTap: () => _openPage(context, const NetworkSpeedTestPage()),
                ),
              ],
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: AppSpacing.xxxl * 2),
          ),
        ],
      ),
    );
  }
}
