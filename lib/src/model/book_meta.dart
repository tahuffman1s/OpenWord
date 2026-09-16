/// Canonical metadata for every book that can appear in a USFX Bible.
///
/// Codes are the Paratext / USFX book identifiers used by eBible.org files.
library;

enum BookSection {
  oldTestament('Old Testament'),
  deuterocanon('Deuterocanonical'),
  newTestament('New Testament');

  const BookSection(this.label);

  final String label;
}

/// Static description of a book: its code, display names and canonical slot.
class BookMeta {
  const BookMeta(this.code, this.name, this.abbrev, this.section);

  final String code;
  final String name;
  final String abbrev;
  final BookSection section;

  /// Name used for alphabetical grouping: `1 Samuel` sorts under `S`, because
  /// that is where a reader looks for it.
  String get sortName {
    final match = _leadingNumeral.firstMatch(name);
    if (match == null) return name;
    return '${match.group(2)}, ${match.group(1)}';
  }

  /// The letter this book lives under in the A–Z rail.
  String get initial => sortName.substring(0, 1).toUpperCase();

  static final RegExp _leadingNumeral = RegExp(r'^([123]) (.+)$');

  /// Canonical order of every known book, used to sort the library.
  static const List<BookMeta> all = <BookMeta>[
    BookMeta('GEN', 'Genesis', 'Gen', BookSection.oldTestament),
    BookMeta('EXO', 'Exodus', 'Exo', BookSection.oldTestament),
    BookMeta('LEV', 'Leviticus', 'Lev', BookSection.oldTestament),
    BookMeta('NUM', 'Numbers', 'Num', BookSection.oldTestament),
    BookMeta('DEU', 'Deuteronomy', 'Deu', BookSection.oldTestament),
    BookMeta('JOS', 'Joshua', 'Jos', BookSection.oldTestament),
    BookMeta('JDG', 'Judges', 'Jdg', BookSection.oldTestament),
    BookMeta('RUT', 'Ruth', 'Rut', BookSection.oldTestament),
    BookMeta('1SA', '1 Samuel', '1Sa', BookSection.oldTestament),
    BookMeta('2SA', '2 Samuel', '2Sa', BookSection.oldTestament),
    BookMeta('1KI', '1 Kings', '1Ki', BookSection.oldTestament),
    BookMeta('2KI', '2 Kings', '2Ki', BookSection.oldTestament),
    BookMeta('1CH', '1 Chronicles', '1Ch', BookSection.oldTestament),
    BookMeta('2CH', '2 Chronicles', '2Ch', BookSection.oldTestament),
    BookMeta('EZR', 'Ezra', 'Ezr', BookSection.oldTestament),
    BookMeta('NEH', 'Nehemiah', 'Neh', BookSection.oldTestament),
    BookMeta('EST', 'Esther', 'Est', BookSection.oldTestament),
    BookMeta('JOB', 'Job', 'Job', BookSection.oldTestament),
    BookMeta('PSA', 'Psalms', 'Psa', BookSection.oldTestament),
    BookMeta('PRO', 'Proverbs', 'Pro', BookSection.oldTestament),
    BookMeta('ECC', 'Ecclesiastes', 'Ecc', BookSection.oldTestament),
    BookMeta('SNG', 'Song of Solomon', 'Sng', BookSection.oldTestament),
    BookMeta('ISA', 'Isaiah', 'Isa', BookSection.oldTestament),
    BookMeta('JER', 'Jeremiah', 'Jer', BookSection.oldTestament),
    BookMeta('LAM', 'Lamentations', 'Lam', BookSection.oldTestament),
    BookMeta('EZK', 'Ezekiel', 'Ezk', BookSection.oldTestament),
    BookMeta('DAN', 'Daniel', 'Dan', BookSection.oldTestament),
    BookMeta('HOS', 'Hosea', 'Hos', BookSection.oldTestament),
    BookMeta('JOL', 'Joel', 'Jol', BookSection.oldTestament),
    BookMeta('AMO', 'Amos', 'Amo', BookSection.oldTestament),
    BookMeta('OBA', 'Obadiah', 'Oba', BookSection.oldTestament),
    BookMeta('JON', 'Jonah', 'Jon', BookSection.oldTestament),
    BookMeta('MIC', 'Micah', 'Mic', BookSection.oldTestament),
    BookMeta('NAM', 'Nahum', 'Nam', BookSection.oldTestament),
    BookMeta('HAB', 'Habakkuk', 'Hab', BookSection.oldTestament),
    BookMeta('ZEP', 'Zephaniah', 'Zep', BookSection.oldTestament),
    BookMeta('HAG', 'Haggai', 'Hag', BookSection.oldTestament),
    BookMeta('ZEC', 'Zechariah', 'Zec', BookSection.oldTestament),
    BookMeta('MAL', 'Malachi', 'Mal', BookSection.oldTestament),
    BookMeta('TOB', 'Tobit', 'Tob', BookSection.deuterocanon),
    BookMeta('JDT', 'Judith', 'Jdt', BookSection.deuterocanon),
    BookMeta('ESG', 'Esther (Greek)', 'EsG', BookSection.deuterocanon),
    BookMeta('WIS', 'Wisdom', 'Wis', BookSection.deuterocanon),
    BookMeta('SIR', 'Sirach', 'Sir', BookSection.deuterocanon),
    BookMeta('BAR', 'Baruch', 'Bar', BookSection.deuterocanon),
    BookMeta('LJE', 'Letter of Jeremiah', 'LJe', BookSection.deuterocanon),
    BookMeta('S3Y', 'Song of the Three', 'S3Y', BookSection.deuterocanon),
    BookMeta('SUS', 'Susanna', 'Sus', BookSection.deuterocanon),
    BookMeta('BEL', 'Bel and the Dragon', 'Bel', BookSection.deuterocanon),
    BookMeta('1MA', '1 Maccabees', '1Ma', BookSection.deuterocanon),
    BookMeta('2MA', '2 Maccabees', '2Ma', BookSection.deuterocanon),
    BookMeta('3MA', '3 Maccabees', '3Ma', BookSection.deuterocanon),
    BookMeta('4MA', '4 Maccabees', '4Ma', BookSection.deuterocanon),
    BookMeta('1ES', '1 Esdras', '1Es', BookSection.deuterocanon),
    BookMeta('2ES', '2 Esdras', '2Es', BookSection.deuterocanon),
    BookMeta('MAN', 'Prayer of Manasseh', 'Man', BookSection.deuterocanon),
    BookMeta('PS2', 'Psalm 151', 'Ps2', BookSection.deuterocanon),
    BookMeta('MAT', 'Matthew', 'Mat', BookSection.newTestament),
    BookMeta('MRK', 'Mark', 'Mrk', BookSection.newTestament),
    BookMeta('LUK', 'Luke', 'Luk', BookSection.newTestament),
    BookMeta('JHN', 'John', 'Jhn', BookSection.newTestament),
    BookMeta('ACT', 'Acts', 'Act', BookSection.newTestament),
    BookMeta('ROM', 'Romans', 'Rom', BookSection.newTestament),
    BookMeta('1CO', '1 Corinthians', '1Co', BookSection.newTestament),
    BookMeta('2CO', '2 Corinthians', '2Co', BookSection.newTestament),
    BookMeta('GAL', 'Galatians', 'Gal', BookSection.newTestament),
    BookMeta('EPH', 'Ephesians', 'Eph', BookSection.newTestament),
    BookMeta('PHP', 'Philippians', 'Php', BookSection.newTestament),
    BookMeta('COL', 'Colossians', 'Col', BookSection.newTestament),
    BookMeta('1TH', '1 Thessalonians', '1Th', BookSection.newTestament),
    BookMeta('2TH', '2 Thessalonians', '2Th', BookSection.newTestament),
    BookMeta('1TI', '1 Timothy', '1Ti', BookSection.newTestament),
    BookMeta('2TI', '2 Timothy', '2Ti', BookSection.newTestament),
    BookMeta('TIT', 'Titus', 'Tit', BookSection.newTestament),
    BookMeta('PHM', 'Philemon', 'Phm', BookSection.newTestament),
    BookMeta('HEB', 'Hebrews', 'Heb', BookSection.newTestament),
    BookMeta('JAS', 'James', 'Jas', BookSection.newTestament),
    BookMeta('1PE', '1 Peter', '1Pe', BookSection.newTestament),
    BookMeta('2PE', '2 Peter', '2Pe', BookSection.newTestament),
    BookMeta('1JN', '1 John', '1Jn', BookSection.newTestament),
    BookMeta('2JN', '2 John', '2Jn', BookSection.newTestament),
    BookMeta('3JN', '3 John', '3Jn', BookSection.newTestament),
    BookMeta('JUD', 'Jude', 'Jud', BookSection.newTestament),
    BookMeta('REV', 'Revelation', 'Rev', BookSection.newTestament),
  ];

  static final Map<String, BookMeta> byCode = {
    for (final book in all) book.code: book,
  };

  static final Map<String, int> ordinalByCode = {
    for (var i = 0; i < all.length; i++) all[i].code: i,
  };

  static BookMeta? lookup(String code) => byCode[code.toUpperCase()];
}

/// Traditional groupings used by the canonical book picker.
enum BookDivision {
  law('Law', 'Law'),
  history('History', 'Hist'),
  wisdom('Wisdom', 'Wis'),
  prophets('Prophets', 'Proph'),
  deuterocanon('Deuterocanonical', 'DC'),
  gospels('Gospels', 'Gsp'),
  acts('Acts', 'Acts'),
  letters('Letters', 'Ltr'),
  apocalypse('Revelation', 'Rev');

  const BookDivision(this.label, this.shortLabel);

  final String label;

  /// Fits the narrow index rail.
  final String shortLabel;
}

/// Division lookup, derived from canonical position.
extension BookMetaDivision on BookMeta {
  BookDivision get division {
    if (section == BookSection.deuterocanon) return BookDivision.deuterocanon;
    final ordinal = BookMeta.ordinalByCode[code] ?? 0;
    if (section == BookSection.oldTestament) {
      if (ordinal <= 4) return BookDivision.law;
      if (ordinal <= 16) return BookDivision.history;
      if (ordinal <= 21) return BookDivision.wisdom;
      return BookDivision.prophets;
    }
    if (code == 'REV') return BookDivision.apocalypse;
    if (code == 'ACT') return BookDivision.acts;
    const gospels = {'MAT', 'MRK', 'LUK', 'JHN'};
    if (gospels.contains(code)) return BookDivision.gospels;
    return BookDivision.letters;
  }
}
