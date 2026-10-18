import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared, selectable Markdown for release notes and chat content.
class AppMarkdown extends StatelessWidget {
  const AppMarkdown({
    super.key,
    required this.data,
    this.textColor,
    this.fontSize,
    this.baseUri,
    this.onOpenLink,
  });

  final String data;
  final Color? textColor;
  final double? fontSize;
  final Uri? baseUri;
  final Future<bool> Function(Uri uri)? onOpenLink;

  Uri? _resolve(String href) {
    final uri = Uri.tryParse(href);
    return uri == null ? null : baseUri?.resolveUri(uri) ?? uri;
  }

  Future<void> _openLink(BuildContext context, String? href) async {
    final uri = href == null ? null : _resolve(href);
    var opened = false;
    if (uri != null &&
        ((const ['https', 'http'].contains(uri.scheme) &&
                uri.host.isNotEmpty) ||
            uri.scheme == 'mailto')) {
      try {
        opened =
            await (onOpenLink?.call(uri) ??
                launchUrl(uri, mode: LaunchMode.externalApplication));
      } catch (_) {}
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('无法打开此链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = textColor ?? colors.onSurface;
    final body = theme.textTheme.bodyMedium!.copyWith(
      color: color,
      fontSize: fontSize,
      height: 1.55,
    );
    TextStyle heading(TextStyle? style) =>
        style!.copyWith(color: color, height: 1.4, fontWeight: FontWeight.w700);
    return MarkdownBody(
      data: data,
      selectable: true,
      fitContent: false,
      softLineBreak: true,
      onTapLink: (_, href, _) => _openLink(context, href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body,
        h1: heading(theme.textTheme.headlineSmall),
        h2: heading(theme.textTheme.titleLarge),
        h3: heading(theme.textTheme.titleMedium),
        h4: heading(theme.textTheme.titleSmall),
        h5: heading(theme.textTheme.bodyLarge),
        h6: heading(theme.textTheme.bodyMedium),
        a: TextStyle(
          color: color,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
        listBullet: body,
        blockquote: body,
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
          borderRadius: BorderRadius.circular(4),
        ),
        code: body.copyWith(
          fontFamily: 'monospace',
          fontSize: (fontSize ?? body.fontSize!) * 0.9,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        tableHead: body.copyWith(fontWeight: FontWeight.w700),
        tableBody: body,
        tableBorder: TableBorder.all(color: colors.outlineVariant),
        // Fixed readable cells enable the renderer's own horizontal scroller.
        tableColumnWidth: FixedColumnWidth(
          160 * MediaQuery.textScalerOf(context).scale(14) / 14,
        ),
        tableScrollbarThumbVisibility: true,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
      ),
      imageBuilder: (source, title, alt) {
        final uri = _resolve(source.toString());
        final fallback = Text(
          alt?.isNotEmpty == true ? alt! : '图片暂不可用',
          style: body,
        );
        if (uri == null ||
            !const ['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          return fallback;
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            semanticLabel: alt,
            errorBuilder: (_, _, _) => fallback,
          ),
        );
      },
    );
  }
}
