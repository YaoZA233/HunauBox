import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/pages/about_page.dart';
import 'package:smart_hunan_agri/pages/main_navigator.dart';
import 'package:smart_hunan_agri/pages/settings_page.dart';
import 'package:smart_hunan_agri/services/app_update_notifier.dart';
import 'package:smart_hunan_agri/services/app_update_service.dart';
import 'package:smart_hunan_agri/services/agent_settings_store.dart';

import 'app_update_service_test.dart' show releaseWith;

class FakeUpdateNotifier extends AppUpdateNotifier {
  final progressUpdates = <String>[];
  String? completedFile;
  String? failedMessage;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> showProgress({required int received, required int total}) async {
    progressUpdates.add('$received/$total');
  }

  @override
  Future<void> showCompleted(String fileName) async {
    completedFile = fileName;
  }

  @override
  Future<void> showFailed(String message) async {
    failedMessage = message;
  }

  @override
  Future<void> cancel() async {}
}

Widget settingsApp() => ProviderScope(
  overrides: [
    agentSettingsProvider.overrideWith((ref) {
      final store = AgentSettingsStore(
        read: () async => null,
        write: (_) async {},
        delete: () async {},
      );
      unawaited(store.load());
      return store;
    }),
  ],
  child: const MaterialApp(home: SettingsPage()),
);

class FakeUpdateService extends AppUpdateService {
  FakeUpdateService({this.pendingDownload});
  final Completer<File>? pendingDownload;
  AppRelease? downloadedRelease;
  UpdateSource? requestedSource;
  void Function(int, int)? progress;
  @override
  Future<AppRelease> fetchLatest([UpdateSource? source]) async {
    requestedSource = source;
    return releaseWith([
      'app-debug.apk',
      'app-release.apk',
    ], body: '## 本次改进\n\n- **修复** 下载选择\n- 支持 `Markdown`');
  }

  @override
  Future<File> downloadApk(
    AppRelease release, {
    void Function(int, int)? onProgress,
  }) async {
    downloadedRelease = release;
    progress = onProgress;
    return pendingDownload?.future ?? File('app-release.apk');
  }
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'HunauBox',
      packageName: 'test',
      version: '1.0.5',
      buildNumber: '5',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('更新弹层渲染 Markdown，并显示和下载正式 APK', (tester) async {
    final service = FakeUpdateService();
    final notifier = FakeUpdateNotifier();
    String? installedPath;
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(
          updateService: service,
          updateNotifier: notifier,
          openInstaller: (path) async {
            installedPath = path;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本次改进'), findsOneWidget);
    expect(find.text('## 本次改进'), findsNothing);
    expect(find.textContaining('app-release.apk'), findsOneWidget);
    expect(find.textContaining('app-debug.apk'), findsNothing);
    expect(find.byType(MarkdownBody), findsOneWidget);
    await tester.ensureVisible(find.text('下载 APK'));
    await tester.tap(find.text('下载 APK'));
    await tester.pumpAndSettle();
    expect(service.downloadedRelease!.apk!.name, 'app-release.apk');
    expect(notifier.completedFile, 'app-release.apk');
    expect(installedPath, 'app-release.apk');
    expect(find.textContaining('正在打开安装界面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final source in UpdateSource.values) {
    testWidgets('设置页可选择并保存 ${source.label} 下载源', (tester) async {
      await tester.pumpWidget(settingsApp());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('更新下载渠道'), 400);
      await tester.tap(find.text('更新下载渠道'));
      await tester.pumpAndSettle();
      expect(find.text('Gitee (默认推荐)'), findsOneWidget);
      expect(find.text('GitHub (国际线路)'), findsOneWidget);
      await tester.tap(
        find.text(
          source == UpdateSource.gitee ? 'Gitee (默认推荐)' : 'GitHub (国际线路)',
        ),
      );
      await tester.pumpAndSettle();
      expect(await AppUpdateService.getPreferredSource(), source);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(settingsApp());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('更新下载渠道'), 400);
      expect(
        find.text(
          source == UpdateSource.gitee ? 'Gitee (国内高速推荐)' : 'GitHub (国际源)',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('关于页使用 ${source.label} 选项并显示双仓库入口', (tester) async {
      await AppUpdateService.setPreferredSource(source);
      final service = FakeUpdateService();
      await tester.pumpWidget(
        MaterialApp(
          home: AboutPage(
            updateService: service,
            updateNotifier: FakeUpdateNotifier(),
            openInstaller: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.requestedSource, source);
      Navigator.of(tester.element(find.byType(MarkdownBody))).pop();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Gitee 仓库'), 200);
      expect(find.text('国内访问推荐'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('GitHub 仓库'), 200);
      expect(find.text('查看源代码与版本发布'), findsOneWidget);
      await AppUpdateService.setPreferredSource(
        source == UpdateSource.gitee ? UpdateSource.github : UpdateSource.gitee,
      );
      await tester.ensureVisible(find.text('检查软件更新'));
      await tester.tap(find.text('检查软件更新'));
      await tester.pumpAndSettle();
      expect(service.requestedSource, isNot(source));
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(320, 700),
    const Size(375, 812),
    const Size(812, 375),
    const Size(1024, 768),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('关于页 $size $brightness 大字体文字完整且入口可见', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        PackageInfo.setMockInitialValues(
          appName: 'HunauBox',
          packageName: 'test',
          version: '1.0.8-beta.123456789',
          buildNumber: '8',
          buildSignature: '',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              colorSchemeSeed: Colors.green,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AboutPage(
              updateService: FakeUpdateService(),
              updateNotifier: FakeUpdateNotifier(),
              openInstaller: (_) async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final text in [
          '当前版本',
          '1.0.8-beta.123456789',
          '检查软件更新',
          'Gitee 仓库',
          'GitHub 仓库',
        ]) {
          await tester.scrollUntilVisible(
            find.text(text),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text(text), findsOneWidget);
          final render = tester.renderObject<RenderParagraph>(find.text(text));
          expect(render.didExceedMaxLines, isFalse);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('关闭下载中的更新弹层，迟到的进度和结果不会更新已销毁弹层', (tester) async {
    final pending = Completer<File>();
    final service = FakeUpdateService(pendingDownload: pending);
    final notifier = FakeUpdateNotifier();
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(
          updateService: service,
          updateNotifier: notifier,
          openInstaller: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下载 APK'));
    await tester.tap(find.text('下载 APK'));
    await tester.pump();
    Navigator.of(tester.element(find.byType(MarkdownBody))).pop();
    await tester.pumpAndSettle();
    service.progress!(2, 4);
    pending.complete(File('app-release.apk'));
    await tester.pumpAndSettle();
    expect(notifier.progressUpdates, ['0/0', '2/4']);
    expect(tester.takeException(), isNull);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('更新说明窄屏两倍字体 $brightness 下完整显示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            colorSchemeSeed: Colors.green,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AboutPage(
            updateService: FakeUpdateService(),
            updateNotifier: FakeUpdateNotifier(),
            openInstaller: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('下载 APK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Agent 导航入口采用星芒图标，仍打开原 Agent 入口', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 78,
            child: CampusNavigationRail(
              agentEnabled: true,
              showSystemStatus: false,
              onChanged: (index) => tapped = index,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    expect(tapped, 3);
  });
}
