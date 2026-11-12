/**
 * Canonical metadata for every book that can appear in a USFX Bible.
 *
 * Codes are the Paratext / USFX book identifiers used by eBible.org files.
 */

export enum BookSection {
  oldTestament = 'oldTestament',
  deuterocanon = 'deuterocanon',
  newTestament = 'newTestament',
}

export const bookSectionLabel: Record<BookSection, string> = {
  [BookSection.oldTestament]: 'Old Testament',
  [BookSection.deuterocanon]: 'Deuterocanonical',
  [BookSection.newTestament]: 'New Testament',
};

/** Traditional groupings used by the canonical book picker. */
export enum BookDivision {
  law = 'law',
  history = 'history',
  wisdom = 'wisdom',
  prophets = 'prophets',
  deuterocanon = 'deuterocanon',
  gospels = 'gospels',
  acts = 'acts',
  letters = 'letters',
  apocalypse = 'apocalypse',
}

export const bookDivisions: readonly BookDivision[] = [
  BookDivision.law,
  BookDivision.history,
  BookDivision.wisdom,
  BookDivision.prophets,
  BookDivision.deuterocanon,
  BookDivision.gospels,
  BookDivision.acts,
  BookDivision.letters,
  BookDivision.apocalypse,
];

export const bookDivisionLabel: Record<BookDivision, string> = {
  law: 'Law',
  history: 'History',
  wisdom: 'Wisdom',
  prophets: 'Prophets',
  deuterocanon: 'Deuterocanonical',
  gospels: 'Gospels',
  acts: 'Acts',
  letters: 'Letters',
  apocalypse: 'Revelation',
};

/** Fits the narrow index rail. */
export const bookDivisionShortLabel: Record<BookDivision, string> = {
  law: 'Law',
  history: 'Hist',
  wisdom: 'Wis',
  prophets: 'Proph',
  deuterocanon: 'DC',
  gospels: 'Gsp',
  acts: 'Acts',
  letters: 'Ltr',
  apocalypse: 'Rev',
};

const leadingNumeral = /^([123]) (.+)$/;

/** Static description of a book: its code, display names and canonical slot. */
export class BookMeta {
  constructor(
    readonly code: string,
    readonly name: string,
    readonly abbrev: string,
    readonly section: BookSection,
  ) {}

  /**
   * Name used for alphabetical grouping: `1 Samuel` sorts under `S`, because
   * that is where a reader looks for it.
   */
  get sortName(): string {
    const match = leadingNumeral.exec(this.name);
    if (!match) return this.name;
    return `${match[2]}, ${match[1]}`;
  }

  /** The letter this book lives under in the A–Z rail. */
  get initial(): string {
    return this.sortName.substring(0, 1).toUpperCase();
  }

  /** Division lookup, derived from canonical position. */
  get division(): BookDivision {
    if (this.section === BookSection.deuterocanon) return BookDivision.deuterocanon;
    const ordinal = BookMeta.ordinalByCode.get(this.code) ?? 0;
    if (this.section === BookSection.oldTestament) {
      if (ordinal <= 4) return BookDivision.law;
      if (ordinal <= 16) return BookDivision.history;
      if (ordinal <= 21) return BookDivision.wisdom;
      return BookDivision.prophets;
    }
    if (this.code === 'REV') return BookDivision.apocalypse;
    if (this.code === 'ACT') return BookDivision.acts;
    if (this.code === 'MAT' || this.code === 'MRK' || this.code === 'LUK' || this.code === 'JHN') {
      return BookDivision.gospels;
    }
    return BookDivision.letters;
  }

  /** Canonical order of every known book, used to sort the library. */
  static readonly all: readonly BookMeta[] = [
    new BookMeta('GEN', 'Genesis', 'Gen', BookSection.oldTestament),
    new BookMeta('EXO', 'Exodus', 'Exo', BookSection.oldTestament),
    new BookMeta('LEV', 'Leviticus', 'Lev', BookSection.oldTestament),
    new BookMeta('NUM', 'Numbers', 'Num', BookSection.oldTestament),
    new BookMeta('DEU', 'Deuteronomy', 'Deu', BookSection.oldTestament),
    new BookMeta('JOS', 'Joshua', 'Jos', BookSection.oldTestament),
    new BookMeta('JDG', 'Judges', 'Jdg', BookSection.oldTestament),
    new BookMeta('RUT', 'Ruth', 'Rut', BookSection.oldTestament),
    new BookMeta('1SA', '1 Samuel', '1Sa', BookSection.oldTestament),
    new BookMeta('2SA', '2 Samuel', '2Sa', BookSection.oldTestament),
    new BookMeta('1KI', '1 Kings', '1Ki', BookSection.oldTestament),
    new BookMeta('2KI', '2 Kings', '2Ki', BookSection.oldTestament),
    new BookMeta('1CH', '1 Chronicles', '1Ch', BookSection.oldTestament),
    new BookMeta('2CH', '2 Chronicles', '2Ch', BookSection.oldTestament),
    new BookMeta('EZR', 'Ezra', 'Ezr', BookSection.oldTestament),
    new BookMeta('NEH', 'Nehemiah', 'Neh', BookSection.oldTestament),
    new BookMeta('EST', 'Esther', 'Est', BookSection.oldTestament),
    new BookMeta('JOB', 'Job', 'Job', BookSection.oldTestament),
    new BookMeta('PSA', 'Psalms', 'Psa', BookSection.oldTestament),
    new BookMeta('PRO', 'Proverbs', 'Pro', BookSection.oldTestament),
    new BookMeta('ECC', 'Ecclesiastes', 'Ecc', BookSection.oldTestament),
    new BookMeta('SNG', 'Song of Solomon', 'Sng', BookSection.oldTestament),
    new BookMeta('ISA', 'Isaiah', 'Isa', BookSection.oldTestament),
    new BookMeta('JER', 'Jeremiah', 'Jer', BookSection.oldTestament),
    new BookMeta('LAM', 'Lamentations', 'Lam', BookSection.oldTestament),
    new BookMeta('EZK', 'Ezekiel', 'Ezk', BookSection.oldTestament),
    new BookMeta('DAN', 'Daniel', 'Dan', BookSection.oldTestament),
    new BookMeta('HOS', 'Hosea', 'Hos', BookSection.oldTestament),
    new BookMeta('JOL', 'Joel', 'Jol', BookSection.oldTestament),
    new BookMeta('AMO', 'Amos', 'Amo', BookSection.oldTestament),
    new BookMeta('OBA', 'Obadiah', 'Oba', BookSection.oldTestament),
    new BookMeta('JON', 'Jonah', 'Jon', BookSection.oldTestament),
    new BookMeta('MIC', 'Micah', 'Mic', BookSection.oldTestament),
    new BookMeta('NAM', 'Nahum', 'Nam', BookSection.oldTestament),
    new BookMeta('HAB', 'Habakkuk', 'Hab', BookSection.oldTestament),
    new BookMeta('ZEP', 'Zephaniah', 'Zep', BookSection.oldTestament),
    new BookMeta('HAG', 'Haggai', 'Hag', BookSection.oldTestament),
    new BookMeta('ZEC', 'Zechariah', 'Zec', BookSection.oldTestament),
    new BookMeta('MAL', 'Malachi', 'Mal', BookSection.oldTestament),
    new BookMeta('TOB', 'Tobit', 'Tob', BookSection.deuterocanon),
    new BookMeta('JDT', 'Judith', 'Jdt', BookSection.deuterocanon),
    new BookMeta('ESG', 'Esther (Greek)', 'EsG', BookSection.deuterocanon),
    new BookMeta('WIS', 'Wisdom', 'Wis', BookSection.deuterocanon),
    new BookMeta('SIR', 'Sirach', 'Sir', BookSection.deuterocanon),
    new BookMeta('BAR', 'Baruch', 'Bar', BookSection.deuterocanon),
    new BookMeta('LJE', 'Letter of Jeremiah', 'LJe', BookSection.deuterocanon),
    new BookMeta('S3Y', 'Song of the Three', 'S3Y', BookSection.deuterocanon),
    new BookMeta('SUS', 'Susanna', 'Sus', BookSection.deuterocanon),
    new BookMeta('BEL', 'Bel and the Dragon', 'Bel', BookSection.deuterocanon),
    new BookMeta('1MA', '1 Maccabees', '1Ma', BookSection.deuterocanon),
    new BookMeta('2MA', '2 Maccabees', '2Ma', BookSection.deuterocanon),
    new BookMeta('3MA', '3 Maccabees', '3Ma', BookSection.deuterocanon),
    new BookMeta('4MA', '4 Maccabees', '4Ma', BookSection.deuterocanon),
    new BookMeta('1ES', '1 Esdras', '1Es', BookSection.deuterocanon),
    new BookMeta('2ES', '2 Esdras', '2Es', BookSection.deuterocanon),
    new BookMeta('MAN', 'Prayer of Manasseh', 'Man', BookSection.deuterocanon),
    new BookMeta('PS2', 'Psalm 151', 'Ps2', BookSection.deuterocanon),
    new BookMeta('MAT', 'Matthew', 'Mat', BookSection.newTestament),
    new BookMeta('MRK', 'Mark', 'Mrk', BookSection.newTestament),
    new BookMeta('LUK', 'Luke', 'Luk', BookSection.newTestament),
    new BookMeta('JHN', 'John', 'Jhn', BookSection.newTestament),
    new BookMeta('ACT', 'Acts', 'Act', BookSection.newTestament),
    new BookMeta('ROM', 'Romans', 'Rom', BookSection.newTestament),
    new BookMeta('1CO', '1 Corinthians', '1Co', BookSection.newTestament),
    new BookMeta('2CO', '2 Corinthians', '2Co', BookSection.newTestament),
    new BookMeta('GAL', 'Galatians', 'Gal', BookSection.newTestament),
    new BookMeta('EPH', 'Ephesians', 'Eph', BookSection.newTestament),
    new BookMeta('PHP', 'Philippians', 'Php', BookSection.newTestament),
    new BookMeta('COL', 'Colossians', 'Col', BookSection.newTestament),
    new BookMeta('1TH', '1 Thessalonians', '1Th', BookSection.newTestament),
    new BookMeta('2TH', '2 Thessalonians', '2Th', BookSection.newTestament),
    new BookMeta('1TI', '1 Timothy', '1Ti', BookSection.newTestament),
    new BookMeta('2TI', '2 Timothy', '2Ti', BookSection.newTestament),
    new BookMeta('TIT', 'Titus', 'Tit', BookSection.newTestament),
    new BookMeta('PHM', 'Philemon', 'Phm', BookSection.newTestament),
    new BookMeta('HEB', 'Hebrews', 'Heb', BookSection.newTestament),
    new BookMeta('JAS', 'James', 'Jas', BookSection.newTestament),
    new BookMeta('1PE', '1 Peter', '1Pe', BookSection.newTestament),
    new BookMeta('2PE', '2 Peter', '2Pe', BookSection.newTestament),
    new BookMeta('1JN', '1 John', '1Jn', BookSection.newTestament),
    new BookMeta('2JN', '2 John', '2Jn', BookSection.newTestament),
    new BookMeta('3JN', '3 John', '3Jn', BookSection.newTestament),
    new BookMeta('JUD', 'Jude', 'Jud', BookSection.newTestament),
    new BookMeta('REV', 'Revelation', 'Rev', BookSection.newTestament),
  ];

  static readonly byCode: ReadonlyMap<string, BookMeta> = new Map(BookMeta.all.map((b) => [b.code, b]));

  static readonly ordinalByCode: ReadonlyMap<string, number> = new Map(BookMeta.all.map((b, i) => [b.code, i]));

  static lookup(code: string): BookMeta | undefined {
    return BookMeta.byCode.get(code.toUpperCase());
  }
}
