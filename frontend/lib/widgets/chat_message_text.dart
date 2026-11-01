import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

TextDirection chatTextDirection(String text, TextDirection fallback) {
  // Digits/punctuation are neutral. The first strong script chooses the
  // paragraph base; Flutter's Unicode bidi algorithm handles embedded runs.
  for (final rune in text.runes) {
    if (rune >= 0x0620 && rune <= 0x064a ||
        rune >= 0x066e && rune <= 0x06d3 ||
        rune >= 0x06fa && rune <= 0x06ff ||
        rune >= 0x0750 && rune <= 0x077f ||
        rune >= 0x08a0 && rune <= 0x08c9) {
      return TextDirection.rtl;
    }
    if (rune >= 0x0041 && rune <= 0x005a ||
        rune >= 0x0061 && rune <= 0x007a ||
        rune >= 0x00c0 && rune <= 0x02af ||
        rune >= 0x0400 && rune <= 0x052f ||
        rune >= 0x3040 && rune <= 0x30ff ||
        rune >= 0x4e00 && rune <= 0x9fff) {
      return TextDirection.ltr;
    }
  }
  return fallback;
}

class ChatMessageText extends StatefulWidget {
  const ChatMessageText(
    this.text, {
    super.key,
    required this.style,
    this.markdown = false,
  });

  final String text;
  final TextStyle style;
  final bool markdown;

  @override
  State<ChatMessageText> createState() => _ChatMessageTextState();
}

class _ChatMessageTextState extends State<ChatMessageText> {
  List<md.Node> _nodes = const [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(ChatMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text ||
        widget.markdown != oldWidget.markdown) {
      _parse();
    }
  }

  void _parse() {
    _nodes = widget.markdown
        ? md.Document(
            extensionSet: md.ExtensionSet.gitHubFlavored,
            encodeHtml: false,
          ).parseLines(const LineSplitter().convert(widget.text))
        : const [];
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Directionality.of(context);
    final style = DefaultTextStyle.of(context).style
        .merge(widget.style)
        .copyWith(
          fontFamilyFallback: const [
            'Tahoma',
            'Arial',
            'Segoe UI Emoji',
            'Microsoft YaHei',
            'Meiryo',
          ],
        );
    if (widget.markdown) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < _nodes.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            Directionality(
              textDirection: chatTextDirection(
                _nodes[index].textContent,
                fallback,
              ),
              child: _ChatMarkdownBlock(node: _nodes[index], style: style),
            ),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paragraph in widget.text.split('\n'))
          Text(
            paragraph,
            textDirection: chatTextDirection(paragraph, fallback),
            textAlign:
                chatTextDirection(paragraph, fallback) == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left,
            style: style,
          ),
      ],
    );
  }
}

/// Use the package's full GFM renderer, with a paragraph-specific direction.
/// The app owns only theme styling and user-initiated, web-only link opening.
class _ChatMarkdownBlock extends StatefulWidget {
  const _ChatMarkdownBlock({required this.node, required this.style});

  final md.Node node;
  final TextStyle style;

  @override
  State<_ChatMarkdownBlock> createState() => _ChatMarkdownBlockState();
}

class _ChatMarkdownBlockState extends State<_ChatMarkdownBlock>
    implements MarkdownBuilderDelegate {
  final List<GestureRecognizer> _recognizers = [];
  List<Widget> _children = const [];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _render();
  }

  @override
  void didUpdateWidget(_ChatMarkdownBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node || oldWidget.style != widget.style) {
      _render();
    }
  }

  void _render() {
    _disposeRecognizers();
    final style = widget.style;
    final color = style.color ?? Theme.of(context).colorScheme.onSurface;
    final heading = style.copyWith(fontWeight: FontWeight.w700);
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: style,
      strong: const TextStyle(fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      a: style.copyWith(decoration: TextDecoration.underline),
      h1: heading,
      h2: heading,
      h3: heading,
      h4: heading,
      h5: heading,
      h6: heading,
      code: style.copyWith(backgroundColor: color.withValues(alpha: .06)),
      codeblockDecoration: BoxDecoration(
        color: color.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(8),
      blockquote: style,
      blockquoteDecoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: color.withValues(alpha: .18), width: 2),
        ),
      ),
      blockquotePadding: const EdgeInsetsDirectional.only(
        start: 8,
      ).resolve(Directionality.of(context)),
      listBullet: style,
      listIndent: 20,
      tableHead: heading,
      tableBody: style,
      tableBorder: TableBorder.all(color: color.withValues(alpha: .18)),
      tableCellsPadding: const EdgeInsets.all(6),
      blockSpacing: 8,
    );
    _children = MarkdownBuilder(
      delegate: this,
      selectable: false,
      styleSheet: sheet,
      imageDirectory: null,
      // A model answer must not automatically fetch tracking images or read
      // local files. Keep the human-readable image description instead.
      imageBuilder: (uri, title, alt) =>
          Text(alt ?? uri.toString(), style: style),
      checkboxBuilder: null,
      bulletBuilder: null,
      builders: const {},
      paddingBuilders: const {},
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      fitContent: false,
      softLineBreak: true,
    ).build([widget.node]);
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final uri = href == null ? null : Uri.tryParse(href);
    final allowed =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    final recognizer = TapGestureRecognizer();
    if (allowed) {
      recognizer.onTap = () async {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          // Link failure must not interrupt or mutate the conversation.
        }
      };
    }
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) => TextSpan(
    style: styleSheet.code,
    text: code.replaceFirst(RegExp(r'\n$'), ''),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _children,
  );

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }
}
