// 离线视觉检查：flutter test --no-pub tool/agent_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide completion;
import 'package:smart_hunan_agri/pages/agent_page.dart';
import 'package:smart_hunan_agri/pages/agent_settings_page.dart';
import 'package:smart_hunan_agri/services/agent_service.dart';
import 'package:smart_hunan_agri/services/agent_tool_registry.dart';

import '../test/agent_service_test.dart'
    show config, AgentAdapter, completion, jsonResponse;
import '../test/agent_widget_test.dart' show app, memorySettings;

void main() {
  testWidgets('生成 Agent 欢迎、对话与配置的浅色、深色预览', (tester) async {
    final font = File('${Platform.environment['SystemRoot']}/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await tester.runAsync(() async {
        await (FontLoader('AgentPreview')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      });
    }
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      for (final kind in [
        'welcome',
        'chat',
        'reasoning',
        'history',
        'settings',
      ]) {
        final store = await memorySettings(config);
        final key = GlobalKey();
        final adapter = AgentAdapter(
          (_, _) => jsonResponse({
            ...completion({
              'content':
                  '今天有 2 门课：\n\n08:00–09:40　植物学\n第一教学楼 101\n\n14:30–16:10　土壤学\n第二教学楼 205\n\n以上来自本地课表，请留意临时调课通知。',
              'reasoning_content': '已根据课表查询工具的结果，按开始时间整理今天的课程，并保留教室信息。',
            }),
            'usage': {
              'prompt_tokens': 1024,
              'completion_tokens': 186,
              'prompt_cache_hit_tokens': 256,
              'completion_tokens_details': {'reasoning_tokens': 64},
            },
          }),
        );
        final screen = kind == 'settings'
            ? const AgentSettingsPage()
            : AgentPage(
                service: AgentService(dio: Dio()..httpClientAdapter = adapter),
                tools: AgentToolRegistry([]),
              );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: app(
              store,
              Theme(
                data: ThemeData(
                  useMaterial3: true,
                  brightness: brightness,
                  fontFamily: font.existsSync() ? 'AgentPreview' : null,
                  scaffoldBackgroundColor: brightness == Brightness.dark
                      ? const Color(0xFF121212)
                      : Colors.white,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF09C489),
                    brightness: brightness,
                  ),
                ),
                child: screen,
              ),
              brightness: brightness,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (['chat', 'reasoning', 'history'].contains(kind)) {
          await tester.enterText(find.byType(TextField), '今天有哪些课，分别在哪上？');
          await tester.tap(find.byTooltip('发送'));
          await tester.pumpAndSettle();
          if (kind == 'reasoning') {
            await tester.tap(find.text('思考内容'));
            await tester.pumpAndSettle();
          }
          if (kind == 'history') {
            await tester.tap(find.byTooltip('聊天记录'));
            await tester.pumpAndSettle();
          }
        }
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/agent_previews/$kind-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
