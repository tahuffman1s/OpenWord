import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/car.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/data/read_aloud.dart';
import 'package:openword/src/data/read_aloud_session.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/reading_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'plans_ui_test.dart' show planPrefs;
import 'read_aloud_test.dart' show FakeSpeech;

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  final bible = parseFixture();

  Future<CarLibrary> library({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final reading = await ReadingStore.load();
    return CarLibrary(bible: bible, reading: reading, showDeuterocanon: false);
  }

  group('the browse tree', () {
    test('a fresh install offers the books and nothing else', () async {
      final car = await library();
      final root = car.children(CarLibrary.rootId);
      expect(root.map((i) => i.id), [CarLibrary.booksId]);
      expect(root.single.playable, isFalse);
      expect(root.single.artist, '3 books');
    });

    test('where reading or listening left off comes first', () async {
      var car = await library(prefs: {'lastPosition': 'GEN/2/'});
      var resume = car.children(CarLibrary.rootId).first;
      expect(resume.id, CarLibrary.resumeId);
      expect(resume.title, 'Continue listening');
      expect(resume.artist, 'Genesis 2');
      expect(resume.playable, isTrue);
      expect(car.resumePlace!.verse, const Reference('GEN', 2, 1));
      expect(car.resumePlace!.fromTop, isTrue);

      // Listening, down to the word, beats a reading position.
      car = await library(
        prefs: {'lastPosition': 'GEN/2/', 'listeningPlace': 'GEN/1/3|7|1'},
      );
      resume = car.children(CarLibrary.rootId).first;
      expect(resume.artist, 'Genesis 1');
      expect(
        car.resumePlace,
        const ListeningPlace(Reference('GEN', 1, 3), offset: 7, fromTop: true),
      );

      // A place in a book this translation lacks is no place.
      car = await library(prefs: {'lastPosition': 'REV/1/'});
      expect(car.resumePlace, isNull);
    });

    test('today’s reading is the unread of each plan’s current day', () async {
      final car = await library(prefs: planPrefs(ReadingPlans.bibleInAYear.id));
      final root = car.children(CarLibrary.rootId);
      final today = root.firstWhere((i) => i.id == CarLibrary.todayId);
      expect(today.title, 'Today’s reading');
      expect(today.artist, 'Genesis 1 and 1 more');
      expect(today.playable, isFalse);
      expect(car.children(CarLibrary.todayId).map((i) => i.id), [
        'chapter/GEN/1',
        'chapter/GEN/2',
      ]);

      // Heard to the end: ticked off, and gone from today.
      car.chapterHeard(const Reference('GEN', 1));
      expect(car.reading.progressFor(ReadingPlans.bibleInAYear.id)!.done, {0});
      expect(car.children(CarLibrary.todayId).map((i) => i.id), [
        'chapter/GEN/2',
      ]);
      expect(
        car
            .children(CarLibrary.rootId)
            .firstWhere((i) => i.id == 'today')
            .artist,
        'Genesis 2',
      );
    });

    test(
      'recent chapters are the history, where this translation has them',
      () async {
        final car = await library(
          prefs: {
            'history': ['PSA/1/', 'REV/1/', 'GEN/2/'],
          },
        );
        expect(
          car.children(CarLibrary.rootId).map((i) => i.id),
          contains(CarLibrary.recentId),
        );
        expect(car.children(CarLibrary.recentId).map((i) => i.title), [
          'Psalms 1',
          'Genesis 2',
        ]);
      },
    );

    test('books open to their chapters, grouped by testament', () async {
      final car = await library();
      final books = car.children(CarLibrary.booksId);
      expect(books.map((i) => i.title), ['Genesis', 'Psalms', 'Matthew']);
      expect(books.first.artist, '2 chapters');
      expect(books.last.artist, '1 chapter');
      expect(
        books.map(
          (i) =>
              i.extras!['android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT'],
        ),
        ['Old Testament', 'Old Testament', 'New Testament'],
      );
      final chapters = car.children('book/GEN');
      expect(chapters.map((i) => i.id), ['chapter/GEN/1', 'chapter/GEN/2']);
      expect(chapters.first.title, 'Genesis 1');
      expect(chapters.every((i) => i.playable == true), isTrue);
      expect(car.children('book/REV'), isEmpty);
      expect(car.children('nonsense'), isEmpty);
    });

    test('an id names a chapter, or nothing', () async {
      final car = await library(prefs: {'listeningPlace': 'GEN/1/3|0|0'});
      expect(car.referenceFor('chapter/GEN/2'), const Reference('GEN', 2));
      expect(car.referenceFor('chapter/GEN/9'), isNull);
      expect(car.referenceFor('chapter/REV/1'), isNull);
      expect(car.referenceFor('chapter/GEN'), isNull);
      expect(car.referenceFor('chapter/GEN/x'), isNull);
      expect(car.referenceFor('book/GEN'), isNull);
      expect(car.referenceFor('resume'), const Reference('GEN', 1, 3));
      expect(car.item('chapter/GEN/2')!.title, 'Genesis 2');
      expect(car.item('nonsense'), isNull);
    });

    test('what a driver says is found, numbers in words included', () async {
      final car = await library();
      expect(car.referenceForSearch('Psalm 1'), const Reference('PSA', 1));
      expect(car.referenceForSearch('genesis two'), const Reference('GEN', 2));
      expect(car.referenceForSearch('Matthew'), const Reference('MAT', 1));
      expect(car.referenceForSearch('the weather'), isNull);
      expect(car.referenceForSearch(''), isNull);
    });

    test('chapters follow on, book to book, to the end', () async {
      final car = await library();
      expect(
        car.chapterAfter(const Reference('GEN', 1)),
        const Reference('GEN', 2),
      );
      expect(
        car.chapterAfter(const Reference('GEN', 2)),
        const Reference('PSA', 1),
      );
      expect(
        car.chapterAfter(const Reference('PSA', 1)),
        const Reference('MAT', 1),
      );
      expect(car.chapterAfter(const Reference('MAT', 1)), isNull);
      expect(car.chapterAfter(const Reference('REV', 1)), isNull);
    });
  });

  group('the session, asked by a car', () {
    late FakeSpeech speech;
    late ReadAloudHandler handler;
    late CarLibrary car;
    var voicesMade = 0;

    Future<void> setUpWith(Map<String, Object> prefs) async {
      speech = FakeSpeech(pauses: true);
      car = await library(prefs: prefs);
      voicesMade = 0;
      handler = ReadAloudHandler()
        ..car = CarAccess(
          library: () async => car,
          voice: () async {
            voicesMade++;
            return ReadAloud(
              engine: speech,
              chapterFor: (reference) => bible
                  .bookByCode(reference.bookCode)
                  ?.chapter(reference.chapter),
              nextChapter: car.chapterAfter,
              onChapterHeard: car.chapterHeard,
              onPlace: (place) => car.reading.listeningPlace = place?.encode(),
            );
          },
        );
    }

    test('lists the tree and the items in it', () async {
      await setUpWith({'lastPosition': 'GEN/2/'});
      final root = await handler.getChildren(AudioService.browsableRootId);
      expect(root.map((i) => i.id), [CarLibrary.resumeId, CarLibrary.booksId]);
      expect((await handler.getMediaItem('chapter/PSA/1'))!.title, 'Psalms 1');
      expect(await handler.getMediaItem('nonsense'), isNull);
      expect((await handler.search('psalm one')).map((i) => i.id), [
        'chapter/PSA/1',
      ]);
      expect(await handler.search('the weather'), isEmpty);
    });

    test('plays a chapter with no screen open, and shows it', () async {
      await setUpWith({});
      await handler.playFromMediaId('chapter/GEN/2');
      await settle();
      expect(voicesMade, 1);
      expect(speech.said.single, startsWith('Genesis, chapter 2.'));
      expect(speech.said.single, contains('The second chapter.'));
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.mediaItem.value!.title, 'Genesis, chapter 2');
      expect(handler.mediaItem.value!.album, 'Test Edition');

      // The same voice serves the next request.
      await handler.playFromMediaId('chapter/PSA/1');
      await settle();
      expect(voicesMade, 1);
      expect(speech.said.last, contains('Psalm 1.'));
    });

    test('takes listening up where it left off, down to the word', () async {
      await setUpWith({'listeningPlace': 'GEN/1/3|4|1'});
      await handler.playFromMediaId(CarLibrary.resumeId);
      await settle();
      // Taken up mid-verse: the verse's words from the kept offset.
      expect(speech.said.single, startsWith('said'));
    });

    test('plays what the driver asked for, or carries on', () async {
      await setUpWith({'lastPosition': 'PSA/1/'});
      await handler.playFromSearch('genesis two');
      await settle();
      expect(speech.said.last, contains('The second chapter.'));
      await handler.playFromSearch('something else entirely');
      await settle();
      expect(speech.said.last, contains('Psalm 1.'));
    });

    test('without a car’s access, it has nothing to say', () async {
      final bare = ReadAloudHandler();
      expect(await bare.getChildren(AudioService.browsableRootId), isEmpty);
      await bare.playFromMediaId('chapter/GEN/1');
      expect(bare.playbackState.value.playing, isFalse);
    });

    test('a reader screen’s own voice takes over from the car’s', () async {
      await setUpWith({});
      await handler.playFromMediaId('chapter/GEN/1');
      await settle();
      final stopsBefore = speech.stops;
      final own = ReadAloud(
        engine: FakeSpeech(),
        chapterFor: (reference) =>
            bible.bookByCode(reference.bookCode)?.chapter(reference.chapter),
        nextChapter: (_) => null,
      );
      handler.bind(own, () => 'Mine');
      expect(speech.stops, greaterThan(stopsBefore));
      expect(handler.voice, same(own));
      // Once bound, the car's requests go to the reader's voice.
      await handler.playFromMediaId('chapter/GEN/2');
      await settle();
      expect(own.isPlaying, isTrue);
      expect(voicesMade, 1);
    });
  });

  test('the Android manifest declares a media app for the car', () {
    // The declaration Android Auto looks for, and the file it points at.
    const manifest = 'android/app/src/main/AndroidManifest.xml';
    const desc = 'android/app/src/main/res/xml/automotive_app_desc.xml';
    final manifestText = File(manifest).readAsStringSync();
    expect(manifestText, contains('com.google.android.gms.car.application'));
    expect(manifestText, contains('@xml/automotive_app_desc'));
    expect(manifestText, contains('android.media.browse.MediaBrowserService'));
    expect(File(desc).readAsStringSync(), contains('<uses name="media"/>'));
  });

  test('a plan chapter heard in the car is ticked off', () async {
    final car = await library(prefs: planPrefs(ReadingPlans.bibleInAYear.id));
    final before = jsonEncode(
      car.reading.progressFor(ReadingPlans.bibleInAYear.id)!.toJson(),
    );
    car.chapterHeard(const Reference('MAT', 1));
    expect(
      jsonEncode(
        car.reading.progressFor(ReadingPlans.bibleInAYear.id)!.toJson(),
      ),
      before,
      reason: 'a chapter not in the day is left alone',
    );
    car.chapterHeard(const Reference('GEN', 2));
    expect(car.reading.progressFor(ReadingPlans.bibleInAYear.id)!.done, {1});
  });
}
