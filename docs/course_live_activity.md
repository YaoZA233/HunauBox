# 课程实况

入口：设置 → 通知设置 → 课程实况。可单独开启自动课程通知，也可主动开始本节课程或发送两分钟的示例。示例不会写入课表。

## 实现

- Dart 使用现有课程解析和调课规则，向 Android 发送具体场次与绝对时间。保存通知设置、导入/修改课表、应用返回前台时同步。
- 原生 Notification 展示课程、教室、时间、课前/下课倒计时；进行中的课程展示进度条。使用系统样式与系统字体，支持系统深浅色。
- 原生 AlarmManager 处理课前、开课、下课；SharedPreferences 保存场次，重启、安装更新和时间变化后恢复。无需持续运行 Flutter 或永久前台服务。
- 有精确闹钟权限时按边界准时更新；没有权限时使用系统非精确调度，可能延迟。进度每分钟尝试静音更新，Doze 时可以延后；系统倒计时独立计时。
- 点击进入课表；“收起本节”只隐藏对应场次，不关闭未来课程。下课后自动移除。锁屏隐藏教室等详情。

## 系统与厂商

Android 24+ 使用原生通知。Android 36+ 为进行中的课程使用 ProgressStyle、shortCriticalText。仅用户主动开始的课程活动与主动发送的进行中示例请求 promoted ongoing；自动课前提醒不请求提升，避免将日历提醒冒充实时活动。

荣耀官方开发指南明确支持通过 Android 16 原生实时通知接入灵动胶囊。荣耀旧版的全局触达/意图共享方案需要开发者平台配置、联调及审核，本次未接入。其他品牌在支持 Android 原生实时活动时可沿用同一路径；其专有胶囊、旧系统及厂商准入未验证，不能承诺所有机型都显示胶囊。无法提升时仍保留原生通知。

- [荣耀灵动胶囊开发指南](https://developer.honor.com/cn/doc/guides/101771)
- [Android 实时更新通知及使用条件](https://developer.android.google.cn/develop/ui/views/notifications/live-update?hl=zh-cn)

## 验证

- Android 调试包 assembleDebug 构建成功，已覆盖安装至连接的荣耀 AAK-AN00，Android 16 / MagicOS 10。
- 进行中示例在真实状态栏出现课程图标与剩余分钟；系统 notification dump 确认 `PROMOTED_ONGOING`。展开显示教室、课程时间、进度及两个操作。
- “查看课表”实际跳转到“我的课表”。课前示例为普通 ongoing 通知，不带提升标志。
- `flutter test --no-pub --reporter expanded`：493 项通过。相关文件 `flutter analyze --no-pub` 无问题。
- 新增测试覆盖设置持久化、场次标识与绝对时间、空教室回退，以及窄屏大字体下的深浅色与系统设置入口。
- 未验证其他厂商、旧安卓版本及真实设备重启/长时间 Doze。设备被强制停止应用后，Android 会停止其闹钟，需要重新打开应用。

## 本机构建

本机 Java 使用用户短路径临时目录时出现 Unix 域套接字连接异常。编译时临时设置 `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=E:/hunau_FlutterProject/smart_hunan_agri/build` 后执行 Gradle，可正常完成；没有改动系统 Java 配置。
