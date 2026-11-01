import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/widgets/chat_message_text.dart';

void main() {
  test('neutral prices do not reverse the first strong language', () {
    expect(
      chatTextDirection('24,000,000 تومان برای GOLD18', TextDirection.ltr),
      TextDirection.rtl,
    );
    expect(
      chatTextDirection('BTC: قیمت 65,000 USDT', TextDirection.rtl),
      TextDirection.ltr,
    );
    expect(
      chatTextDirection('Évolution BTC و طلا', TextDirection.rtl),
      TextDirection.ltr,
    );
    expect(
      chatTextDirection('۲۴۰۰۰۰۰۰ تومان', TextDirection.ltr),
      TextDirection.rtl,
    );
    expect(chatTextDirection('123.45', TextDirection.rtl), TextDirection.rtl);
  });
  testWidgets(
    'mixed paragraphs preserve exact text and per-paragraph direction',
    (tester) async {
      const text =
          'قیمت BTC برابر 65,000 USDT است.\nBTC price: 65,000 USDT\nمنبع: https://example.com/BTC';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: ChatMessageText(
                text,
                style: TextStyle(
                  fontFamily: 'Segoe UI',
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
            ),
          ),
        ),
      );
      final paragraphs = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(paragraphs.map((p) => p.data).join('\n'), text);
      expect(paragraphs.map((p) => p.textDirection).toList(), [
        TextDirection.rtl,
        TextDirection.ltr,
        TextDirection.rtl,
      ]);
      expect(paragraphs.first.style!.fontFamily, 'Segoe UI');
      expect(paragraphs.first.style!.fontFamilyFallback, contains('Tahoma'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assistant Markdown renders emphasis and lists without raw markers',
    (tester) async {
      await tester.pumpWidget(
        _markdownHost(
          'قیمت **BTC** حدود *65,000 USDT* است.\n\n- منبع معتبر\n- ~~قدیمی~~ تأخیری\n\n1. بررسی زمان\n2. بررسی واحد',
        ),
      );
      final texts = tester.widgetList<RichText>(find.byType(RichText));
      final rendered = texts.map((t) => t.text.toPlainText()).join('\n');
      expect(rendered, contains('قیمت BTC حدود 65,000 USDT است.'));
      expect(rendered, isNot(contains('**')));
      expect(rendered, isNot(contains('~~')));
      expect(rendered, contains('منبع معتبر'));
      expect(rendered, contains('بررسی واحد'));
      expect(
        _spans(
          texts,
        ).any((s) => s.text == 'BTC' && s.style?.fontWeight == FontWeight.w700),
        isTrue,
      );
      expect(
        _spans(texts).any(
          (s) =>
              s.text == '65,000 USDT' && s.style?.fontStyle == FontStyle.italic,
        ),
        isTrue,
      );
      expect(
        _spans(texts).any(
          (s) =>
              s.text == 'قدیمی' &&
              s.style?.decoration == TextDecoration.lineThrough,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'formatted Persian, English, numbers and links retain their direction',
    (tester) async {
      await tester.pumpWidget(
        _markdownHost(
          'قیمت **BTC** برابر 65,000 USDT است.\n\nBTC price: **65,000 USDT**\n\nمنبع: [Example](https://example.com/BTC)',
        ),
      );
      final paragraphs = find.byType(RichText).evaluate().where((e) {
        final text = (e.widget as RichText).text.toPlainText();
        return text.contains('BTC') || text.contains('منبع');
      }).toList();
      expect(
        paragraphs.map(
          (e) => (e.renderObject as RenderParagraph).textDirection,
        ),
        [TextDirection.rtl, TextDirection.ltr, TextDirection.rtl],
      );
      expect(
        paragraphs
            .map((e) => (e.widget as RichText).text.toPlainText())
            .join('\n'),
        contains('منبع: Example'),
      );
      expect(
        _spans(
          paragraphs.map((e) => e.widget as RichText),
        ).any((s) => s.text == 'Example' && s.recognizer != null),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tables, code, quotes and partial Markdown fit a narrow bubble', (
    tester,
  ) async {
    const data =
        '# توضیح\n\n> **منبع** مهم است.\n\n`BTC`\n\n```text\nBTC: 65000 USDT\n```\n\n| Asset | Price |\n| --- | --- |\n| BTC | 65000 |\n\n**پاسخ در حال';
    await tester.pumpWidget(_markdownHost(data, width: 190));
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('BTC: 65000 USDT'), findsOneWidget);
    expect(find.textContaining('پاسخ در حال'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Markdown does not fetch images or launch non-web links', (
    tester,
  ) async {
    await tester.pumpWidget(
      _markdownHost(
        '![توضیح تصویر](https://example.com/tracker.png)\n\n[محلی](file:///private.txt) [اجرایی](javascript:alert)',
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('توضیح تصویر'), findsOneWidget);
    final handlers = _spans(
      tester.widgetList<RichText>(find.byType(RichText)),
    ).where((s) => s.recognizer != null);
    expect(handlers, hasLength(2));
    for (final span in handlers) {
      expect((span.recognizer as dynamic).onTap, isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('user text remains literal and rendered answers update safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatMessageText('**user text**', style: TextStyle(fontSize: 13)),
      ),
    );
    expect(find.text('**user text**'), findsOneWidget);
    await tester.pumpWidget(_markdownHost('**BTC**'));
    expect(find.text('BTC'), findsOneWidget);
    await tester.pumpWidget(_markdownHost('**GOLD18** — تومان'));
    expect(find.textContaining('GOLD18'), findsOneWidget);
    expect(find.text('BTC'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

Widget _markdownHost(String text, {double width = 600}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Segoe UI'),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          width: width,
          child: ChatMessageText(
            text,
            markdown: true,
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
        ),
      ),
    ),
  ),
);

Iterable<TextSpan> _spans(Iterable<RichText> widgets) sync* {
  Iterable<TextSpan> descend(InlineSpan span) sync* {
    if (span is TextSpan) {
      yield span;
      for (final child in span.children ?? const <InlineSpan>[]) {
        yield* descend(child);
      }
    }
  }

  for (final widget in widgets) {
    yield* descend(widget.text);
  }
}
