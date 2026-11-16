import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/agent_models.dart';
import 'package:smart_hunan_agri/widgets/agent_message_bubble.dart';
import 'package:smart_hunan_agri/widgets/app_markdown.dart';

const sampleMarkdown = '''
# 今日课程

这是 **重点**，以及 `inline code`。

- 高等数学
- 英语

> 记得携带课本

| 时间 | 课程 | 教室 |
| --- | --- | --- |
| 08:00 | 农业生态环境保护与可持续发展 | 八教北223 |

```dart
final veryLongVariableName = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789';
```
''';

void main() {
  testWidgets('标题、粗体、列表、表格和代码按 Markdown 渲染且可选择', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AppMarkdown(data: sampleMarkdown)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('今日课程'), findsOneWidget);
    expect(find.text('# 今日课程'), findsNothing);
    expect(find.text('这是 重点，以及 inline code。'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).selectable,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击链接按相对发布页地址解析，打开失败有反馈', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMarkdown(
            data: '[发布说明](/YaoZA233/HunauBox/releases)\n\n[不可用](unknown:abc)',
            baseUri: Uri.parse(
              'https://github.com/YaoZA233/HunauBox/releases/tag/v1.0.6',
            ),
            onOpenLink: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布说明'));
    await tester.pumpAndSettle();
    expect(
      opened.single.toString(),
      'https://github.com/YaoZA233/HunauBox/releases',
    );
    await tester.tap(find.text('不可用'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开此链接'), findsOneWidget);
    expect(opened, hasLength(1));
  });

  testWidgets('Agent 的回复和思考均渲染 Markdown，复制保留完整原文', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentMessageBubble(
              message: AgentDisplayMessage(
                'assistant',
                '**回答**\n\n- 课程信息',
                reasoning: '## 思考标题\n\n依据课表',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('回答'), findsOneWidget);
    expect(find.text('**回答**'), findsNothing);
    await tester.tap(find.text('思考内容'));
    await tester.pumpAndSettle();
    expect(find.text('思考标题'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNWidgets(2));
    await tester.tap(find.byTooltip('复制消息'));
    await tester.pumpAndSettle();
    expect(copied, '**回答**\n\n- 课程信息');
  });

  for (final brightness in Brightness.values) {
    testWidgets('Markdown 在 320px 两倍字体 $brightness 下可横向滚动且无溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final theme = ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
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
                child: AgentMessageBubble(
                  message: AgentDisplayMessage('assistant', sampleMarkdown),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final horizontal = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsNWidgets(2));
      for (final scroll in horizontal.evaluate().map(
        (e) => e.widget as SingleChildScrollView,
      )) {
        expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(body.styleSheet!.p!.color, theme.colorScheme.onSurface);
      expect(body.styleSheet!.code!.color, theme.colorScheme.onSurface);
    });
  }
}
