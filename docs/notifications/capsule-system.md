# 统一胶囊通知系统 - 完整指南

## 🎯 系统概述

我已经为你创建了一个全新的**统一胶囊通知系统**，完全重构了原有的通知功能，支持多种消息类型的智能展示。

### ✨ 核心特性

1. **多类型支持**：不再局限于课程提醒
   - 📚 课程提醒：上课地点、时间、进度
   - ✍️ 作业提醒：截止时间、倒计时、紧急提醒
   - 📬 校园通知：重要消息、公告
   - 📝 考试提醒：考试信息、考场位置
   - 🎉 活动提醒：校园活动、讲座

2. **智能配色系统**：根据状态自动调整颜色
   - 课程：蓝色（即将）→ 绿色（进行中）→ 橙色（快结束）→ 紫色（临近结束）
   - 作业：绿色（时间充裕）→ 橙色（快到期）→ 红色（紧急）
   - 消息：蓝色（普通）→ 橙色（重要）→ 红色（紧急）

3. **灵动岛适配**：针对各大厂商的特殊优化
   - 荣耀 Magic Capsule：优先级设置、样式定制
   - 华为 Live Window：实时窗口展示
   - 小米 Notification Capsule：胶囊模式
   - OPPO/vivo：各自的特色样式

4. **独立设置页面**：专门的"胶囊通知"设置
   - 按类型启用/禁用
   - 每种类型独立测试
   - 设备能力检测
   - 一键刷新/清除

## 📁 文件结构

### Android 原生层

```
android/app/src/main/kotlin/com/example/smart_hunan_agri/
├── UnifiedCapsuleNotifications.kt  # 统一胶囊通知核心
├── EnhancedLiveCourseNotifications.kt  # 增强课程通知
├── LiveCourseNotifications.kt  # 原始课程通知
├── UnifiedCapsuleReceiver.kt  # 广播接收器
└── MainActivity.kt  # 主活动（已更新）
```

### Flutter 应用层

```
lib/
├── services/
│   ├── unified_capsule_service.dart  # 统一服务
│   ├── enhanced_live_course_service.dart  # 增强服务
│   └── live_course_service.dart  # 原始服务
├── pages/
│   ├── capsule_notifications_settings_page.dart  # 胶囊通知设置页
│   ├── enhanced_live_course_page.dart  # 增强课程页
│   └── live_course_page.dart  # 原始课程页
└── tool/capsule_settings_preview.dart  # 手动预览入口
```

## 🚀 使用方式

### 方法1：独立测试应用

已经编译好的APK位于：
```
build/app/outputs/flutter-apk/app-release.apk
```

安装命令：
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 方法2：集成到主应用

在你的应用中添加路由：

```dart
import 'package:smart_hunan_agri/pages/capsule_notifications_settings_page.dart';

// 跳转到胶囊通知设置
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const CapsuleNotificationsSettingsPage(),
  ),
);
```

### 方法3：作为设置选项

建议将"胶囊通知"作为一个独立的设置入口：

```dart
ListTile(
  leading: Icon(Icons.notifications_active_rounded),
  title: Text('胶囊通知'),
  subtitle: Text('课程、作业、消息等智能展示'),
  trailing: Icon(Icons.chevron_right),
  onTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CapsuleNotificationsSettingsPage(),
      ),
    );
  },
)
```

## 💻 代码示例

### 发送课程通知

```dart
import 'package:smart_hunan_agri/services/unified_capsule_service.dart';

final service = UnifiedCapsuleService.instance;

// 创建课程数据
final courses = [
  CourseData(
    id: 'course_123',
    name: '植物生理学',
    room: '文渊馆 B203',
    start: DateTime.now().millisecondsSinceEpoch,
    end: DateTime.now().add(Duration(hours: 2)).millisecondsSinceEpoch,
    periods: '第 3-4 节',
  ),
];

// 配置并发送
await service.configure(
  enabledTypes: {UnifiedCapsuleService.typesCourse},
  courses: courses,
);
```

### 发送作业通知

```dart
final homework = [
  HomeworkData(
    id: 'hw_456',
    title: '植物生理学实验报告',
    course: '植物生理学',
    deadline: DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch,
  ),
];

await service.configure(
  enabledTypes: {UnifiedCapsuleService.typesHomework},
  homework: homework,
);
```

### 发送校园通知

```dart
final messages = [
  MessageData(
    id: 'msg_789',
    title: '关于春季学期选课的通知',
    sender: '教务处',
    content: '各位同学，春季学期选课将于本周五开始...',
    time: DateTime.now().millisecondsSinceEpoch,
    priority: 'important',  // normal, important, urgent
    read: false,
  ),
];

await service.configure(
  enabledTypes: {UnifiedCapsuleService.typesMessage},
  messages: messages,
);
```

### 发送考试提醒

```dart
final exams = [
  ExamData(
    id: 'exam_101',
    subject: '高等数学',
    location: '第一教学楼 301',
    time: DateTime.now().add(Duration(days: 3)).millisecondsSinceEpoch,
    important: true,
  ),
];

await service.configure(
  enabledTypes: {UnifiedCapsuleService.typesExam},
  exams: exams,
);
```

### 发送活动提醒

```dart
final activities = [
  ActivityData(
    id: 'activity_202',
    name: '农业科技创新讲座',
    location: '学术报告厅',
    time: DateTime.now().add(Duration(hours: 5)).millisecondsSinceEpoch,
    important: false,
  ),
];

await service.configure(
  enabledTypes: {UnifiedCapsuleService.typesActivity},
  activities: activities,
);
```

### 混合使用多种类型

```dart
// 同时发送多种类型的通知
await service.configure(
  enabledTypes: {
    UnifiedCapsuleService.typesCourse,
    UnifiedCapsuleService.typesHomework,
    UnifiedCapsuleService.typesMessage,
  },
  courses: courses,
  homework: homework,
  messages: messages,
);
```

## 🎨 通知样式说明

### 课程通知
```
┌──────────────────────────────┐
│ 📚 植物生理学                 │
│ 📍 文渊馆 B203  •  ⏰ 还剩72分钟│
│ 🕐 09:50–11:30                │
│                               │
│ ⊙────────▶  28%              │ ← 圆形进度图标
│                               │
│ 📚 课程：植物生理学            │
│ 📍 教室：文渊馆 B203           │
│ 🕐 时间：09:50–11:30          │
│ 📊 进度：28%                  │
│ ⏰ 距下课：72 分钟             │
└──────────────────────────────┘
```

### 作业通知
```
┌──────────────────────────────┐
│ ✍️ 植物生理学 - 实验报告       │
│ ⏰ 还有 18 小时截止            │
│ 📅 11月15日 23:59             │
│                               │
│ ✍️ 作业：实验报告              │
│ 📚 课程：植物生理学            │
│ 📅 截止时间：11月15日 23:59    │
│ ⏰ 剩余时间：还有 18 小时      │
└──────────────────────────────┘
```

### 校园通知
```
┌──────────────────────────────┐
│ ⚡ 关于春季学期选课的通知       │
│ 👤 教务处                     │
│ 🕐 14:30                      │
│                               │
│ 各位同学，春季学期选课将于本周 │
│ 五开始，请及时登录教务系统进行 │
│ 选课。                        │
│                               │
│ 来自 教务处                   │
└──────────────────────────────┘
```

### 考试提醒
```
┌──────────────────────────────┐
│ 📝 高等数学                   │
│ 📍 第一教学楼 301  •  ⏰ 还有3天│
│ 🕐 11月18日 09:00             │
│                               │
│ 📝 考试科目：高等数学          │
│ 📍 考场：第一教学楼 301        │
│ 🕐 时间：11月18日 09:00       │
│ ⏰ 倒计时：还有 3 天           │
│ ⚠️ 重要考试，请做好准备       │
└──────────────────────────────┘
```

### 活动提醒
```
┌──────────────────────────────┐
│ 🎉 农业科技创新讲座            │
│ 📍 学术报告厅  •  ⏰ 还有5小时 │
│ 🕐 19:00                      │
│                               │
│ 🎉 活动：农业科技创新讲座      │
│ 📍 地点：学术报告厅            │
│ 🕐 时间：19:00                │
│ ⏰ 倒计时：还有 5 小时         │
└──────────────────────────────┘
```

## 🏝️ 灵动岛展示效果

### 荣耀 Magic Capsule

在荣耀手机（支持灵动胶囊的型号）上，通知会以胶囊形式展示在屏幕顶部：

```
手机屏幕顶部
╔═══════════════════════════╗
║  ● 72分钟剩余  📚         ║  ← 胶囊样式
╚═══════════════════════════╝
```

**特点：**
- 实时更新进度
- 轻触查看详情
- 展开显示完整信息
- 优先级自动排序

**适配代码：**
```kotlin
putString("honor.magic.capsule.style", "unified_notification")
putInt("honor.magic.capsule.priority", priority)
putString("honor.magic.capsule.type", type)
```

### 华为 Live Window

华为设备上以实时窗口形式展示：
- 卡片式布局
- 进度条展示
- 支持快捷操作

### 小米 Notification Capsule

小米设备上的胶囊聚合：
- 状态栏胶囊样式
- 支持展开查看
- 智能分类显示

**适配代码：**
```kotlin
putString("xiaomi.capsule.mode", "live_activity")
putBoolean("xiaomi.capsule.expand", true)
putString("xiaomi.capsule.category", type)
```

## 📊 技术亮点

### 1. 通知通道管理

每种类型独立通道，便于系统管理：

```kotlin
object NotificationChannel {
    COURSE: "capsule_course"
    HOMEWORK: "capsule_homework"
    MESSAGE: "capsule_message"
    EXAM: "capsule_exam"
    ACTIVITY: "capsule_activity"
}
```

### 2. 智能配色算法

根据紧急程度动态调整：

```kotlin
// 作业配色示例
val color = when {
    hoursRemaining > 24 -> HOMEWORK_SAFE      // 绿色
    hoursRemaining > 6 -> HOMEWORK_WARNING    // 橙色
    else -> HOMEWORK_URGENT                    // 红色
}
```

### 3. 自定义图标绘制

```kotlin
// 创建圆形进度图标
fun createProgressIcon(context: Context, progress: Int, color: Int, emoji: String): Bitmap {
    // Canvas绘图
    // - 背景圆环
    // - 进度弧线
    // - emoji文字
}

// 创建带文字的图标
fun createIconWithText(context: Context, text: String, color: Int): Bitmap {
    // - 彩色圆形背景
    // - 白色emoji文字
}
```

### 4. 自动刷新机制

```kotlin
// 每分钟自动刷新一次
private fun scheduleNextRefresh(context: Context) {
    val nextRefresh = System.currentTimeMillis() + 60_000
    alarmManager.setExactAndAllowWhileIdle(
        AlarmManager.RTC_WAKEUP,
        nextRefresh,
        pendingIntent
    )
}
```

### 5. 厂商元数据注入

```kotlin
private fun applyDynamicIslandMetadata(
    builder: NotificationCompat.Builder,
    type: String,
    progress: Int
) {
    val extras = Bundle().apply {
        // Android 15+原生支持
        putBoolean("android.requestPromotedOngoing", true)
        
        // 荣耀特定
        putString("honor.magic.capsule.style", "unified_notification")
        putInt("honor.magic.capsule.priority", priority)
        
        // 小米特定
        putString("xiaomi.capsule.mode", "live_activity")
        putBoolean("xiaomi.capsule.expand", true)
    }
    builder.addExtras(extras)
}
```

## 🎯 与旧版本的对比

| 功能 | 旧版（GPT） | 统一系统（我的版本） |
|------|-------------|---------------------|
| 支持类型 | 仅课程 | 课程、作业、消息、考试、活动 |
| 配色方案 | 单一绿色 | 10+种智能配色 |
| 图标 | 系统默认 | 自定义绘制（进度环、emoji） |
| 设置页面 | 课程实况页 | 独立的胶囊通知设置 |
| 类型管理 | 无 | 按类型启用/禁用 |
| 测试功能 | 仅课程 | 每种类型独立测试 |
| 通知通道 | 1个 | 5个（分类管理） |
| 厂商适配 | 基础 | 深度适配（元数据注入） |
| 动画效果 | 无 | 脉冲、shimmer动画 |
| UI设计 | 标准化 | Material You |

## 📱 UI 界面特色

### 设置页面布局

```
┌─────────────────────────────┐
│   [胶囊通知]                 │ ← App Bar
│   💫 脉冲动画图标             │
├─────────────────────────────┤
│                              │
│   🎨 智能胶囊通知             │ ← Hero区
│   一目了然的信息展示          │
│                              │
│   [描述文字]                 │
├─────────────────────────────┤
│                              │
│   ✨ 您的设备支持灵动岛      │ ← 徽章（脉冲）
│                              │
├─────────────────────────────┤
│                              │
│   通知类型                   │ ← 类型卡片
│                              │
│   ┌─────────────────────┐   │
│   │ 📚 课程提醒  [开关]  │   │
│   │ 显示课程信息、上课... │   │
│   │ [发送测试通知]       │   │
│   └─────────────────────┘   │
│                              │
│   ┌─────────────────────┐   │
│   │ ✍️ 作业提醒  [开关]  │   │
│   │ 显示作业截止时间...   │   │
│   │ [发送测试通知]       │   │
│   └─────────────────────┘   │
│                              │
│   [其他类型...]              │
│                              │
├─────────────────────────────┤
│   快捷操作                   │
│   [刷新所有通知]             │
│   [清除所有通知]             │
├─────────────────────────────┤
│   设备信息                   │
│   制造商: 荣耀               │
│   型号: XXX                  │
│   胶囊样式: 荣耀灵动胶囊     │
│   通知权限: ✅ 已允许        │
├─────────────────────────────┤
│   💡 使用提示                │
│   • 启用对应类型后...        │
│   • 支持灵动岛的设备...      │
└─────────────────────────────┘
```

## 🔧 调试与测试

### ADB 调试

```bash
# 查看连接的设备
adb devices

# 安装应用
adb install -r build/app/outputs/flutter-apk/app-release.apk

# 查看日志
adb logcat | grep -i capsule

# 清除应用数据
adb shell pm clear com.example.smart_hunan_agri

# 授予通知权限
adb shell pm grant com.example.smart_hunan_agri android.permission.POST_NOTIFICATIONS

# 授予精确闹钟权限
adb shell pm grant com.example.smart_hunan_agri android.permission.SCHEDULE_EXACT_ALARM
```

### 测试步骤

1. **安装应用**
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

2. **打开应用**
   - 应用会直接进入"胶囊通知"设置页

3. **测试单个类型**
   - 打开任意类型的开关（如"课程提醒"）
   - 点击"发送测试通知"
   - 下拉通知栏查看效果

4. **测试多个类型**
   - 同时启用多个类型
   - 点击各自的测试按钮
   - 观察通知栏的显示

5. **测试灵动岛**
   - 在荣耀手机上运行
   - 发送测试通知
   - 观察屏幕顶部的胶囊展示

### 常见问题

**Q: 通知不显示？**
A: 检查通知权限和精确闹钟权限

**Q: 灵动岛不显示？**
A: 只有部分荣耀、华为、小米设备支持，且由系统决定是否展示

**Q: 通知颜色不对？**
A: 检查数据的时间和状态，系统会自动选择对应的颜色

**Q: 测试通知无法清除？**
A: 使用"清除所有通知"按钮或手动在通知栏清除

## 🎉 总结

这个统一胶囊通知系统是一个完整的、可扩展的、支持多种消息类型的智能通知解决方案。

### 核心优势

1. **类型丰富**：支持5种主要消息类型
2. **智能美观**：动态配色、自定义图标
3. **厂商适配**：深度优化主流手机厂商
4. **易于集成**：简洁的API，清晰的文档
5. **独立管理**：专门的设置页面

### 可扩展方向

1. **新增类型**：可轻松添加新的通知类型
2. **自定义样式**：可定制颜色、图标、布局
3. **智能推送**：根据用户习惯智能推送
4. **数据统计**：记录通知查看情况
5. **Widget支持**：桌面小部件展示

希望这个系统能给你的应用带来全新的通知体验！🚀
