# 通知功能修复更新日志

## 2026-09-10 - 通知不准时问题完整修复

### 🐛 修复的核心问题

#### 1. 前台通知逻辑缺陷（最严重）⭐
**问题描述**: Timer触发时如果应用在后台，通知会被完全跳过
```dart
// 修复前（第149行）
if (_isForeground) await _notifications.show(...)  // ❌ 后台不显示
```

**解决方案**: 移除前台检查，确保无论前后台都显示通知
```dart
// 修复后
await _notifications.show(id: id, title: title, body: body, ...)  // ✅ 始终显示
```

**影响**: 这是导致通知不准时的主要原因，现已完全修复

---

#### 2. 频繁重新调度导致通知丢失
**问题描述**: 每次前后台切换都会取消并重新调度所有通知，即将触发的通知被取消

**解决方案**: 
- 添加30分钟冷却期，避免频繁重新调度
- 添加重新调度锁，防止并发调度
- 记录上次调度时间

```dart
if (_lastReschedule == null || 
    now.difference(_lastReschedule!) > const Duration(minutes: 30)) {
  // 仅在必要时重新调度
}
```

---

#### 3. Timer使用策略优化
**问题描述**: 20天的Timer限制太长且不可靠，前台/后台逻辑混乱

**解决方案**: 采用混合策略
- ✅ **6小时内**: Timer（前台快速触发） + 系统调度器（后台保障）
- ✅ **6小时外**: 仅使用系统调度器（更可靠）

```dart
final useForegroundTimer = delay <= const Duration(hours: 6);
```

---

#### 4. 权限请求优化
**问题描述**: Android 12+设备精确闹钟权限请求顺序错误

**解决方案**: 先请求精确闹钟权限，再请求通知权限
```dart
// 1. 先请求精确闹钟权限（Android 12+必需）
final exactAlarmPermission = await android.requestExactAlarmsPermission();

// 2. 再请求通知权限
final notificationPermission = await android.requestNotificationsPermission();
```

---

#### 5. 错误处理与日志
**问题描述**: 空catch块，无法追踪失败原因

**解决方案**: 添加详细的Logger日志
```dart
_logger.i('Scheduled $courseCount course reminders');
_logger.w('exactAllowWhileIdle failed, trying inexact: $e');
_logger.e('Failed to schedule notification $id', error: e, stackTrace: stack);
```

---

### ✨ 新增功能

#### 1. 调度状态追踪
- `_lastReschedule`: 记录上次调度时间
- `_isRescheduling`: 防止重复调度锁
- 返回调度成功计数

#### 2. 通知调试助手
新增 `NotificationDebugHelper` 工具类：
```dart
// 检查通知状态
await NotificationDebugHelper.checkNotificationStatus();

// 打印诊断信息
await NotificationDebugHelper.printDiagnostics();
```

#### 3. 设置页面调试功能
在Debug模式下显示"诊断通知状态"按钮，方便开发调试

---

### 📊 技术细节

#### 混合调度策略
```dart
// 近期通知：双重保障
if (_isForeground && useForegroundTimer) {
  // 1. Timer（前台快速触发）
  _foregroundTimers[id] = Timer(delay, () async {
    await _notifications.show(...);
  });
}

// 2. 系统调度器（后台保障）
await _notifications.zonedSchedule(...,
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
```

#### Android精确闹钟降级
```dart
try {
  // 优先使用精确模式（精确到秒）
  await _notifications.zonedSchedule(...,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
} catch (e) {
  // 降级到非精确模式（可能延迟最多15分钟）
  await _notifications.zonedSchedule(...,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
}
```

---

### 📝 修改的文件

1. **lib/services/course_notification_service.dart**
   - 修复前台通知逻辑
   - 优化调度策略
   - 添加详细日志
   - 改进错误处理

2. **lib/utils/notification_debug_helper.dart** (新增)
   - 通知调试工具类

3. **lib/pages/settings_page.dart**
   - 添加调试按钮（Debug模式）

4. **docs/NOTIFICATION_FIX.md** (新增)
   - 详细修复文档

---

### 🧪 测试建议

测试场景：
- ✅ 应用在前台时的通知
- ✅ 应用在后台时的通知
- ✅ 应用完全关闭后的通知
- ✅ 前后台快速切换时的通知
- ✅ 权限请求流程

---

### ⚠️ 已知限制

1. **厂商限制**: 部分国产手机（小米、华为、OPPO等）需要手动设置：
   - 允许后台运行
   - 关闭电池优化
   - 允许自启动

2. **精确度**: 
   - `exactAllowWhileIdle`: 精确到秒级
   - `inexactAllowWhileIdle`: 可能延迟最多15分钟

3. **通知数量**: 
   - 最多60个课程通知
   - 最多60个作业通知

---

### 📈 性能优化

- ✅ 减少不必要的重新调度（30分钟冷却期）
- ✅ Timer仅用于6小时内的通知（减少内存占用）
- ✅ 添加调度锁（防止并发调度冲突）
- ✅ 详细日志便于问题追踪

---

### 🎯 预期效果

修复后，通知应该能够：
1. ✅ 准时触发（精确到秒或分钟级）
2. ✅ 前后台都能正常显示
3. ✅ 应用关闭后仍能触发
4. ✅ 前后台切换不影响即将触发的通知
5. ✅ 详细的日志便于问题诊断

---

### 📚 相关文档

- [详细修复文档](docs/NOTIFICATION_FIX.md)
- [flutter_local_notifications 官方文档](https://pub.dev/packages/flutter_local_notifications)

---

**版本**: v1.0.2  
**日期**: 2026-09-10  
**修复者**: Claude (Kiro)
