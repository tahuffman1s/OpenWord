import { ChangeNotifier } from '../infra/changeNotifier';
import { Prefs } from '../infra/prefs';
import { Versification, type TranslationInfo } from '../model/bible';
import { compareCodeUnits } from '../model/searchIndex';
import { Translations } from './translations';

/** Light, dark, or whichever the system is in; the index is persisted. */
export enum ThemeMode {
  system = 0,
  light = 1,
  dark = 2,
}

/** How the book picker lists books. The index is persisted. */
export enum BookOrder {
  /** Genesis to Revelation, grouped by division. */
  canonical = 0,

  /** Alphabetical, with numbered books under their name. */
  alphabetical = 1,
}

export const bookOrderLabel: Record<BookOrder, string> = {
  [BookOrder.canonical]: 'Canon',
  [BookOrder.alphabetical]: 'A–Z',
};

/**
 * Reading typeface. Literata is bundled with the app; "Sans" follows the
 * platform's own UI font. The index is persisted.
 */
export enum ReadingFont {
  serif = 0,
  sans = 1,
}

export const readingFontLabel: Record<ReadingFont, string> = {
  [ReadingFont.serif]: 'Serif',
  [ReadingFont.sans]: 'Sans',
};

export const readingFontFamily: Record<ReadingFont, string | null> = {
  [ReadingFont.serif]: 'Literata',
  [ReadingFont.sans]: null,
};

const kThemeMode = 'themeMode';
const kDynamicColor = 'dynamicColor';
const kSeedColor = 'seedColor';
const kFontScale = 'fontScale';
const kLineHeight = 'lineHeight';
const kFont = 'readingFont';
const kRedLetter = 'redLetter';
const kFootnotes = 'footnotes';
const kParagraphs = 'paragraphs';
const kVerseNumbers = 'verseNumbers';
const kDeuterocanon = 'deuterocanon';
const kBookOrder = 'bookOrder';
const kTranslation = 'translation';
const kCompare = 'compareTranslation';
const kCheckUpdates = 'checkForUpdates';
const kLastCheck = 'lastUpdateCheck';
const kSkippedUpdate = 'skippedUpdate';
const kAnchorAnyway = 'anchorAnyway';
const kSpeechPace = 'speechPace';
const kOldSpeechRate = 'speechRate';
const kSpeechVoice = 'speechVoice';
const kLearnAutoSpeak = 'learnAutoSpeak';

/** User preferences, persisted with `Prefs`. */
export class Settings extends ChangeNotifier {
  /**
   * The palette seeds the colour picker offers. A browser has no system
   * palette to read, so the one chosen is what the whole scheme is drawn
   * from. Each is ARGB.
   */
  static readonly seedChoices: readonly number[] = [
    0xff6750a4, 0xff1b6c4f, 0xff8c4a2f, 0xff2d5fa8, 0xff7d5260, 0xff4e5b31, 0xff5b5891, 0xff8a5100,
  ];

  private constructor(private readonly prefs: Prefs) {
    super();
  }

  static async load(prefs: Prefs = Prefs.open()): Promise<Settings> {
    return new Settings(prefs);
  }

  get themeMode(): ThemeMode {
    return themeModeFromIndex(this.prefs.getInt(kThemeMode) ?? ThemeMode.system);
  }
  set themeMode(value: ThemeMode) {
    this.writeInt(kThemeMode, value);
  }

  get useDynamicColor(): boolean {
    return this.prefs.getBool(kDynamicColor) ?? true;
  }
  set useDynamicColor(value: boolean) {
    this.writeBool(kDynamicColor, value);
  }

  /** The palette seed, as ARGB. */
  get seedColor(): number {
    return this.prefs.getInt(kSeedColor) ?? Settings.seedChoices[0];
  }
  set seedColor(value: number) {
    this.writeInt(kSeedColor, value >>> 0);
  }

  get fontScale(): number {
    return this.prefs.getDouble(kFontScale) ?? 1.0;
  }
  set fontScale(value: number) {
    this.writeDouble(kFontScale, value);
  }

  get lineHeight(): number {
    return this.prefs.getDouble(kLineHeight) ?? 1.6;
  }
  set lineHeight(value: number) {
    this.writeDouble(kLineHeight, value);
  }

  /** The speeds reading aloud offers. */
  static readonly speechRates: readonly number[] = [0.75, 1.0, 1.25, 1.5, 2.0];

  /**
   * How fast reading aloud goes, as a multiple of the voice's natural
   * pace.
   *
   * Before 1.23 a multiple of a pace a fifth slower than that — the
   * voice's own "speed prior", which made 1× drag — and kept under
   * another name. A speed chosen then is carried over as the nearest
   * that sounds the same.
   */
  get speechRate(): number {
    const pace = this.prefs.getDouble(kSpeechPace);
    if (pace !== null) return pace;
    const before = this.prefs.getDouble(kOldSpeechRate);
    if (before === null) return 1.0;
    const same = before * 0.8;
    return Settings.speechRates.reduce((a, b) => (Math.abs(a - same) <= Math.abs(b - same) ? a : b));
  }

  set speechRate(value: number) {
    this.writeDouble(kSpeechPace, value);
  }

  /**
   * Whether practice and the rounds speak of their own accord: a verse as
   * it appears, a tile as it is tapped, the verse again once answered.
   * The speaker button works either way.
   */
  get learnAutoSpeak(): boolean {
    return this.prefs.getBool(kLearnAutoSpeak) ?? true;
  }
  set learnAutoSpeak(value: boolean) {
    this.writeBool(kLearnAutoSpeak, value);
  }

  /**
   * The voice chosen for reading aloud, by the name it is kept by, or
   * null for the first.
   */
  get speechVoice(): string | null {
    return this.prefs.getString(kSpeechVoice);
  }
  set speechVoice(value: string | null) {
    if (value === null) {
      this.prefs.remove(kSpeechVoice);
      this.notifyListeners();
    } else {
      this.writeString(kSpeechVoice, value);
    }
  }

  get readingFont(): ReadingFont {
    return readingFontFromIndex(this.prefs.getInt(kFont) ?? ReadingFont.serif);
  }
  set readingFont(value: ReadingFont) {
    this.writeInt(kFont, value);
  }

  get redLetter(): boolean {
    return this.prefs.getBool(kRedLetter) ?? true;
  }
  set redLetter(value: boolean) {
    this.writeBool(kRedLetter, value);
  }

  get showFootnotes(): boolean {
    return this.prefs.getBool(kFootnotes) ?? true;
  }
  set showFootnotes(value: boolean) {
    this.writeBool(kFootnotes, value);
  }

  /**
   * True: verses flow together in paragraphs, as in a printed Bible.
   * False: every verse starts on its own line.
   */
  get paragraphLayout(): boolean {
    return this.prefs.getBool(kParagraphs) ?? true;
  }
  set paragraphLayout(value: boolean) {
    this.writeBool(kParagraphs, value);
  }

  get showVerseNumbers(): boolean {
    return this.prefs.getBool(kVerseNumbers) ?? true;
  }
  set showVerseNumbers(value: boolean) {
    this.writeBool(kVerseNumbers, value);
  }

  get showDeuterocanon(): boolean {
    return this.prefs.getBool(kDeuterocanon) ?? false;
  }
  set showDeuterocanon(value: boolean) {
    this.writeBool(kDeuterocanon, value);
  }

  get bookOrder(): BookOrder {
    return bookOrderFromIndex(this.prefs.getInt(kBookOrder) ?? BookOrder.canonical);
  }
  set bookOrder(value: BookOrder) {
    this.writeInt(kBookOrder, value);
  }

  get translationId(): string {
    return this.prefs.getString(kTranslation) ?? Translations.fallback.id;
  }
  set translationId(value: string) {
    this.writeString(kTranslation, value);
  }

  /** The translation shown beside the main one, or null when not comparing. */
  get compareTranslationId(): string | null {
    const id = this.prefs.getString(kCompare);
    return id === null || id.length === 0 || id === this.translationId ? null : id;
  }

  set compareTranslationId(value: string | null) {
    if (value === null || value.length === 0) {
      this.prefs.remove(kCompare);
      this.notifyListeners();
      return;
    }
    this.writeString(kCompare, value);
  }

  /**
   * A stored preference that nothing in the app reads now: updates come
   * through the service worker (`src/pwa/serviceWorker.ts`), which looks
   * for a newer build by itself. `lastUpdateCheck` and `skippedUpdate`
   * below are the same.
   */
  get checkForUpdates(): boolean {
    return this.prefs.getBool(kCheckUpdates) ?? true;
  }
  set checkForUpdates(value: boolean) {
    this.writeBool(kCheckUpdates, value);
  }

  get lastUpdateCheck(): Date | null {
    const millis = this.prefs.getInt(kLastCheck);
    return millis === null ? null : new Date(millis);
  }

  set lastUpdateCheck(value: Date | null) {
    if (value === null) {
      this.prefs.remove(kLastCheck);
      this.notifyListeners();
      return;
    }
    this.writeInt(kLastCheck, value.getTime());
  }

  /** A version the reader has told the app not to nag about again. */
  get skippedUpdate(): string | null {
    return this.prefs.getString(kSkippedUpdate);
  }
  set skippedUpdate(value: string | null) {
    if (value === null) {
      this.prefs.remove(kSkippedUpdate);
      this.notifyListeners();
      return;
    }
    this.writeString(kSkippedUpdate, value);
  }

  /**
   * Translations the reader has asked to have the verse-keyed layers on
   * regardless of what their numbering was measured to be.
   */
  get anchoredAnyway(): Set<string> {
    return new Set(this.prefs.getStringList(kAnchorAnyway) ?? []);
  }

  /**
   * Whether the cross-references and the Hebrew and Greek are offered for
   * a translation.
   *
   * Both are keyed to the verse, so they apply to any translation whose
   * numbering agrees with the one they were anchored to; against a Bible
   * numbered otherwise they do not fail, they land on the wrong verse.
   * A translation measured as numbering differently is therefore not
   * offered them — unless the reader has asked for them anyway, which is
   * their call to make: they can see the verse in front of them, and a
   * reference that is out by one is more use to them than none at all.
   */
  offersVerseKeyedLayers(translation: TranslationInfo): boolean {
    return Versification.mayAnchorEnglish(translation.versification) || this.anchoredAnyway.has(translation.id);
  }

  setAnchoredAnyway(id: string, value: boolean): void {
    const ids = this.anchoredAnyway;
    if (value ? ids.has(id) : !ids.has(id)) return;
    if (value) ids.add(id);
    else ids.delete(id);
    this.prefs.setStringList(kAnchorAnyway, [...ids].sort(compareCodeUnits));
    this.notifyListeners();
  }

  // One writer per type rather than one that looks at the value: JS
  // cannot tell an int from a double, so each setter above says which
  // it writes.
  private writeInt(key: string, value: number): void {
    this.prefs.setInt(key, value);
    this.notifyListeners();
  }

  private writeDouble(key: string, value: number): void {
    this.prefs.setDouble(key, value);
    this.notifyListeners();
  }

  private writeBool(key: string, value: boolean): void {
    this.prefs.setBool(key, value);
    this.notifyListeners();
  }

  private writeString(key: string, value: string): void {
    this.prefs.setString(key, value);
    this.notifyListeners();
  }
}

function themeModeFromIndex(index: number): ThemeMode {
  return index >= 0 && index <= 2 ? (index as ThemeMode) : ThemeMode.system;
}

function readingFontFromIndex(index: number): ReadingFont {
  return index >= 0 && index <= 1 ? (index as ReadingFont) : ReadingFont.serif;
}

function bookOrderFromIndex(index: number): BookOrder {
  return index >= 0 && index <= 1 ? (index as BookOrder) : BookOrder.canonical;
}
