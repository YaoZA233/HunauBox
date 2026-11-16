import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/pages/onboarding_page.dart';
import 'package:smart_hunan_agri/services/onboarding_store.dart';

import 'about_update_page_test.dart' show settingsApp;

class FailingStore extends OnboardingStore {
  const FailingStore();
  @override
  Future<bool> isComplete() async => false;
  @override
  Future<void> complete() async => throw StateError('disk error');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('首次完成后持久化，重新打开直接进入首页', (tester) async {
    var ready = 0;
    Widget app() => MaterialApp(
      home: OnboardingGate(
        onReady: () => ready++,
        child: const Scaffold(body: Text('测试首页')),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('先看看功能在哪里'), findsOneWidget);
    expect(find.text('测试首页'), findsNothing);
    for (final title in [
      '登录后同步校园信息',
      '导入课表，查看每天安排',
      '课程与消息分开查看',
      '把学习事项找出来',
      '把常用信息放在一页',
      '按需要开启，再随时回来',
    ]) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    expect(find.text('把常用信息放在一页'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
    expect(find.text('测试首页'), findsOneWidget);
    expect(ready, 1);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        OnboardingStore.completionKey,
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('测试首页'), findsOneWidget);
    expect(find.text('先看看功能在哪里'), findsNothing);
    expect(ready, 2);
  });

  testWidgets('跳过后不再自动显示，返回键也可结束首次引导', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingGate(child: Scaffold(body: Text('首页'))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        OnboardingStore.completionKey,
      ),
      isTrue,
    );
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingGate(child: Scaffold(body: Text('首页'))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        OnboardingStore.completionKey,
      ),
      isTrue,
    );
  });

  testWidgets('写入失败仍可使用并提示可能再次显示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingGate(
          store: FailingStore(),
          child: Scaffold(body: Text('首页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('未能记住引导状态，下次打开时可能再次显示'), findsOneWidget);
  });

  testWidgets('设置中可以重看和关闭引导', (tester) async {
    await tester.pumpWidget(settingsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用引导'));
    await tester.pumpAndSettle();
    expect(find.text('先看看功能在哪里'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        OnboardingStore.completionKey,
      ),
      isNull,
    );
  });

  for (final size in [
    const Size(320, 700),
    const Size(812, 375),
    const Size(1024, 768),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('大字体、减少动画和 $brightness 下适配 $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              colorSchemeSeed: Colors.green,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const OnboardingPage(firstRun: true),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 6; i++) {
          await tester.ensureVisible(find.text('使用时留意'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('下一步'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.text('使用时留意'));
        await tester.pumpAndSettle();
        expect(find.text('开始使用'), findsOneWidget);
      });
    }
  }

  testWidgets('目录可直接跳到指定教程，继续与返回都有效', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage(firstRun: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('教程目录'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('课程与消息分开查看'));
    await tester.tap(find.text('课程与消息分开查看'));
    await tester.pumpAndSettle();
    expect(find.text('课程与消息分开查看'), findsOneWidget);
    expect(find.text('左侧功能 → 学习通课程 / 学习通消息'), findsOneWidget);
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    expect(find.text('导入课表，查看每天安排'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('课程与消息分开查看'), findsOneWidget);
  });

  testWidgets('横屏大字体下目录可滚动并跳至最后主题', (tester) async {
    tester.view.physicalSize = const Size(700, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const OnboardingPage(firstRun: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('教程目录'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Agent 与设置'),
      180,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Agent 与设置'));
    await tester.pumpAndSettle();
    expect(find.text('按需要开启，再随时回来'), findsOneWidget);
    expect(find.text('开始使用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
