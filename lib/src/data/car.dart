import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';
import 'library.dart';
import 'marks.dart';
import 'read_aloud.dart';
import 'reference_search.dart';
import 'settings.dart';

/// What a car sees of OpenWord, and what it can ask for.
///
/// Android Auto talks to a media app through its media browser: a tree
/// of items, some to open and some to play, and a way to play one by
/// its id or by what the driver said. This is that tree for Scripture
/// read aloud — where listening left off, today's reading from any plan
/// under way, the chapters lately read, and every book and chapter — and
/// the ids that name each thing, so that the handler can be asked for
/// `chapter/PSA/23` and know what is meant.
class CarLibrary {
  CarLibrary({
    required this.bible,
    required this.reading,
    required this.showDeuterocanon,
  });

  final Bible bible;
  final ReadingStore reading;
  final bool showDeuterocanon;

  static const String rootId = AudioService.browsableRootId;
  static const String resumeId = 'resume';
  static const String todayId = 'today';
  static const String recentId = 'recent';
  static const String booksId = 'books';

  /// The books a car may browse, in canonical order.
  List<Book> get books => [
    for (final book in bible.books)
      if (showDeuterocanon || book.section != BookSection.deuterocanon) book,
  ];

  /// Where listening left off, down to the word, or else the top of the
  /// chapter reading left off in.
  ListeningPlace? get resumePlace {
    final place = ListeningPlace.decode(reading.listeningPlace);
    if (place != null && _has(place.verse)) return place;
    final last = reading.lastPosition;
    if (last != null && _has(last)) {
      return ListeningPlace(last.withVerse(1), fromTop: true);
    }
    return null;
  }

  /// The verse [resumePlace] takes up at.
  Reference? get resumePoint => resumePlace?.verse;

  /// Today's reading across every plan under way, unread chapters first.
  List<Reference> get todaysReading {
    final chapters = <Reference>[];
    for (final progress in reading.plans) {
      final day = progress.currentDay;
      if (day == null || !progress.hasReadingDueOn(reading.today)) continue;
      for (final slot in day.slots) {
        final chapter = progress.chapterAt(slot);
        if (!progress.isRead(slot) &&
            _has(chapter) &&
            !chapters.contains(chapter)) {
          chapters.add(chapter);
        }
      }
    }
    return chapters;
  }

  bool _has(Reference reference) =>
      bible.bookByCode(reference.bookCode)?.chapter(reference.chapter) != null;

  /// The items under [parentId]: what the car lists when that is opened.
  List<MediaItem> children(String parentId) {
    if (parentId == rootId) return _root();
    if (parentId == booksId) return _books();
    if (parentId == todayId) {
      return [for (final chapter in todaysReading) _chapterItem(chapter)];
    }
    if (parentId == recentId) {
      return [
        for (final chapter in reading.history)
          if (_has(chapter)) _chapterItem(chapter),
      ];
    }
    if (parentId.startsWith('book/')) {
      final book = bible.bookByCode(parentId.substring(5));
      if (book == null) return const [];
      return [
        for (final number in book.chapterNumbers)
          _chapterItem(Reference(book.code, number)),
      ];
    }
    return const [];
  }

  List<MediaItem> _root() {
    final resume = resumePoint;
    final today = todaysReading;
    return [
      if (resume != null)
        MediaItem(
          id: resumeId,
          title: 'Continue listening',
          album: bible.translation.name,
          artist: resume.withVerse(null).label,
          playable: true,
        ),
      if (today.isNotEmpty)
        MediaItem(
          id: todayId,
          title: 'Today’s reading',
          album: bible.translation.name,
          artist: today.length == 1
              ? today.single.label
              : '${today.first.label} and ${today.length - 1} more',
          playable: false,
        ),
      if (reading.history.any(_has))
        MediaItem(
          id: recentId,
          title: 'Recent chapters',
          album: bible.translation.name,
          playable: false,
        ),
      MediaItem(
        id: booksId,
        title: 'Books',
        album: bible.translation.name,
        artist: '${books.length} books',
        playable: false,
      ),
    ];
  }

  List<MediaItem> _books() => [
    for (final book in books)
      MediaItem(
        id: 'book/${book.code}',
        title: book.name,
        album: bible.translation.name,
        artist: book.chapterCount == 1
            ? '1 chapter'
            : '${book.chapterCount} chapters',
        playable: false,
        // Grouped under their testament in a car that groups.
        extras: {
          'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT':
              book.section.label,
        },
      ),
  ];

  MediaItem _chapterItem(Reference chapter) => MediaItem(
    id: 'chapter/${chapter.bookCode}/${chapter.chapter}',
    title: chapter.withVerse(null).label,
    album: bible.translation.name,
    artist: 'OpenWord',
    playable: true,
  );

  /// The item named by [mediaId], or null for an id that names nothing.
  MediaItem? item(String mediaId) {
    final reference = referenceFor(mediaId);
    if (reference == null) return null;
    return _chapterItem(reference.withVerse(null));
  }

  /// Where to start reading for a media id: a chapter, or the verse to
  /// take up at for [resumeId].
  Reference? referenceFor(String mediaId) {
    if (mediaId == resumeId) return resumePoint;
    if (mediaId.startsWith('chapter/')) {
      final parts = mediaId.split('/');
      if (parts.length != 3) return null;
      final chapter = int.tryParse(parts[2]);
      if (chapter == null) return null;
      final reference = Reference(parts[1], chapter);
      return _has(reference) ? reference : null;
    }
    return null;
  }

  /// Where to start for what a driver said — "Psalm 23", "John three" —
  /// or null when it names nothing here.
  Reference? referenceForSearch(String query) {
    final spoken = _numbersInWords(query);
    final found = ReferenceSearch.parse(spoken, books);
    if (found == null || !_has(found)) return null;
    return found;
  }

  /// Numbers a voice assistant may hand over as words, turned to digits.
  static String _numbersInWords(String text) {
    var out = text.toLowerCase();
    _words.forEach((word, digit) {
      out = out.replaceAll(RegExp('\\b$word\\b'), '$digit');
    });
    return out;
  }

  static const Map<String, int> _words = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, //
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, //
    'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, //
    'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19, //
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, //
  };

  /// The chapter after [chapter] in the order a car lists them, or null
  /// at the end of the last book.
  Reference? chapterAfter(Reference chapter) {
    final list = books;
    for (var i = 0; i < list.length; i++) {
      final book = list[i];
      if (book.code != chapter.bookCode) continue;
      final numbers = book.chapterNumbers.toList();
      final at = numbers.indexOf(chapter.chapter);
      if (at >= 0 && at + 1 < numbers.length) {
        return Reference(book.code, numbers[at + 1]);
      }
      if (i + 1 < list.length) {
        final next = list[i + 1];
        return Reference(next.code, next.outline.first.number);
      }
      return null;
    }
    return null;
  }

  /// Ticks off a chapter heard to its end in any plan it is due in.
  void chapterHeard(Reference chapter) {
    for (final progress in reading.plans) {
      final day = progress.currentDay;
      if (day == null) continue;
      for (final slot in day.slots) {
        if (!progress.isRead(slot) && progress.chapterAt(slot) == chapter) {
          reading.setPlanSlot(progress.plan.id, slot, read: true);
        }
      }
    }
  }
}

/// What the media session needs from the app to answer a car on its own:
/// the library to list and a voice to read with, each had when wanted,
/// since the car may ask before the Scripture has finished loading, or
/// with no screen open at all.
class CarAccess {
  const CarAccess({required this.library, required this.voice});

  final Future<CarLibrary?> Function() library;

  /// A voice ready to read, with its pace and speaker set, following the
  /// chapters on from one to the next and keeping its place.
  final Future<ReadAloud?> Function() voice;
}

/// Car access over the app's own stores.
CarAccess carAccessFor({
  required LibraryController library,
  required ReadingStore reading,
  required Settings settings,
}) {
  Future<CarLibrary?> carLibrary() async {
    final bible = await whenLoaded(library);
    if (bible == null) return null;
    return CarLibrary(
      bible: bible,
      reading: reading,
      showDeuterocanon: settings.showDeuterocanon,
    );
  }

  return CarAccess(
    library: carLibrary,
    voice: () async {
      final car = await carLibrary();
      if (car == null) return null;
      final engine = createSpeechEngine();
      if (!engine.isAvailable) return null;
      final voice = ReadAloud(
        engine: engine,
        chapterFor: (reference) => car.bible
            .bookByCode(reference.bookCode)
            ?.chapter(reference.chapter),
        nextChapter: car.chapterAfter,
        onChapterHeard: car.chapterHeard,
        onPlace: (place) => reading.listeningPlace = place?.encode(),
      );
      voice.configure(
        language: car.bible.translation.language,
        rate: settings.speechRate,
        voice: settings.speechVoice,
      );
      return voice;
    },
  );
}

/// The Scripture once it is loaded, or null if loading it failed.
Future<Bible?> whenLoaded(LibraryController library) {
  if (library.isReady) return Future.value(library.bible);
  if (library.status == LibraryStatus.failed) return Future.value(null);
  final done = Completer<Bible?>();
  void check() {
    if (library.isReady) {
      library.removeListener(check);
      done.complete(library.bible);
    } else if (library.status == LibraryStatus.failed) {
      library.removeListener(check);
      done.complete(null);
    }
  }

  library.addListener(check);
  return done.future;
}
