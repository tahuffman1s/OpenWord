import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/app_scope.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/data/updates.dart';
import 'package:openword/src/data/voice_licences.dart';
import 'package:openword/src/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  tearDown(LicenseRegistry.reset);

  test(
    'the voice\'s licences are there in full, with the GPL source',
    () async {
      registerVoiceLicences();
      final entries = await LicenseRegistry.licenses.toList();
      String text(String package) => entries
          .where((entry) => entry.packages.contains(package))
          .single
          .paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      expect(text('KittenTTS'), contains('Apache License'));
      expect(text('KittenTTS'), contains('KittenML'));
      expect(text('eSpeak NG'), contains('GNU GENERAL PUBLIC LICENSE'));
      expect(text('eSpeak NG'), contains(espeakSource));
      expect(text('ONNX Runtime'), contains('Microsoft Corporation'));
    },
  );

  testWidgets('Settings credits the voice and shows every licence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final settings = await Settings.load();
    final reading = await ReadingStore.load();
    final library = LibraryController(bundle: FixtureBundle());
    await tester.runAsync(() => library.load(testTranslation.id));
    await tester.pumpWidget(
      AppScope(
        settings: settings,
        library: library,
        reading: reading,
        updates: UpdateService(
          settings: settings,
          backend: FakeUpdateBackend(isSupported: false),
          currentVersion: '1.0.0',
        ),
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final credit = find.text(voiceAttribution);
    await tester.scrollUntilVisible(credit, 300);
    expect(credit, findsOneWidget);
    expect(voiceAttribution, contains('GPL-3.0'));
    expect(voiceAttribution, contains(espeakSource));

    await tester.scrollUntilVisible(find.text('Licences'), 300);
    await tester.tap(find.text('Licences'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
