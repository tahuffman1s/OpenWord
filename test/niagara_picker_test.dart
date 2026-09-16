import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/ui/widgets/niagara_picker.dart';

void main() {
  const groups = [
    PickerGroup<String>(
      key: 'A',
      entries: [
        PickerEntry(label: 'Amos', value: 'AMO'),
        PickerEntry(label: 'Acts', value: 'ACT'),
      ],
    ),
    PickerGroup<String>(
      key: 'G',
      entries: [
        PickerEntry(label: 'Galatians', value: 'GAL'),
        PickerEntry(label: 'Genesis', value: 'GEN'),
      ],
    ),
    PickerGroup<String>(key: 'Q', entries: []),
  ];

  Future<void> pump(WidgetTester tester, List<String> picked) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 600,
              child: NiagaraPicker<String>(
                groups: groups,
                onSelected: picked.add,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows every rail label, including empty ones', (tester) async {
    await pump(tester, []);
    // A and G also head their sections in the browsable list underneath.
    expect(find.text('A'), findsNWidgets(2));
    expect(find.text('G'), findsNWidgets(2));
    expect(find.text('Q'), findsOneWidget);
  });

  testWidgets('the idle list is usable without the rail', (tester) async {
    final picked = <String>[];
    await pump(tester, picked);
    await tester.tap(find.text('Genesis').first);
    await tester.pumpAndSettle();
    expect(picked, ['GEN']);
  });

  testWidgets('dragging the rail fans a group out and picks from it', (
    tester,
  ) async {
    final picked = <String>[];
    await pump(tester, picked);

    // Land on the rail beside "G", then slide left onto a fanned entry.
    final railG = tester.getRect(find.text('G').last);
    final gesture = await tester.startGesture(railG.center);
    await tester.pumpAndSettle();

    await gesture.moveTo(Offset(railG.center.dx - 120, railG.center.dy - 20));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveTo(Offset(railG.center.dx - 200, railG.center.dy - 20));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(picked, isNotEmpty);
    expect(picked.single, anyOf('GAL', 'GEN'));
  });

  testWidgets('says so when a letter has no books', (tester) async {
    await pump(tester, []);
    await tester.tap(find.text('Q'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No books under'), findsOneWidget);
  });
}
