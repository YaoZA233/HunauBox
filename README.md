# Hunau Smart Compus Life

基于 Flutter 开发的智慧校园移动端应用程序，旨在提供便捷的校园生活服务

## ✨ 主要功能 (Features)

通过本项目集成的依赖包，应用主要涵盖以下核心能力：

- **强大的网络通信**：基于 `dio` 进行网络请求，配合 `cookie_jar` 实现会话和 Cookie 的持久化管理。
- **现代状态管理**：主要采用 `flutter_riverpod` (及 `provider`)，实现可预测且解耦的数据与状态管理。
- **Web 容器互通**：内置 `flutter_inappwebview` 与 `webview_flutter`，能高效加载外部或内部 H5 页面进行混合开发。
- **本地存储与数据安全**：利用 `shared_preferences` 存储常规配置，`flutter_secure_storage` 和 `crypto`/`pointycastle` 提供敏感凭证的加密保存。

## 🛠 技术栈 (Tech Stack)

- **框架 (Framework)**: [Flutter](https://flutter.dev/) (SDK: ^3.11.4)
- **网络 (Networking)**: dio, dio_cookie_manager, html (网页解析)
- **状态管理 (State Management)**: riverpod
- **工具/UI库 (Tools/UI)**: flutter_svg, flutter_native_splash, intl

## 📂 目录结构 (Project Structure)

```text
lib/
├── models/       # 数据模型层 (Model classes for JSON parsing, etc.)
├── pages/        # 视图页面层 (App screens and pages)
├── providers/    # 状态管理层 (Riverpod providers)
├── services/     # 业务服务层 (API requests, database ops, etc.)
├── utils/        # 帮助/工具类 (Constants, theme, extensions)
├── widgets/      # 自定义公共组件 (Reusable UI components)
└── main.dart     # 应用程序入口
```

## 🚀 快速启动 (Getting Started)

### 环境要求 (Prerequisites)

- 请确保你的环境已安装了 [Flutter SDK](https://docs.flutter.dev/get-started/install) （版本 ^3.11.4+ 推荐）。

### 运行项目 (Running the App)

1. 克隆或下载本项目源码。
2. 在项目根目录，获取相关的依赖项：

   ```bash
   flutter pub get
   ```

3. 可选：如果你修改了启动页图标或配置，可以同步更新一下（利用自动化命令）：

   ```bash
   # flutter pub run flutter_launcher_icons:main
   # flutter pub run flutter_native_splash:create
   ```

4. 启动应用：

   ```bash
   flutter run
   ```
