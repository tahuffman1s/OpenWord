import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/data/update_backend.dart';
import 'package:openword/src/data/updates.dart';
import 'package:openword/src/ui/update_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<UpdateService> ready(FakeUpdateBackend backend) async {
  SharedPreferences.setMockInitialValues({});
  final service = UpdateService(
    settings: await Settings.load(),
    backend: backend,
    currentVersion: '1.4.0',
  );
  await service.check(force: true);
  return service;
}

Future<void> openSheet(WidgetTester tester, UpdateService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showUpdateSheet(context, service),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows what is new, and downloads on a tap', (tester) async {
    final backend = FakeUpdateBackend(
      body: releaseJson(
        tag: 'v2.0.0',
        notes:
            '### Added\n- Maps of the places a chapter names.\n'
            '\n---\n\nThe Android APK is signed with a debug key.',
      ),
    );
    final service = await ready(backend);
    await openSheet(tester, service);

    expect(find.text('OpenWord v2.0.0'), findsOneWidget);
    expect(find.text('You have 1.4.0'), findsOneWidget);
    expect(find.textContaining('Maps of the places'), findsOneWidget);
    // The workflow's installation boilerplate is cut off.
    expect(find.textContaining('debug key'), findsNothing);

    await tester.tap(find.textContaining('Download'));
    await tester.pumpAndSettle();

    expect(backend.downloads, hasLength(1));
    expect(find.text('Install'), findsOneWidget);

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(backend.installs, hasLength(1));
  });

  testWidgets('offers the release page where it cannot install', (
    tester,
  ) async {
    final backend = FakeUpdateBackend(
      body: releaseJson(tag: 'v2.0.0', assets: const []),
      target: TargetKind.other,
      canInstall: false,
    );
    final service = await ready(backend);
    await openSheet(tester, service);

    expect(find.text('Open the release page'), findsOneWidget);
    await tester.tap(find.text('Open the release page'));
    await tester.pumpAndSettle();

    expect(backend.opened, hasLength(1));
  });

  testWidgets('skipping closes the sheet and remembers', (tester) async {
    final service = await ready(
      FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0')),
    );
    await openSheet(tester, service);

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();

    expect(find.text('Skip this version'), findsNothing);
    expect(service.settings.skippedUpdate, '2.0.0');
    expect(service.shouldAnnounce, isFalse);
  });

  testWidgets('a key that does not match is shown with a way through', (
    tester,
  ) async {
    final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
    final service = await ready(backend);
    await openSheet(tester, service);

    await tester.tap(find.textContaining('Download'));
    await tester.pumpAndSettle();

    backend.installFailsWith = PlatformException(
      code: 'signature-mismatch',
      message: 'This release was signed with a different key than yours.',
    );
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(find.textContaining('different key'), findsOneWidget);
    expect(find.textContaining('copy a backup from Settings'), findsOneWidget);
    expect(find.text('Open the release page'), findsOneWidget);

    await tester.tap(find.text('Remove the copy you have'));
    await tester.pumpAndSettle();
    expect(backend.uninstalls, 1);
  });

  testWidgets('a failed download is shown with a way out', (tester) async {
    final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
    final service = await ready(backend);
    await openSheet(tester, service);

    backend.failWith = Exception('the server hung up');
    await tester.tap(find.textContaining('Download'));
    await tester.pumpAndSettle();

    expect(find.textContaining('hung up'), findsOneWidget);
    expect(find.text('Open the release page'), findsOneWidget);
  });
}
