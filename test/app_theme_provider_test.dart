import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/motion_settings.dart';
import 'package:smart_hunan_agri/providers/app_theme_provider.dart';
import 'package:smart_hunan_agri/providers/background_provider.dart';
import 'package:smart_hunan_agri/providers/motion_provider.dart';
import 'package:smart_hunan_agri/providers/theme_provider.dart';
import 'package:smart_hunan_agri/widgets/app_motion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('切换动画不重建基础主题（无 fromSeed 重算）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Let the async preference loads settle so they can't invalidate the
    // cached base theme mid-test.
    container.read(appBackgroundProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final before = container.read(baseAppThemeProvider(Brightness.light));
    await container
        .read(motionSettingsProvider.notifier)
        .update(const MotionSettings(transition: AppTransition.stack));
    final after = container.read(baseAppThemeProvider(Brightness.light));

    expect(identical(before, after), isTrue);
  });

  test('切换深浅色各自缓存，互不重算', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final light = container.read(baseAppThemeProvider(Brightness.light));
    final dark = container.read(baseAppThemeProvider(Brightness.dark));
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(identical(light, dark), isFalse);

    expect(
      identical(light, container.read(baseAppThemeProvider(Brightness.light))),
      isTrue,
    );
    expect(
      identical(dark, container.read(baseAppThemeProvider(Brightness.dark))),
      isTrue,
    );
  });

  test('改变主题色重建基础主题并反映新主色', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const newColor = Color(0xFFFF5722);
    final before = container.read(baseAppThemeProvider(Brightness.light));
    await container
        .read(themeColorProvider.notifier)
        .updateThemeColor(newColor);
    final after = container.read(baseAppThemeProvider(Brightness.light));

    expect(identical(before, after), isFalse);
    expect(after.colorScheme.primary, newColor);
  });

  test('应用动画到基础主题保留配色并安装动画扩展与转场', () {
    const motion = MotionSettings(
      transition: AppTransition.stack,
      speed: MotionSpeed.fast,
    );
    final base = buildBaseAppTheme(
      themeColor: const Color(0xFF09C489),
      background: const AppBackgroundSettings(),
      brightness: Brightness.light,
    );

    final themed = applyMotionToTheme(base, motion);

    expect(themed.colorScheme.primary, base.colorScheme.primary);
    expect(themed.extension<MotionSettings>()?.toJson(), motion.toJson());

    final builder =
        themed.pageTransitionsTheme.builders[TargetPlatform.android];
    expect(builder, isA<AppPageTransitionsBuilder>());
    expect(
      (builder! as AppPageTransitionsBuilder).transitionDuration,
      const Duration(milliseconds: 220),
    );
  });

  test('无动画转场时长为零', () {
    const motion = MotionSettings(transition: AppTransition.none);
    final base = buildBaseAppTheme(
      themeColor: const Color(0xFF09C489),
      background: const AppBackgroundSettings(),
      brightness: Brightness.light,
    );
    final themed = applyMotionToTheme(base, motion);
    final builder =
        themed.pageTransitionsTheme.builders[TargetPlatform.android]!
            as AppPageTransitionsBuilder;
    expect(builder.transitionDuration, Duration.zero);
  });
}
