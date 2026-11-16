import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/providers/app_theme_provider.dart';
import 'package:smart_hunan_agri/providers/background_provider.dart';
import 'package:smart_hunan_agri/providers/font_provider.dart';
import 'package:smart_hunan_agri/widgets/font_settings_section.dart';

import 'about_update_page_test.dart' show settingsApp;

Uint8List testFont() {
  final tags = ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'loca', 'glyf'];
  final headerSize = 12 + tags.length * 16;
  final bytes = Uint8List(headerSize + tags.length);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, tags.length);
  for (var i = 0; i < tags.length; i++) {
    final at = 12 + i * 16;
    bytes.setRange(at, at + 4, ascii.encode(tags[i]));
    data.setUint32(at + 8, headerSize + i);
    data.setUint32(at + 12, 1);
    bytes[headerSize + i] = i + 1;
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final actualFont = [
    'C:/Windows/Fonts/arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
  ].where((path) => File(path).existsSync()).firstOrNull;

  testWidgets('选择真实 TTF 后设置界面立即应用并可恢复默认', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('hunaubox_font_real_'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final container = ProviderContainer(
      overrides: [
        fontFilePickerProvider.overrideWithValue(
          () async => SelectedFontFile(path: actualFont!, name: 'test.ttf'),
        ),
        appFontProvider.overrideWith(
          (ref) => AppFontNotifier(directory: () async => directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appFontProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final font = ref.watch(appFontProvider);
            return MaterialApp(
              theme: buildBaseAppTheme(
                themeColor: Colors.green,
                background: const AppBackgroundSettings(),
                brightness: Brightness.light,
                fontFamily: font.family,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(child: FontSettingsSection()),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('导入字体'));
      for (
        var i = 0;
        i < 100 && !container.read(appFontProvider).isCustom;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    final imported = container.read(appFontProvider);
    expect(imported.isCustom, true);
    expect(find.text('test.ttf'), findsOneWidget);
    expect(
      Theme.of(
        tester.element(find.text('应用字体')),
      ).textTheme.bodyLarge!.fontFamily,
      imported.family,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('恢复默认字体'));
      for (
        var i = 0;
        i < 100 && container.read(appFontProvider).isCustom;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(container.read(appFontProvider).family, isNull);
    expect(find.text('当前使用系统默认字体'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: actualFont == null);

  test('导入字体、重新启动加载和恢复默认，不删除原文件', () async {
    final dir = await Directory.systemTemp.createTemp('hunaubox_font_test_');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/selected.ttf');
    await source.writeAsBytes(testFont());
    final appDir = Directory('${dir.path}/app');
    final loads = <String>[];
    Future<void> register(String family, Uint8List bytes) async =>
        loads.add(family);
    final first = AppFontNotifier(
      directory: () async => appDir,
      register: register,
    );
    await first.ready;
    await first.importFont(
      SelectedFontFile(path: source.path, name: '自选字体.ttf'),
    );
    final family = first.state.family!;
    expect(first.state.name, '自选字体.ttf');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppFontNotifier.preferenceKey), isNotNull);
    expect(appDir.listSync().whereType<File>(), hasLength(1));
    first.dispose();
    final second = AppFontNotifier(
      directory: () async => appDir,
      register: register,
    );
    await second.ready;
    expect(second.state.family, family);
    expect(loads, [family, family]);
    for (final brightness in Brightness.values) {
      final theme = buildBaseAppTheme(
        themeColor: Colors.green,
        background: const AppBackgroundSettings(),
        brightness: brightness,
        fontFamily: family,
      );
      expect(theme.textTheme.bodyLarge!.fontFamily, family);
      expect(theme.appBarTheme.titleTextStyle!.fontFamily, family);
    }
    await second.reset();
    expect(second.state.isCustom, false);
    expect(prefs.getString(AppFontNotifier.preferenceKey), isNull);
    expect(appDir.listSync(), isEmpty);
    expect(await source.exists(), isTrue);
    second.dispose();
  });

  test('无效文件或加载失败保留当前字体；缺失字体会回退默认', () async {
    final dir = await Directory.systemTemp.createTemp('hunaubox_font_failure_');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/good.ttf');
    await source.writeAsBytes(testFont());
    final invalid = File('${dir.path}/broken.ttf');
    await invalid.writeAsString('not a font');
    final appDir = Directory('${dir.path}/app');
    var failRegistration = false;
    final notifier = AppFontNotifier(
      directory: () async => appDir,
      register: (_, _) async {
        if (failRegistration) throw StateError('bad font');
      },
    );
    await notifier.ready;
    await notifier.importFont(
      SelectedFontFile(path: source.path, name: 'good.ttf'),
    );
    final before = notifier.state.family;
    await expectLater(
      notifier.importFont(
        SelectedFontFile(path: invalid.path, name: 'broken.ttf'),
      ),
      throwsA(isA<FontImportException>()),
    );
    expect(notifier.state.family, before);
    final otherBytes = testFont()..last = 42;
    final other = File('${dir.path}/other.ttf');
    await other.writeAsBytes(otherBytes);
    failRegistration = true;
    await expectLater(
      notifier.importFont(
        SelectedFontFile(path: other.path, name: 'other.ttf'),
      ),
      throwsA(isA<FontImportException>()),
    );
    expect(notifier.state.family, before);
    expect(appDir.listSync().whereType<File>(), hasLength(1));
    notifier.dispose();
    await appDir.listSync().whereType<File>().single.delete();
    final reopened = AppFontNotifier(
      directory: () async => appDir,
      register: (_, _) async {},
    );
    await reopened.ready;
    expect(reopened.state.family, isNull);
    expect(reopened.state.error, contains('默认字体'));
    reopened.dispose();
  });

  test('校验截断的字体表并拒绝伪装文件', () {
    expect(
      () => AppFontNotifier.validate(Uint8List.fromList([0, 1, 0, 0])),
      throwsA(isA<FontImportException>()),
    );
    final bad = testFont();
    ByteData.sublistView(bad).setUint32(12 + 8, 0x7fffffff);
    expect(
      () => AppFontNotifier.validate(bad),
      throwsA(isA<FontImportException>()),
    );
  });

  testWidgets('设置页面提供字体导入入口', (tester) async {
    await tester.pumpWidget(settingsApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('应用字体'), 300);
    expect(find.text('导入字体'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('字体设置在窄屏大字体与 $brightness 下可取消选择', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var picks = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fontFilePickerProvider.overrideWithValue(() async {
              picks++;
              return null;
            }),
          ],
          child: MaterialApp(
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
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: FontSettingsSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前使用系统默认字体'), findsOneWidget);
      await tester.tap(find.text('导入字体'));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(find.text('当前使用系统默认字体'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
