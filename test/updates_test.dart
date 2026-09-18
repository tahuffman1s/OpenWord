import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/app_version.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/data/update_backend.dart';
import 'package:openword/src/data/updates.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<Settings> freshSettings([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return Settings.load();
}

void main() {
  test('the version the app reports matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(declared, isNotNull, reason: 'pubspec.yaml has no version');
    expect(
      appVersion,
      declared!.group(1),
      reason: 'app_version.dart has drifted from pubspec.yaml',
    );
  });

  group('version ordering', () {
    AppRelease parse(String text) => AppRelease.parse(text)!;

    test('reads the shapes releases are tagged with', () {
      expect(parse('v1.4.0').toString(), '1.4.0');
      expect(parse('1.4.0').toString(), '1.4.0');
      expect(parse('1.4.0+5').toString(), '1.4.0');
      expect(parse('v2.0').toString(), '2.0');
      expect(AppRelease.parse('nightly'), isNull);
      expect(AppRelease.parse(''), isNull);
    });

    test('compares by number, not by string', () {
      expect(parse('1.10.0').isNewerThan(parse('1.9.0')), isTrue);
      expect(parse('1.4.1').isNewerThan(parse('1.4.0')), isTrue);
      expect(parse('2.0.0').isNewerThan(parse('1.99.99')), isTrue);
      expect(parse('1.4.0').isNewerThan(parse('1.4.0')), isFalse);
      expect(parse('1.3.0').isNewerThan(parse('1.4.0')), isFalse);
    });

    test('a missing part counts as zero', () {
      expect(parse('1.4').isNewerThan(parse('1.4.0')), isFalse);
      expect(parse('1.4.1').isNewerThan(parse('1.4')), isTrue);
    });

    test('a pre-release comes before the release it leads to', () {
      expect(parse('1.5.0').isNewerThan(parse('1.5.0-beta.1')), isTrue);
      expect(parse('1.5.0-beta.1').isNewerThan(parse('1.4.0')), isTrue);
    });

    test('the build number is not part of the comparison', () {
      expect(parse('1.4.0+9').isNewerThan(parse('1.4.0+1')), isFalse);
    });
  });

  group('reading a release', () {
    test('picks out the version, notes and the file for this platform', () {
      final release = Release.parse(
        releaseJson(
          assets: [
            'OpenWord-v9.9.9-android.apk',
            'OpenWord-v9.9.9-linux-x64.tar.gz',
            'OpenWord-v9.9.9-windows-x64.zip',
            'OpenWord-v9.9.9-web.zip',
          ],
        ),
      )!;

      expect(release.version.toString(), '9.9.9');
      expect(release.notes, contains('Something new'));
      expect(release.assetFor(TargetKind.android)!.name, endsWith('.apk'));
      expect(
        release.assetFor(TargetKind.linux)!.name,
        endsWith('-linux-x64.tar.gz'),
      );
      expect(
        release.assetFor(TargetKind.windows)!.name,
        endsWith('-windows-x64.zip'),
      );
      // iOS and macOS have nothing to install; the web build is not an
      // update, so none of them resolve to a file.
      expect(release.assetFor(TargetKind.other), isNull);
    });

    test('drafts and pre-releases are not offered', () {
      expect(Release.parse(releaseJson(draft: true)), isNull);
      expect(Release.parse(releaseJson(prerelease: true)), isNull);
    });

    test('rubbish does not become a release', () {
      expect(Release.parse('{}'), isNull);
      expect(Release.parse('"nope"'), isNull);
      expect(Release.parse(releaseJson(tag: 'nightly')), isNull);
    });

    test('a release with no file still carries its page', () {
      final release = Release.parse(releaseJson(assets: const []))!;

      expect(release.assetFor(TargetKind.android), isNull);
      expect(release.page.toString(), contains('/releases/tag/v9.9.9'));
    });
  });

  group('checking', () {
    test('a newer release is offered', () async {
      final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check();

      expect(service.stage, UpdateStage.available);
      expect(service.updateAvailable, isTrue);
      expect(service.shouldAnnounce, isTrue);
      expect(service.asset!.name, endsWith('.apk'));
    });

    test('the version in hand is not offered to itself', () async {
      final service = UpdateService(
        settings: await freshSettings(),
        backend: FakeUpdateBackend(body: releaseJson(tag: 'v1.4.0')),
        currentVersion: '1.4.0',
      );

      await service.check();

      expect(service.stage, UpdateStage.upToDate);
      expect(service.updateAvailable, isFalse);
      expect(service.shouldAnnounce, isFalse);
    });

    test('an older release is not offered either', () async {
      final service = UpdateService(
        settings: await freshSettings(),
        backend: FakeUpdateBackend(body: releaseJson(tag: 'v1.0.0')),
        currentVersion: '1.4.0',
      );

      await service.check();

      expect(service.stage, UpdateStage.upToDate);
    });

    test('nothing is asked while the switch is off', () async {
      final settings = await freshSettings();
      settings.checkForUpdates = false;
      final backend = FakeUpdateBackend(body: releaseJson());
      final service = UpdateService(
        settings: settings,
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check();
      expect(backend.reads, 0);

      // "Check now" is the reader asking, so it goes anyway.
      await service.check(force: true);
      expect(backend.reads, 1);
    });

    test('the automatic check is at most daily', () async {
      final settings = await freshSettings();
      final backend = FakeUpdateBackend(body: releaseJson());
      var now = DateTime(2026, 9, 17, 9);
      final service = UpdateService(
        settings: settings,
        backend: backend,
        currentVersion: '1.4.0',
        clock: () => now,
      );

      await service.check();
      expect(backend.reads, 1);
      expect(settings.lastUpdateCheck, now);

      now = now.add(const Duration(hours: 6));
      await service.check();
      expect(backend.reads, 1, reason: 'too soon to ask again');

      now = now.add(const Duration(days: 1));
      await service.check();
      expect(backend.reads, 2);
    });

    test('nothing happens at all on the web', () async {
      final backend = FakeUpdateBackend(
        body: releaseJson(),
        isSupported: false,
      );
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check(force: true);

      expect(backend.reads, 0);
      expect(service.stage, UpdateStage.idle);
    });

    test('a dead network is reported, not thrown', () async {
      final service = UpdateService(
        settings: await freshSettings(),
        backend: FakeUpdateBackend(
          failWith: const SocketException('Failed host lookup'),
        ),
        currentVersion: '1.4.0',
      );

      await service.check(force: true);

      expect(service.stage, UpdateStage.failed);
      expect(service.error, 'No connection to GitHub.');
    });

    test('nonsense from GitHub is reported, not thrown', () async {
      final service = UpdateService(
        settings: await freshSettings(),
        backend: FakeUpdateBackend(body: '{"tag_name": "not-a-version"}'),
        currentVersion: '1.4.0',
      );

      await service.check(force: true);

      expect(service.stage, UpdateStage.failed);
      expect(service.error, contains('unexpected'));
    });

    test('a skipped version stops the announcement, not the page', () async {
      final settings = await freshSettings();
      final service = UpdateService(
        settings: settings,
        backend: FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0')),
        currentVersion: '1.4.0',
      );

      await service.check(force: true);
      service.skipThisVersion();

      expect(settings.skippedUpdate, '2.0.0');
      expect(service.shouldAnnounce, isFalse);
      expect(service.updateAvailable, isTrue);
    });
  });

  group('downloading and installing', () {
    test('reports progress and hands the file over', () async {
      final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );
      final seen = <double?>[];
      service.addListener(() {
        if (service.stage == UpdateStage.downloading) {
          seen.add(service.progress);
        }
      });

      await service.check(force: true);
      await service.download();

      expect(seen, containsAllInOrder(<double>[0.5, 1.0]));
      expect(service.stage, UpdateStage.readyToInstall);
      expect(backend.downloads.single.toString(), endsWith('.apk'));

      await service.install();
      expect(backend.installs.single, endsWith('OpenWord-v2.0.0-android.apk'));
    });

    test('a key that does not match is explained, not just failed', () async {
      final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check(force: true);
      await service.download();
      backend.installFailsWith = PlatformException(
        code: 'signature-mismatch',
        message: 'This release was signed with a different key',
      );
      await service.install();

      // Not a plain failure: the update is sound, the system will not take
      // it, and the reader needs to be told what to do about it.
      expect(service.stage, UpdateStage.blocked);
      expect(service.error, contains('different key'));

      await service.uninstall();
      expect(backend.uninstalls, 1);
    });

    test('any other refusal from the platform is reported', () async {
      final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check(force: true);
      await service.download();
      backend.installFailsWith = PlatformException(
        code: 'not-allowed',
        message: 'OpenWord is not allowed to install apps',
      );
      await service.install();

      expect(service.stage, UpdateStage.failed);
      expect(service.error, contains('not allowed'));
    });

    test('an install that starts leaves the sheet as it was', () async {
      final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check(force: true);
      await service.download();
      await service.install();

      expect(service.stage, UpdateStage.readyToInstall);
      expect(service.error, isNull);
      expect(backend.installs, hasLength(1));
    });

    test('a failed download is reported, and installs nothing', () async {
      final backend = FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0'));
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check(force: true);
      backend.failWith = const HttpException('The download answered 404');
      await service.download();

      expect(service.stage, UpdateStage.failed);
      expect(service.error, contains('404'));

      await service.install();
      expect(backend.installs, isEmpty);
    });

    test('where the app cannot install, it offers the page', () async {
      final backend = FakeUpdateBackend(
        body: releaseJson(tag: 'v2.0.0'),
        target: TargetKind.other,
        canInstall: false,
      );
      final service = UpdateService(
        settings: await freshSettings(),
        backend: backend,
        currentVersion: '1.4.0',
      );

      await service.check(force: true);
      expect(service.asset, isNull);

      await service.download();
      expect(backend.downloads, isEmpty);

      await service.openReleasePage();
      expect(backend.opened.single.toString(), contains('/releases/tag/'));
    });
  });
}
