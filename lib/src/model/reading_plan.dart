import 'bible.dart';
import 'book_meta.dart';
import 'versification_table.dart';

/// A run of chapters of one book read together: "Genesis 1–3".
class Passage {
  const Passage(this.bookCode, this.firstChapter, this.lastChapter);

  final String bookCode;
  final int firstChapter;
  final int lastChapter;

  int get chapterCount => lastChapter - firstChapter + 1;

  /// How a single chapter is named in a plan.
  static String labelFor(Reference chapter) =>
      Passage(chapter.bookCode, chapter.chapter, chapter.chapter).label;

  Iterable<Reference> get chapters sync* {
    for (var c = firstChapter; c <= lastChapter; c++) {
      yield Reference(bookCode, c);
    }
  }

  String get label {
    final name = BookMeta.lookup(bookCode)?.name ?? bookCode;
    // A book of one chapter is named, not numbered: "Jude", not "Jude 1".
    if (_chapterCountOf(bookCode) == 1) return name;
    if (firstChapter == lastChapter) {
      // One psalm is a psalm.
      return bookCode == 'PSA' ? 'Psalm $firstChapter' : '$name $firstChapter';
    }
    return '$name $firstChapter–$lastChapter';
  }

  @override
  bool operator ==(Object other) =>
      other is Passage &&
      other.bookCode == bookCode &&
      other.firstChapter == firstChapter &&
      other.lastChapter == lastChapter;

  @override
  int get hashCode => Object.hash(bookCode, firstChapter, lastChapter);

  @override
  String toString() => label;
}

/// One day of a plan: the chapters to read, in order.
///
/// Each chapter is a slot. A plan can read the same chapter twice — a
/// psalm on two different days — so progress is kept per slot rather than
/// per chapter.
class PlanDay {
  const PlanDay({
    required this.number,
    required this.chapters,
    required this.firstSlot,
    required this.verses,
  });

  /// 1-based.
  final int number;
  final List<Reference> chapters;

  /// The slot of this day's first chapter; the rest follow in order.
  final int firstSlot;

  /// How many verses the day holds, which is what a reading time is
  /// estimated from.
  final int verses;

  int get slotCount => chapters.length;

  Iterable<int> get slots sync* {
    for (var i = 0; i < chapters.length; i++) {
      yield firstSlot + i;
    }
  }

  /// The day's chapters gathered into passages: "Genesis 50; Exodus 1–2".
  List<Passage> get passages {
    final result = <Passage>[];
    for (final chapter in chapters) {
      final last = result.isEmpty ? null : result.last;
      if (last != null &&
          last.bookCode == chapter.bookCode &&
          last.lastChapter + 1 == chapter.chapter) {
        result[result.length - 1] = Passage(
          last.bookCode,
          last.firstChapter,
          chapter.chapter,
        );
      } else {
        result.add(Passage(chapter.bookCode, chapter.chapter, chapter.chapter));
      }
    }
    return result;
  }

  String get label => passages.map((p) => p.label).join('; ');
}

/// A reading plan: which chapters to read on which day.
///
/// Days are numbered, not dated. A plan starts whenever the reader starts
/// it, and a day not read is still there tomorrow — the reason most people
/// give a yearly plan up is that the readings they missed pile up behind
/// them, and a plan here does not pile anything up.
class ReadingPlan {
  ReadingPlan._({
    required this.id,
    required this.name,
    required this.summary,
    required this.description,
    required this.days,
    this.recommended = false,
  });

  /// Stable: progress is saved against it. A plan that changed shape would
  /// have to take a new id rather than move a reader's ticks onto other
  /// chapters.
  final String id;
  final String name;

  /// One line, for the list.
  final String summary;

  /// A paragraph, for the plan's own page.
  final String description;
  final List<PlanDay> days;

  /// Offered first to someone who has never followed a plan.
  final bool recommended;

  int get length => days.length;

  int get slotCount =>
      days.isEmpty ? 0 : days.last.firstSlot + days.last.slotCount;

  /// The day a slot belongs to.
  PlanDay dayOfSlot(int slot) {
    var low = 0;
    var high = days.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (days[mid].firstSlot <= slot) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return days[low];
  }

  /// Minutes a typical day takes to read silently: an English verse is
  /// about 25 words, and adults read about 230 words a minute. Rounded to
  /// something a person would say.
  int get minutesPerDay {
    if (days.isEmpty) return 0;
    final verses = days.fold<int>(0, (sum, day) => sum + day.verses);
    final minutes = verses / days.length * 25 / 230;
    if (minutes < 5) return minutes.ceil().clamp(1, 5);
    return (minutes / 5).round() * 5;
  }

  /// Builds a plan from one or more tracks, each read through at an even
  /// pace over [days].
  ///
  /// The pace is even in verses rather than chapters, because chapters are
  /// nothing like the same length: Psalm 117 has two verses and Psalm 119
  /// a hundred and seventy-six. No chapter is split, and no day is empty.
  factory ReadingPlan.even({
    required String id,
    required String name,
    required String summary,
    required String description,
    required int days,
    required List<List<Reference>> tracks,
    bool recommended = false,
  }) {
    final perDay = List.generate(days, (_) => <Reference>[]);
    final versesPerDay = List.filled(days, 0);
    for (final chapters in tracks) {
      final split = _split([for (final c in chapters) _versesIn(c)], days);
      for (var d = 0; d < days; d++) {
        for (final i in split[d]) {
          perDay[d].add(chapters[i]);
          versesPerDay[d] += _versesIn(chapters[i]);
        }
      }
    }
    var slot = 0;
    final built = <PlanDay>[];
    for (var d = 0; d < days; d++) {
      built.add(
        PlanDay(
          number: d + 1,
          chapters: List.unmodifiable(perDay[d]),
          firstSlot: slot,
          verses: versesPerDay[d],
        ),
      );
      slot += perDay[d].length;
    }
    return ReadingPlan._(
      id: id,
      name: name,
      summary: summary,
      description: description,
      days: List.unmodifiable(built),
      recommended: recommended,
    );
  }

  /// Splits weighted items, in order, into [days] runs that are as even as
  /// they can be without splitting an item or leaving a day empty.
  ///
  /// Each day takes items until the running total reaches that day's share
  /// of the whole — an item goes to the day its middle falls in — while
  /// always leaving at least one item for every day still to come. With
  /// fewer items than days the last days are empty; no plan here asks for
  /// that.
  static List<List<int>> split(List<int> weights, int days) =>
      _split(weights, days);

  static List<List<int>> _split(List<int> weights, int days) {
    final result = List.generate(days, (_) => <int>[]);
    if (weights.isEmpty || days <= 0) return result;
    final total = weights.fold<int>(0, (a, b) => a + b);
    var next = 0;
    var running = 0.0;
    for (var d = 0; d < days; d++) {
      final target = total * (d + 1) / days;
      final daysAfter = days - d - 1;
      while (next < weights.length) {
        final left = weights.length - next;
        final mustTake = result[d].isEmpty;
        final mustLeave = left <= daysAfter;
        if (!mustTake && mustLeave) break;
        if (!mustTake && d < days - 1 && running + weights[next] / 2 > target) {
          break;
        }
        result[d].add(next);
        running += weights[next];
        next++;
      }
    }
    return result;
  }
}

/// Every chapter of these books, in order.
List<Reference> chaptersOf(List<String> codes) => [
  for (final code in codes)
    for (var c = 1; c <= _chapterCountOf(code); c++) Reference(code, c),
];

/// Two runs of chapters woven into one, each spread evenly through the
/// other: the New Testament with a psalm every so often.
List<Reference> weave(List<Reference> a, List<Reference> b) {
  final result = <Reference>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    // Whichever run is further behind its share goes next.
    final aDue =
        i < a.length && (j >= b.length || i / a.length <= j / b.length);
    result.add(aDue ? a[i++] : b[j++]);
  }
  return result;
}

/// The plans OpenWord offers.
///
/// Built from the English verse counts rather than from whichever
/// translation is open, so a plan's days are the same in every translation
/// and a reader can change translation half way through without their
/// place moving.
class ReadingPlans {
  const ReadingPlans._();

  static List<ReadingPlan>? _all;

  static List<ReadingPlan> get all => _all ??= [
    gospels,
    bibleInAYear,
    bothTestaments,
    newTestament90,
    psalms30,
    proverbsMonth,
  ];

  static ReadingPlan? byId(String id) {
    for (final plan in all) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  static List<Reference> _section(
    BookSection section, {
    Set<String> except = const {},
  }) => chaptersOf([
    for (final code in _books(section))
      if (!except.contains(code)) code,
  ]);

  static List<String> _books(BookSection section) => [
    for (final book in BookMeta.all)
      if (book.section == section && englishVerseCounts.containsKey(book.code))
        book.code,
  ];

  static final ReadingPlan gospels = ReadingPlan.even(
    id: 'gospels-30',
    name: 'The Gospels in 30 days',
    summary: 'The life of Jesus, told four times',
    description:
        'Matthew, Mark, Luke and John, about three chapters a day. The '
        'place most people start: short, all story, and it is the centre '
        'of the rest.',
    days: 30,
    tracks: [
      chaptersOf(['MAT', 'MRK', 'LUK', 'JHN']),
    ],
    recommended: true,
  );

  static final ReadingPlan bibleInAYear = ReadingPlan.even(
    id: 'bible-year',
    name: 'The Bible in a year',
    summary: 'Genesis to Revelation, straight through',
    description:
        'Every book in the order the Bible prints them, a little over '
        'three chapters a day. Days are even in length rather than in '
        'chapters, so a day of short chapters has more of them.',
    days: 365,
    tracks: [
      [
        ..._section(BookSection.oldTestament),
        ..._section(BookSection.newTestament),
      ],
    ],
  );

  static final ReadingPlan bothTestaments = ReadingPlan.even(
    id: 'ot-nt-year',
    name: 'Old and New Testament together',
    summary: 'The whole Bible in a year, from both ends at once',
    description:
        'Two readings a day: one from the Old Testament, and one from the '
        'New Testament or the Psalms, so Leviticus is never all there is. '
        'The Psalms are read alongside the New Testament, the way the old '
        'M\'Cheyne plan reads them, rather than all at once in the middle.',
    days: 365,
    tracks: [
      _section(BookSection.oldTestament, except: {'PSA'}),
      weave(_section(BookSection.newTestament), chaptersOf(['PSA'])),
    ],
  );

  static final ReadingPlan newTestament90 = ReadingPlan.even(
    id: 'nt-90',
    name: 'The New Testament in 90 days',
    summary: 'Matthew to Revelation in three months',
    description:
        'The whole New Testament in order, about three chapters a day: the '
        'Gospels, the early church, the letters and Revelation.',
    days: 90,
    tracks: [_section(BookSection.newTestament)],
  );

  static final ReadingPlan psalms30 = ReadingPlan.even(
    id: 'psalms-30',
    name: 'The Psalms in a month',
    summary: 'All 150 psalms in 30 days',
    description:
        'The prayer book of the Bible, about five psalms a day. Psalm 119, '
        'the longest chapter in the Bible, has a day to itself.',
    days: 30,
    tracks: [
      chaptersOf(['PSA']),
    ],
  );

  static final ReadingPlan proverbsMonth = ReadingPlan.even(
    id: 'proverbs-31',
    name: 'Proverbs in a month',
    summary: 'One chapter a day, 31 days',
    description:
        'Proverbs has 31 chapters and a month has up to 31 days, so many '
        'people read the chapter that matches the date. Five minutes a day.',
    days: 31,
    tracks: [
      chaptersOf(['PRO']),
    ],
  );
}

final Map<String, List<int>> _parsedCounts = {};

List<int> _countsOf(String code) => _parsedCounts.putIfAbsent(
  code,
  () => [
    for (final part in (englishVerseCounts[code] ?? '').split(' '))
      if (part.isNotEmpty) int.parse(part),
  ],
);

int _chapterCountOf(String code) => _countsOf(code).length;

int _versesIn(Reference chapter) {
  final counts = _countsOf(chapter.bookCode);
  final index = chapter.chapter - 1;
  return index >= 0 && index < counts.length ? counts[index] : 0;
}
