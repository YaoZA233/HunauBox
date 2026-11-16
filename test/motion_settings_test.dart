import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/motion_settings.dart';
import 'package:smart_hunan_agri/pages/motion_settings_page.dart';
import 'package:smart_hunan_agri/providers/motion_provider.dart';
import 'package:smart_hunan_agri/widgets/app_motion.dart';

ThemeData motionTheme(
  MotionSettings settings, {
  Brightness brightness = Brightness.light,
}) => ThemeData(
  brightness: brightness,
  colorSchemeSeed: Colors.green,
  extensions: [settings],
  pageTransitionsTheme: PageTransitionsTheme(
    builders: {
      for (final platform in TargetPlatform.values)
        platform: AppPageTransitionsBuilder(settings),
    },
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('动画偏好持久化，快速连续修改和启动时修改不被旧配置覆盖', () async {
    SharedPreferences.setMockInitialValues({
      MotionSettingsNotifier.storageKey: jsonEncode({'transition': 'cube'}),
    });
    final notifier = MotionSettingsNotifier();
    final first = notifier.update(
      const MotionSettings(transition: AppTransition.fade),
    );
    final second = notifier.update(
      const MotionSettings(
        transition: AppTransition.stack,
        speed: MotionSpeed.fast,
        pressFeedback: false,
        bouncyScroll: false,
        reduceMotion: true,
      ),
    );
    await Future.wait([notifier.ready, first, second]);
    expect(notifier.state.transition, AppTransition.stack);
    final restored = MotionSettingsNotifier();
    await restored.ready;
    expect(restored.state.toJson(), notifier.state.toJson());
    notifier.dispose();
    restored.dispose();
  });

  test('未知配置值和损坏的存储可以安全回退', () async {
    for (final legacy in ['cube', 'perspective']) {
      expect(
        MotionSettings.fromJson({
          'transition': legacy,
          'speed': 'fast',
        }).transition,
        AppTransition.slide,
      );
      expect(
        MotionSettings.fromJson({'transition': legacy, 'speed': 'fast'}).speed,
        MotionSpeed.fast,
      );
    }
    expect(
      MotionSettings.fromJson({
        'transition': 'old',
        'speed': 42,
        'pressFeedback': null,
      }).toJson(),
      const MotionSettings().toJson(),
    );
    SharedPreferences.setMockInitialValues({
      MotionSettingsNotifier.storageKey: '{broken',
    });
    final notifier = MotionSettingsNotifier();
    await notifier.ready;
    expect(notifier.state.transition, AppTransition.slide);
    notifier.dispose();
  });

  for (final style in AppTransition.values) {
    testWidgets('${style.label} 打开、动画中返回、再次打开均正常', (tester) async {
      final settings = MotionSettings(transition: style);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: motionTheme(settings),
          home: const Scaffold(body: Text('首页')),
        ),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('详情')),
      );
      navigator.currentState!.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        route.transitionDuration,
        style == AppTransition.none
            ? Duration.zero
            : const Duration(milliseconds: 300),
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('详情'), findsNothing);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('再次打开')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('再次打开'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('默认滑动保留 iOS 边缘返回手势，可中途取消或完成', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: motionTheme(
          const MotionSettings(),
        ).copyWith(platform: TargetPlatform.iOS),
        home: const Scaffold(body: Text('首页')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('详情'))),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsOneWidget);
    await tester.flingFrom(const Offset(1, 300), const Offset(650, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统减少动态效果覆盖转场、缩放和弹性滚动', (tester) async {
    const settings = MotionSettings(transition: AppTransition.stack);
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: motionTheme(settings),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const AppPressScale(pressed: true, child: Text('按压'));
            },
          ),
        ),
      ),
    );
    expect(settings.effectiveTransition(pageContext), AppTransition.fade);
    expect(settings.duration(pageContext).inMilliseconds, 100);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(
      const AppScrollBehavior().getScrollPhysics(pageContext),
      isA<ClampingScrollPhysics>(),
    );
  });

  testWidgets('按下、拖动取消和禁用按键反馈不会误触', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: motionTheme(const MotionSettings()),
        home: Scaffold(
          body: ListView(
            children: [
              AppPressable(
                onTap: () => taps++,
                child: const SizedBox(height: 100, child: Text('可按')),
              ),
              const AppPressable(
                child: SizedBox(height: 100, child: Text('禁用')),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('可按')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widgetList<AnimatedScale>(find.byType(AnimatedScale)).first.scale,
      .97,
    );
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(
      tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .every((w) => w.scale == 1),
      isTrue,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('可按'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.tap(find.text('禁用'));
    expect(taps, 1);
  });

  testWidgets('周日视图动画快速反向，保留两边列表滚动状态', (tester) async {
    final selection = ValueNotifier(0);
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(() {
      selection.dispose();
      first.dispose();
      second.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: motionTheme(
          const MotionSettings(transition: AppTransition.stack),
        ),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: selection,
            builder: (context, index, _) => AppMotionIndexedStack(
              index: index,
              children: [
                ListView(
                  controller: first,
                  children: const [SizedBox(height: 2000, child: Text('周'))],
                ),
                ListView(
                  controller: second,
                  children: const [SizedBox(height: 2000, child: Text('日'))],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    first.jumpTo(200);
    selection.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    selection.value = 0;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(first.offset, 200);
    expect(find.text('周'), findsOneWidget);
    expect(find.text('日'), findsNothing);
    selection.value = 1;
    await tester.pumpAndSettle();
    second.jumpTo(100);
    selection.value = 0;
    await tester.pumpAndSettle();
    selection.value = 1;
    await tester.pumpAndSettle();
    expect(second.offset, 100);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    testWidgets('设置 ${brightness.name} 窄屏大字体，选择效果、预览及恢复默认', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: motionTheme(const MotionSettings(), brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const MotionSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('transition-cube')), findsNothing);
      expect(
        find.byKey(const ValueKey('transition-perspective')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('transition-stack')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transition-stack')));
      await tester.pumpAndSettle();
      expect(
        container.read(motionSettingsProvider).transition,
        AppTransition.stack,
      );
      await tester.scrollUntilVisible(
        find.text('预览转场'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('预览转场'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('恢复默认动画'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认动画'));
      await tester.pumpAndSettle();
      expect(
        container.read(motionSettingsProvider).toJson(),
        const MotionSettings().toJson(),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
