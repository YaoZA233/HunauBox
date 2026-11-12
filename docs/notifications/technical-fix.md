# 通知功能修复与优化

## 修复的问题

### 1. 前台通知逻辑缺陷 (最严重)
**问题**: Timer触发时如果应用在后台，通知会被跳过
```dart
// 原代码（149行）
if (_isForeground) await _notifications.show(...)
```
**影响**: 这导致用户在应用切换到后台后，通知完全不会显示

**修复**: 移除了前台检查，确保无论前后台都能显示通知
```dart
// 新代码
await _notifications.show(id, title, body, notificationDetails);
```

### 2. 频繁重新调度
**问题**: 每次前后台切换都会取消所有通知并重新调度
```dart
// 原代码
void didChangeAppLifecycleState(AppLifecycleState state) {
  _isForeground = foreground;
  unawaited(rescheduleIfEnabled()); // 每次都重新调度
}
```
**影响**: 即将触发的通知被取消，导致通知丢失或延迟

**修复**: 添加30分钟冷却期和重新调度锁
```dart
// 新代码
if (_lastReschedule == null || 
    now.difference(_lastReschedule!) > const Duration(minutes: 30)) {
  unawaited(rescheduleIfEnabled());
}
```

### 3. Timer使用策略不当
**问题**: 20天的Timer限制太长，且前台/后台逻辑混乱
```dart
// 原代码
if (_isForeground && delay <= const Duration(days: 20)) {
  // 仅使用Timer
}
```
**影响**: 长时间的Timer可能不可靠，且后台不使用系统调度器

**修复**: 采用混合策略
- 6小时内的近期通知：Timer（前台） + 系统调度器（后台保障）
- 6小时外的远期通知：仅使用系统调度器

### 4. 权限请求顺序错误
**问题**: 精确闹钟权限和通知权限顺序混乱
```dart
// 原代码
final androidGranted = await android?.requestNotificationsPermission();
await android?.requestExactAlarmsPermission(); // 顺序错误
```
**影响**: Android 12+设备可能无法获取精确通知权限

**修复**: 先请求精确闹钟权限，再请求通知权限

### 5. 缺少错误处理和日志
**问题**: catch块为空，无法追踪调度失败原因
```dart
// 原代码
try {
  await _notifications.zonedSchedule(...);
} catch (_) { // 空catch
  await _notifications.zonedSchedule(...);
}
```
**影响**: 无法诊断通知失败的原因

**修复**: 添加详细的Logger日志记录

## 新增功能

### 1. 调度状态追踪
- 记录上次调度时间
- 防止重复调度
- 调度成功计数

### 2. 详细的日志输出
```dart
_logger.i('Scheduled $courseCount course reminders');
_logger.w('exactAllowWhileIdle failed, trying inexact: $e');
_logger.e('Failed to schedule notification $id', error: e2, stackTrace: stack);
```

### 3. 调试助手
新增 `NotificationDebugHelper` 类：
- `testImmediateNotification()`: 测试立即通知
- `checkNotificationStatus()`: 检查通知状态
- `printDiagnostics()`: 打印诊断信息

### 4. 设置页面调试按钮
在Debug模式下显示"诊断通知状态"按钮，方便开发时调试

## 技术细节

### 混合调度策略
```dart
// 近期通知（6小时内）：双重保障
if (_isForeground && useForegroundTimer) {
  // 1. 创建Timer（快速、精确）
  _foregroundTimers[id] = Timer(delay, () async {
    await _notifications.show(...);
  });
}

// 2. 始终使用系统调度器作为后备
await _notifications.zonedSchedule(...,
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
```

### Android精确闹钟降级策略
```dart
try {
  // 首先尝试精确模式
  await _notifications.zonedSchedule(...,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
} catch (e) {
  // 降级到非精确模式（可能有15分钟延迟）
  await _notifications.zonedSchedule(...,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
}
```

## 使用建议

### 用户端
1. 确保在系统设置中授予应用"通知"权限
2. Android 12+设备需授予"精确闹钟"权限
3. 部分厂商（小米、华为、OPPO等）需要额外设置：
   - 允许后台运行
   - 关闭电池优化
   - 允许自启动

### 开发端
1. 使用Debug模式下的"诊断通知状态"按钮检查配置
2. 查看日志输出了解通知调度情况
3. 测试场景：
   - 应用在前台时的通知
   - 应用在后台时的通知
   - 应用完全关闭后的通知
   - 前后台切换时的通知

## 已知限制

### Android省电模式
部分厂商的省电模式可能会限制后台通知，这是系统级限制，无法通过代码完全解决。

### 精确度
- `exactAllowWhileIdle`: 精确到秒级
- `inexactAllowWhileIdle`: 可能有最多15分钟的延迟

### 通知数量
- 最多调度60个课程通知
- 最多调度60个作业截止通知
- 总计120个通知

## 测试清单

- [ ] 前台通知正常显示
- [ ] 后台通知正常显示
- [ ] 应用关闭后通知正常显示
- [ ] 前后台切换不会取消即将触发的通知
- [ ] 权限请求流程正常
- [ ] 日志输出正常
- [ ] 调试功能正常

## 性能影响

- 减少了不必要的重新调度（30分钟冷却期）
- Timer仅用于6小时内的通知（减少内存占用）
- 添加了调度锁（防止并发调度）

## 相关文件

- `lib/services/course_notification_service.dart`: 核心通知服务
- `lib/services/course_notification_settings_store.dart`: 通知设置存储
- `lib/utils/notification_debug_helper.dart`: 调试助手
- `lib/pages/settings_page.dart`: 设置页面
- `android/app/src/main/AndroidManifest.xml`: Android权限配置

## 版本历史

### v1.0.2 (2026-09-10)
- 修复前台通知逻辑缺陷
- 优化前后台切换调度策略
- 改进权限请求流程
- 添加详细日志和调试功能
- 优化Timer使用策略
