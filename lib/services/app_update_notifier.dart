import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// APK 下载在通知栏中的进度通知。
/// 所有方法都会静默吞掉异常：通知不可用（权限被拒、平台不支持）不能影响下载与安装主流程。
class AppUpdateNotifier {
  AppUpdateNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'app_update_download';
  static const String channelName = '应用更新下载';
  static const int notificationId = 20260101;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  int _lastPercent = -2;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: '显示新版本安装包的下载进度',
            importance: Importance.low,
          ),
        );
    _initialized = true;
  }

  Future<void> requestPermission() async {
    try {
      await _ensureInitialized();
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// 进度按整百分数节流，避免高频刷新通知
  Future<void> showProgress({required int received, required int total}) async {
    final percent = total > 0 ? received * 100 ~/ total : -1;
    if (percent == _lastPercent) return;
    _lastPercent = percent;
    try {
      await _ensureInitialized();
      await _plugin.show(
        id: notificationId,
        title: '正在下载新版本',
        body: total > 0 ? '已下载 $percent%' : '正在连接服务器…',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: '显示新版本安装包的下载进度',
            importance: Importance.low,
            priority: Priority.low,
            category: AndroidNotificationCategory.progress,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: false,
            showWhen: false,
            progress: total > 0 ? received : 0,
            maxProgress: total > 0 ? total : 0,
            indeterminate: total <= 0,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> showCompleted(String fileName) async {
    _lastPercent = -2;
    try {
      await _ensureInitialized();
      await _plugin.show(
        id: notificationId,
        title: '下载完成',
        body: '$fileName 已保存到 Download 目录，正在打开安装',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: '显示新版本安装包的下载进度',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: false,
            autoCancel: true,
            showWhen: false,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> showFailed(String message) async {
    _lastPercent = -2;
    try {
      await _ensureInitialized();
      await _plugin.show(
        id: notificationId,
        title: '下载失败',
        body: message,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: '显示新版本安装包的下载进度',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: false,
            autoCancel: true,
            showWhen: false,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancel() async {
    _lastPercent = -2;
    try {
      await _plugin.cancel(id: notificationId);
    } catch (_) {}
  }
}
