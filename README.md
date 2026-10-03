# HUNAUBOX

基于 Flutter 开发的 HUNAU 校园生活服务 App。应用通过侧边导航整合首页、校园功能、通知、作业和设置，将校园卡、教务与常用校园服务集中到一个移动端入口中。

项目当前使用学校统一身份认证登录，并通过网络请求、WebView 和本地缓存连接校园相关服务。

## 主要功能

### 首页

- 展示今日课程或下一节课程，以及上课时间和地点
- 展示学期周次、学期进度和剩余时间
- 提供校园卡、校园卡充值、电费充值、空教室、学工系统、成绩查询、课程表和报修平台等常用入口
- 支持选择最多 8 个常用服务入口
- 展示每日一句，并提供个人资料入口

### 校园服务

- 校园卡信息查询和在线充值
- 宿舍电费查询与充值
- 空教室实时查询
- 学工系统、教学评价平台、成绩查询和课程表
- 电子校历、图书荐购、报修平台和场馆预约
- 阳光服务：提交校园诉求、查看受理单位和办理进度
- 请假申请：选择请假类型与时间，计算时长并查看审核状态
- 原生报修平台：后勤、校园网络、一校通和业务系统分类报修，支持工单列表与详情
- 学生公寓信息查询、校园班车/校车信息和活动广场
- VPN 地址转换和网络测速

### 通知与作业

- 获取并查看校园通知，支持全部/未读筛选和通知详情
- 获取课程作业，按待完成/已完成查看并打开作业详情
- 登录后可手动刷新通知和作业数据
- 可在设置中开启新校园消息和新作业通知

### Agent 校园助手

- 可选开启校园 Agent，并配置兼容 Chat Completions 的模型服务
- 支持查询今日课程、下一节课、课程地点和近期作业
- 支持查询课表临时调课、阳光服务诉求、请假申请和报修工单
- 支持用自然语言创建临时调课、停课和恢复原课表，执行前会展示原安排、目标安排和冲突提示并请求确认
- 支持创建手动作业、完成手动作业和打开相关校园功能
- 支持通过自然语言进入空教室、成绩、通知等校园服务页面
- 涉及创建、跳转或其他可能改变数据的操作时，会先展示操作内容并请求确认
- Agent 不代替用户支付、提交问卷、提交学习通作业或执行扣款操作
- API Key 等配置保存在本机安全存储中，反馈问题时请勿提交 Key、密码、验证码或 Cookie

### 课表与个性化

- 从教务系统导入课表，以周视图查看课程，并可快速回到当天
- 支持长按课程卡片进行临时调课，也可以从右上角进入调课方式选择
- 支持日期时间调课、单周次调课、批量周次调课和批量课程调课
- 支持将某一周次标记为不上课；临时安排独立保存，不会破坏原始课表
- 支持将当前课表导出为 ICS 文件并分享
- 根据已导入课表发送下一节课提醒，可选择提前 10、15、20 或 30 分钟通知
- 支持白天、黑夜与跟随系统三种显示模式，以及 10 种主题配色
- 支持从相册选择首页背景，并调整背景模糊程度

### 登录与本地数据

- 使用 HUNAU 统一身份认证登录
- 登录凭据使用 `flutter_secure_storage` 保存，支持下次启动自动登录
- Cookie、课表、通知、作业和部分页面数据会根据功能需要进行本地缓存
- 需要登录的功能会在进入时自动进行登录校验

### 帮助与反馈

- 帮助与反馈页面提供登录、Agent、课表调课、作业、通知和同步异常的使用说明
- FAQ 会解释常见的登录失败、Agent 配置错误、缓存未更新和课表显示差异
- 提交问题时建议附上页面名称、操作步骤、预期结果、实际结果、设备型号和应用版本
- 请勿在反馈中发送密码、API Key、验证码、Cookie 或其他敏感信息

## 技术栈

- **框架**：Flutter，Dart SDK `^3.11.4`
- **状态管理**：Riverpod、Provider
- **网络请求**：Dio、Cookie Jar、Dio Cookie Manager
- **网页服务**：`flutter_inappwebview`、`webview_flutter`
- **数据解析**：`html`
- **本地存储与安全**：Shared Preferences、Path Provider、Flutter Secure Storage、Crypto、Pointy Castle
- **版本更新**：通过 GitHub Releases 查询版本、展示更新说明并下载 APK 安装包
- **系统能力**：定位、二维码扫描、课程通知、图片选择、分享、URL 调起
- **界面与工具**：Material 3、Flutter SVG、Intl、Flutter Native Splash

## 项目结构

```text
smart_hunan_agri/
├── android/                  # Android 工程
├── ios/                      # iOS 工程
├── web/                      # Web 工程
├── linux/                    # Linux 工程
├── macos/                    # macOS 工程
├── windows/                  # Windows 工程
├── assets/                   # 应用图标等资源
├── lib/
│   ├── models/               # 数据模型和应用常量
│   ├── pages/                # 页面与业务界面
│   ├── providers/            # Riverpod 状态提供者
│   ├── services/             # 网络、认证、缓存和业务服务
│   ├── utils/                # 解析器、日期和工具类
│   ├── widgets/              # 可复用组件
│   └── main.dart             # 应用入口
├── test/                     # Flutter 测试
├── pubspec.yaml              # 依赖和 Flutter 配置
└── analysis_options.yaml     # Dart 静态检查配置
```

## 环境要求

建议使用以下环境：

- Flutter SDK（建议使用支持 Dart `^3.11.4` 的版本）
- Dart SDK `^3.11.4`，由 Flutter SDK 提供
- Android Studio、Android SDK 和 Android 模拟器，或已开启 USB 调试的 Android 真机
- Android 工程使用 Java 17 编译

先检查本机 Flutter 环境：

```bash
flutter doctor -v
flutter --version
```

## 安装与运行

在项目根目录执行：

```bash
# 获取依赖
flutter pub get

# 查看可用设备
flutter devices

# 启动开发版本
flutter run
```

也可以指定设备运行：

```bash
flutter run -d <device-id>
```

首次使用时，点击首页右上角头像登录学校统一身份认证。通知、作业、成绩、课表、校园卡、宿舍等依赖个人数据的功能，需要登录并保持网络可用；部分入口会打开学校或第三方 H5 页面。

## 编译构建

### Android APK

生成可直接安装的 Release APK：

```bash
flutter build apk --release
```

产物默认位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

如果需要按 ABI 拆分 APK：

```bash
flutter build apk --release --split-per-abi
```

### Android App Bundle

用于上传应用商店的 AAB：

```bash
flutter build appbundle --release
```

产物默认位于：

```text
build/app/outputs/bundle/release/app-release.aab
```

### iOS

在 macOS 上执行：

```bash
flutter build ios --release
```

之后使用 Xcode 打开 `ios/Runner.xcworkspace`，配置 Bundle Identifier、开发团队和签名证书，再进行真机安装或归档发布。

### 其他 Flutter 平台

当前仓库包含 Web、Linux、macOS 和 Windows 工程。如需构建对应平台，可使用：

```bash
flutter build web
flutter build linux
flutter build macos
flutter build windows
```

具体是否可用取决于本机平台、Flutter 开发环境以及相关插件对目标平台的支持情况。

## 测试与代码检查

```bash
# 静态检查
flutter analyze

# 运行全部测试
flutter test
```

## 致谢

- 本项目的部分源码实现参考了 [SoilZhu/ChillEast](https://github.com/SoilZhu/ChillEast)，感谢原作者的开源分享。
- 首页 UI 的设计灵感来自 [YumeYucca/YumeBox](https://github.com/YumeYucca/YumeBox)，感谢原作者提供的优秀设计思路。

## 注意事项

- 本项目依赖 HUNAU 校园系统及相关外部服务，服务地址、认证流程或页面结构变化可能影响登录和数据获取。
- 使用成绩、课表、通知、作业、校园卡等功能时，请使用本人校园账号，并妥善保护账号信息。
- 当前 Android `applicationId` 为 `com.example.smart_hunan_agri`，正式发布前建议修改为自己的正式包名。
- 当前 Android Release 构建配置使用 debug 签名，仅适合本地测试；正式发布前必须配置 release keystore 和签名信息。
- 使用定位、通知、相机、存储或网络相关功能时，请根据系统提示授予必要权限。

## 版本信息

- 应用版本：`1.0.3+3`
- 项目名称：`smart_hunan_agri`
- 应用展示名称：`HuanuBox`
