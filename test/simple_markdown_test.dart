import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/ui/widgets/simple_markdown.dart';

Future<void> pump(WidgetTester tester, String source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SimpleMarkdown(source: source)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The plain text of every rendered span, in order.
List<String> rendered(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((widget) => widget.text.toPlainText())
    .toList();

/// The style of the span that actually carries text, which is what gets
/// painted — spans above it only pass a style down.
TextStyle leafStyle(WidgetTester tester, Finder finder) {
  TextStyle? found;
  void walk(InlineSpan span, TextStyle? inherited) {
    final text = span as TextSpan;
    final style = text.style ?? inherited;
    if (text.text != null && text.text!.isNotEmpty) found ??= style;
    for (final child in text.children ?? const <InlineSpan>[]) {
      walk(child, style);
    }
  }

  walk(tester.widget<RichText>(finder).text, null);
  return found!;
}

void main() {
  testWidgets('joins wrapped lines into one paragraph', (tester) async {
    await pump(tester, 'Genesis is the book\nof beginnings.\n\nIt tells how.');
    expect(rendered(tester), [
      'Genesis is the book of beginnings.',
      'It tells how.',
    ]);
  });

  testWidgets('reads underlined headings, as the source writes them', (
    tester,
  ) async {
    await pump(tester, 'Setting\n=======\n\nText.\n\nAuthor\n------\n\nMore.');
    expect(rendered(tester), ['Setting', 'Text.', 'Author', 'More.']);
  });

  testWidgets('a heading is set apart from the text around it', (tester) async {
    await pump(tester, 'Setting\n=======\n\nPlain text.');

    // The style has to reach the span that holds the text: a span carrying a
    // style of its own would render the heading as body text however the
    // enclosing widget is styled.
    final heading = leafStyle(tester, find.byType(RichText).first);
    final body = leafStyle(tester, find.byType(RichText).last);

    expect(heading.fontWeight, FontWeight.w700);
    expect(heading.color, isNot(body.color));
    expect(heading.fontSize, greaterThan(body.fontSize!));
  });

  testWidgets('reads hash headings too', (tester) async {
    await pump(tester, '## Summary\n\nText.');
    expect(rendered(tester), ['Summary', 'Text.']);
  });

  testWidgets('a rule on its own is not a heading', (tester) async {
    await pump(tester, 'Text.\n\n-----\n\nMore.');
    expect(rendered(tester), ['Text.', 'More.']);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('renders bullets and numbered items', (tester) async {
    await pump(tester, '* First\n* Second\n\n1. One\n2. Two');
    expect(rendered(tester), [
      '•',
      'First',
      '•',
      'Second',
      '1.',
      'One',
      '2.',
      'Two',
    ]);
  });

  testWidgets('emphasises bold and italic without showing the markers', (
    tester,
  ) async {
    await pump(tester, 'A **bold** and *italic* line.');
    expect(rendered(tester).single, 'A bold and italic line.');

    final spans = <TextSpan>[];
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    expect(
      spans.firstWhere((s) => s.text == 'bold').style!.fontWeight,
      FontWeight.w700,
    );
    expect(
      spans.firstWhere((s) => s.text == 'italic').style!.fontStyle,
      FontStyle.italic,
    );
  });

  testWidgets('unescapes backslash escapes, which the source is full of', (
    tester,
  ) async {
    await pump(tester, r'CC BY\-SA 4\.0 and non\-Israelite');
    expect(rendered(tester).single, 'CC BY-SA 4.0 and non-Israelite');
  });

  testWidgets('renders nothing for empty input', (tester) async {
    await pump(tester, '   \n\n  ');
    expect(rendered(tester), isEmpty);
  });
}
