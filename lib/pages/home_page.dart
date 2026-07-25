import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course_model.dart';
import '../models/quick_action_item.dart';
import '../providers/homework_provider.dart';
import '../providers/notice_provider.dart';
import '../services/auth_service.dart';
import '../services/auth_guard.dart';
import '../services/course_schedule_service.dart';
import '../services/secure_storage_helper.dart';
import '../services/quick_action_store.dart';
import '../services/timetable_storage.dart';
import '../utils/date_calculator.dart';
import '../utils/ics_parser.dart';
import '../utils/week_parser.dart';
import '../widgets/login_bottom_sheet.dart';
import 'function_page.dart';
import 'empty_classroom_page.dart';
import 'score_page.dart';
import 'timetable_page.dart';
import 'profile_page.dart';
import 'campus_card_recharge_page.dart';
import 'campus_card_webview_page.dart';
import 'electricity_recharge_page.dart';
import 'xgxt_webview_page.dart';
import 'vpn_converter_page.dart';
import 'network_speed_test_page.dart';
import 'webview_detail_page.dart';
import 'bus_tracking_page.dart';
import 'dorm_service_page.dart';
import '../models/app_constants.dart';

class HomePage extends ConsumerStatefulWidget {
  final bool isActive;

  const HomePage({super.key, this.isActive = true});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _quickActionStore = QuickActionStore.instance;
  final _authService = AuthService();
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _showLoginSuccessBadge = false;
  String? _realName;
  String? _avatarUrl;
  bool _attemptedAutoLogin = false;

  bool _isLoadingTimetable = false;
  bool _hasTimetable = false;
  List<CourseModel> _allCourses = [];
  CourseModel? _currentCourse;
  CourseModel? _nextCourse;
  DateTime? _nextCourseStart;

  DateTime? _firstWeekMonday;
  int _currentWeek = 0;
  int _totalWeeks = 20;
  int _elapsedDays = 0;
  int _remainingDays = 0;
  int _progressPercent = 0;
  String _hitokotoText = '';
  String _hitokotoFrom = '';
  bool _wasActive = true;
  Timer? _courseRefreshTimer;

  @override
  void initState() {
    super.initState();
    _wasActive = widget.isActive;
    _quickActionStore.load();
    _loadPreviewCourses();
    _courseRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.isActive) {
        _updateDisplayedCourses(DateTime.now());
      }
    });
    _loadSemesterProgress();
    _loadHitokoto();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptAutoLogin();
    });
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive && !_wasActive) {
      _syncSavedLoginState();
      _loadPreviewCourses();
      _loadSemesterProgress();
    }

    _wasActive = widget.isActive;
  }

  @override
  void dispose() {
    _courseRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _attemptAutoLogin() async {
    if (_attemptedAutoLogin || _isLoggedIn) return;
    _attemptedAutoLogin = true;

    final storage = SecureStorageHelper();
    final username = await storage.getUsername();
    final password = await storage.getPassword();
    if (username == null || password == null || !mounted) {
      return;
    }

    await _performLogin(
      username,
      password,
      showWelcome: true,
      useBottomSheet: false,
    );
  }

  Future<void> _syncSavedLoginState() async {
    if (_isLoggedIn || !await AuthGuard.hasSavedCredentials()) return;

    final userInfo = await _authService.fetchFullUserInfo();
    if (!mounted) return;

    setState(() {
      _isLoggedIn = true;
      _realName = userInfo['realName'];
      _avatarUrl = userInfo['avatarUrl'];
    });
  }

  Future<void> _handleLogin() async {
    if (!_isLoggedIn && await AuthGuard.hasSavedCredentials()) {
      await _syncSavedLoginState();
    }
    if (!mounted) return;

    if (_isLoggedIn) {
      final storage = SecureStorageHelper();
      final username = await storage.getUsername();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfilePage(
            realName: _realName,
            avatarUrl: _avatarUrl,
            studentId: username,
            onLogout: () {
              setState(() {
                _isLoggedIn = false;
                _realName = null;
                _avatarUrl = null;
              });
            },
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => const LoginBottomSheet(),
    );

    // 回调拿到了登录后的用户信息
    if (result != null && mounted) {
      setState(() {
        _isLoggedIn = true;
        _realName = result['realName'];
        _avatarUrl = result['avatarUrl'];
      });
      _playLoginSuccessAnimation();
      _loadPreviewCourses();
      _loadSemesterProgress();
      _showWelcomePopup(_realName);
      ref.read(noticeProvider.notifier).refresh();
      ref.read(homeworkProvider.notifier).refresh();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _performLogin(
    String username,
    String password, {
    required bool showWelcome,
    required bool useBottomSheet,
  }) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.login(username, password, context);
      final userInfo = await _authService.fetchFullUserInfo();

      if (!mounted) return;

      setState(() {
        _isLoggedIn = true;
        _realName = userInfo['realName'];
        _avatarUrl = userInfo['avatarUrl'];
      });

      _playLoginSuccessAnimation();
      _loadPreviewCourses();
      _loadSemesterProgress();
      ref.read(noticeProvider.notifier).refresh();
      ref.read(homeworkProvider.notifier).refresh();

      if (showWelcome) {
        _showWelcomePopup(_realName);
      }
    } catch (e) {
      if (mounted && !useBottomSheet) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('自动登录失败，请手动登录后再试'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showWelcomePopup(String? realName) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '欢迎回来，${realName?.trim().isNotEmpty == true ? realName : '农大学子'}',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  void _playLoginSuccessAnimation() {
    if (!mounted) return;

    setState(() {
      _showLoginSuccessBadge = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showLoginSuccessBadge = false;
      });
    });
  }

  Future<bool> _ensureLoggedInForFeature() async {
    if (_isLoggedIn) return true;

    final result = await AuthGuard.ensureLoggedIn(context);
    if (!result.allowed || !mounted) return false;

    setState(() {
      _isLoggedIn = true;
      if (result.userInfo != null) {
        _realName = result.userInfo!['realName'];
        _avatarUrl = result.userInfo!['avatarUrl'];
      }
    });

    if (result.userInfo != null) {
      _playLoginSuccessAnimation();
      _showWelcomePopup(_realName);
    }

    _loadPreviewCourses();
    _loadSemesterProgress();
    ref.read(noticeProvider.notifier).refresh();
    ref.read(homeworkProvider.notifier).refresh();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final CourseModel? displayCourse = _currentCourse ?? _nextCourse;
    final bool hasCourse = displayCourse != null;
    final String statusLabel = _courseStatusLabel();

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 60,
      ), // 防止顶部被遮挡，加大 padding
      children: [
        // 问候语 + 右上角头像
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Life@HUNAU",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1.2,
                letterSpacing: -1.0,
              ),
            ),
            GestureDetector(
              onTap: _isLoading ? null : _handleLogin,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: _isLoading ? 0.92 : 1.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: _isLoading
                            ? [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.18),
                                  blurRadius: 14,
                                  spreadRadius: 2,
                                ),
                              ]
                            : const [],
                      ),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        backgroundImage: _isLoggedIn && _avatarUrl != null
                            ? FileImage(File(_avatarUrl!)) as ImageProvider
                            : null,
                        child: _isLoggedIn && _avatarUrl != null
                            ? null
                            : Icon(
                                Icons.person,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                      ),
                    ),
                  ),
                  if (_isLoading)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  if (_showLoginSuccessBadge)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.7, end: 1.0),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) {
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: Icon(
                            Icons.verified_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_hitokotoText.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildQuoteLine(),
        ],
        const SizedBox(height: 26),
        _buildCampusOverview(
          displayCourse: displayCourse,
          statusLabel: statusLabel,
          hasCourse: hasCourse,
        ),
        const SizedBox(height: 36),

        // 功能入口标题
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "常用服务",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            InkWell(
              onTap: () async {
                if (!await _ensureLoggedInForFeature() || !context.mounted) {
                  return;
                }
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const FunctionPage()));
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  "查看全部",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // 功能按钮组
        ValueListenableBuilder<List<String>>(
          valueListenable: _quickActionStore.selectedIds,
          builder: (context, ids, _) {
            final selectedIds = ids.isEmpty
                ? QuickActionCatalog.defaultIds
                : ids.take(8).toList();
            final items = selectedIds
                .map(QuickActionCatalog.byId)
                .whereType<QuickActionItem>()
                .toList();

            return GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildQuickAction(
                  item.icon,
                  item.label,
                  onTap: () => _handleQuickActionTap(item.id),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuoteLine() {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.format_quote_rounded, size: 22, color: colors.tertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hitokotoText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (_hitokotoFrom.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  _hitokotoFrom,
                  style: TextStyle(fontSize: 12, color: colors.tertiary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCampusOverview({
    required CourseModel? displayCourse,
    required String statusLabel,
    required bool hasCourse,
  }) {
    final colors = Theme.of(context).colorScheme;
    final hasSemester = _firstWeekMonday != null;
    final progress = (_progressPercent / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: colors.primary, width: 4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 146),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 17, color: colors.primary),
                    const SizedBox(width: 7),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isLoadingTimetable)
                  Text('正在同步课表...', style: _overviewTitleStyle(colors))
                else if (!hasCourse)
                  Text(
                    _hasTimetable ? '暂无后续课程' : '尚未导入课表',
                    style: _overviewTitleStyle(colors),
                  )
                else ...[
                  Text(
                    displayCourse!.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _overviewTitleStyle(colors),
                  ),
                  const SizedBox(height: 8),
                  _buildCourseDetail(
                    icon: Icons.schedule_outlined,
                    text: _formatCourseTime(displayCourse),
                  ),
                  const SizedBox(height: 5),
                  _buildCourseDetail(
                    icon: Icons.location_on_outlined,
                    text: displayCourse.classroom.trim().isEmpty
                        ? '教室待定'
                        : displayCourse.classroom,
                  ),
                  if (_currentCourse != null && _nextCourse != null) ...[
                    const SizedBox(height: 9),
                    _buildCourseDetail(
                      icon: Icons.skip_next_rounded,
                      text: '下一节：${_nextCourse!.name} · ${_formatCourseTime(_nextCourse!)}',
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 112,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: colors.outlineVariant,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hasSemester ? '第$_currentWeek周' : '学期进度',
                  style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  hasSemester ? '$_progressPercent%' : '--',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: colors.secondary,
                  ),
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: hasSemester ? progress : 0,
                    backgroundColor: colors.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(colors.secondary),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  hasSemester ? '余$_remainingDays天 / $_totalWeeks周' : '导入课表后显示',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseDetail({
    required IconData icon,
    required String text,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: colors.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            softWrap: true,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  TextStyle _overviewTitleStyle(ColorScheme colors) {
    return TextStyle(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: colors.onSurface,
    );
  }

  Future<void> _loadPreviewCourses() async {
    setState(() {
      _isLoadingTimetable = true;
    });

    try {
      final storage = TimetableStorage();
      final hasTimetable = await storage.hasLocalTimetable();

      if (hasTimetable) {
        final icsContent = await storage.readTimetable();
        final metadata = await storage.readMetadata();
        final firstWeekMondayValue = metadata?['firstWeekMonday'];
        final firstWeekMonday = firstWeekMondayValue is String
            ? DateTime.tryParse(firstWeekMondayValue)
            : null;

        if (icsContent != null && firstWeekMonday != null && mounted) {
          setState(() {
            _hasTimetable = true;
            _allCourses = IcsParser.parse(icsContent);
            _firstWeekMonday = firstWeekMonday;
          });
          _updateDisplayedCourses(DateTime.now());
        } else if (mounted) {
          setState(() {
            _hasTimetable = hasTimetable;
            _allCourses = [];
            _firstWeekMonday = null;
            _currentCourse = null;
            _nextCourse = null;
            _nextCourseStart = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasTimetable = false;
            _allCourses = [];
            _currentCourse = null;
            _nextCourse = null;
            _nextCourseStart = null;
          });
        }
      }
    } catch (e) {
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTimetable = false;
        });
      }
    }
  }

  void _updateDisplayedCourses(DateTime now) {
    if (!mounted) return;
    final selection = CourseScheduleService.currentAndNext(
      courses: _allCourses,
      firstWeekMonday: _firstWeekMonday,
      now: now,
    );
    setState(() {
      _currentCourse = selection.current?.course;
      _nextCourse = selection.next?.course;
      _nextCourseStart = selection.next?.start;
    });
  }

  String _courseStatusLabel() {
    if (_currentCourse != null) return '正在上课';
    final nextStart = _nextCourseStart;
    if (nextStart == null) return '下一节课';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextDate = DateTime(nextStart.year, nextStart.month, nextStart.day);
    final dayDifference = nextDate.difference(today).inDays;
    if (dayDifference == 0) return '下一节课';
    if (dayDifference == 1) return '明天第一节课';
    return '${nextStart.month}月${nextStart.day}日下一节课';
  }

  String _formatCourseTime(CourseModel course) {
    final start = DateCalculator.getSectionTime(course.startPeriod)['start']!;
    final end = DateCalculator.getSectionTime(course.endPeriod)['end']!;
    final startStr =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '$startStr - $endStr';
  }

  Future<void> _loadSemesterProgress() async {
    try {
      final storage = TimetableStorage();
      final metadata = await storage.readMetadata();
      final icsContent = await storage.readTimetable();

      if (metadata != null && metadata['firstWeekMonday'] != null) {
        final firstWeekMonday = DateTime.parse(
          metadata['firstWeekMonday'] as String,
        );
        final now = DateTime.now();

        final startDate = DateTime(
          firstWeekMonday.year,
          firstWeekMonday.month,
          firstWeekMonday.day,
        );
        final currentDate = DateTime(now.year, now.month, now.day);

        int elapsedDays = currentDate.difference(startDate).inDays + 1;
        if (elapsedDays < 0) elapsedDays = 0;

        final currentWeek = DateCalculator.getCurrentWeekNumber(
          firstWeekMonday,
          now,
        );

        int totalWeeks = 20;
        if (icsContent != null) {
          final courses = IcsParser.parse(icsContent);
          int maxWeek = 20;
          for (final course in courses) {
            final weeks = WeekParser.parseWeeks(course.weeks);
            if (weeks.isNotEmpty) {
              final courseMaxWeek = weeks.reduce(
                (curr, next) => curr > next ? curr : next,
              );
              if (courseMaxWeek > maxWeek) {
                maxWeek = courseMaxWeek;
              }
            }
          }
          totalWeeks = maxWeek;
        }

        final totalDays = totalWeeks * 7;
        int remainingDays = totalDays - elapsedDays;
        if (remainingDays < 0) remainingDays = 0;

        int progressPercent = 0;
        if (totalDays > 0) {
          progressPercent = (elapsedDays / totalDays * 100)
              .clamp(0, 100)
              .toInt();
        }

        if (mounted) {
          setState(() {
            _hasTimetable = true;
            _firstWeekMonday = firstWeekMonday;
            _currentWeek = currentWeek <= 0 ? 1 : currentWeek;
            _totalWeeks = totalWeeks;
            _elapsedDays = elapsedDays;
            _remainingDays = remainingDays;
            _progressPercent = progressPercent;
          });
        }
      }
    } catch (e) {
      return;
    }
  }

  Future<void> _loadHitokoto() async {
    try {
      final dio = Dio();
      final response = await dio.get('https://v1.hitokoto.cn/?c=i');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        final text = data['hitokoto']?.toString().trim() ?? '';
        final from = data['from']?.toString().trim() ?? '';
        if (mounted) {
          setState(() {
            _hitokotoText = text;
            _hitokotoFrom = from;
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildQuickAction(IconData icon, String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _handleQuickActionTap(String id) async {
    // The calendar is a public web page and should remain usable before login.
    if (id != 'school_calendar' && !await _ensureLoggedInForFeature()) return;
    if (!mounted) return;

    if (id == 'timetable') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TimetablePage()));
      if (!mounted) return;
      _loadPreviewCourses();
      _loadSemesterProgress();
      return;
    }

    if (id == 'empty_classroom') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const EmptyClassroomPage()));
      return;
    }

    if (id == 'score') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ScorePage()));
      return;
    }

    if (id == 'campus_card_recharge') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CampusCardRechargePage()));
      return;
    }

    if (id == 'ele_recharge') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ElectricityRechargePage()),
      );
      return;
    }

    if (id == 'campus_card') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CampusCardWebViewPage()));
      return;
    }

    if (id == 'xgxt') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const XgxtWebViewPage()));
      return;
    }

    if (id == 'teaching_eval') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebViewDetailPage(
            title: '教学评价平台',
            url: AppConstants.teachingEvalUrl,
            showWebBack: true,
          ),
        ),
      );
      return;
    }

    if (id == 'school_calendar') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WebViewDetailPage(
            title: '电子校历',
            url: AppConstants.schoolCalendarUrl,
            showWebBack: true,
          ),
        ),
      );
      return;
    }

    if (id == 'book_recommend') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WebViewDetailPage(
            title: '图书荐购',
            url: AppConstants.bookRecommendationUrl,
            showWebBack: true,
          ),
        ),
      );
      return;
    }

    if (id == 'repair') {
      await Navigator.of(context).push(
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
      return;
    }

    if (id == 'gym') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WebViewDetailPage(
            title: '场馆预约',
            url: AppConstants.gymReservationUrl,
            showWebBack: true,
          ),
        ),
      );
      return;
    }

    if (id == 'dorm_service') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DormServicePage()));
      return;
    }

    if (id == 'lecture_hall') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WebViewDetailPage(
            title: '通识教育大讲堂',
            url: AppConstants.lecturesUrl,
            showWebBack: true,
          ),
        ),
      );
      return;
    }

    if (id == 'activity_square') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WebViewDetailPage(
            title: '活动广场',
            url: AppConstants.activitySquareUrl,
            showWebBack: true,
          ),
        ),
      );
      return;
    }

    if (id == 'bus') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BusTrackingPage()));
      return;
    }

    if (id == 'vpn') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const VpnConverterPage()));
      return;
    }

    if (id == 'speed_test') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NetworkSpeedTestPage()));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('该功能正在开发中')));
  }
} // 确保这个大括号存在
