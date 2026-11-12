import type { ComponentChildren, RefObject, VNode } from 'preact';
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { registerFeatureOpener, type Feature } from '../app/openFlow';
import { useAppScope, type AppScopeValue } from '../app/scope';
import { Atlas, type AtlasData, type ChapterPlace } from '../data/atlas';
import { BookIntros } from '../data/bookIntros';
import { createSpeechEngine } from '../data/createSpeechEngine';
import { CrossReferences } from '../data/crossReferences';
import type { LibraryController } from '../data/library';
import { ReadingStore } from '../data/marks';
import { neuralVoices, type NeuralVoices } from '../data/neuralVoices';
import { Originals } from '../data/originals';
import type { PlanProgress } from '../data/planProgress';
import { ListeningPlace, ReadAloud, type SpeechEngine, type SpeechVoice } from '../data/readAloud';
import { ArtColours, chapterArtFile } from '../data/readAloudArt';
import { readAloudSessionError, startReadAloudSession, type ReadAloudHandler } from '../data/readAloudSession';
import { ReferenceMatcher } from '../data/referenceSearch';
import { Settings } from '../data/settings';
import { ChangeNotifier, useNotifier } from '../infra/changeNotifier';
import { type Bible, type Book, type Chapter, isVerseText, ReadingDirection, Reference } from '../model/bible';
import { BookSection } from '../model/bookMeta';
import { QuizKind, QuizMaker, type QuizQuestion } from '../model/quiz';
import { Passage, type PlanDay } from '../model/readingPlan';
import type { StrongsNumber } from '../model/strongsCodec';
import { VerseSelection } from '../model/verseSelection';
import type { XrefAnchor } from '../model/xrefCodec';
import { showBookSheet } from './bookSheet';
import { showConcordance } from './concordanceScreen';
import { showCrossReferences } from './crossReferenceSheet';
import { showDisplaySheet } from './displaySheet';
import { useAsync, useMediaQuery } from './hooks';
import {
  AlertDialog,
  AppBar,
  Button,
  Chip,
  DialogAction,
  Icon,
  IconButton,
  LinearProgress,
  ListTile,
  Screen,
  Sheet,
  TextButton,
  TextField,
  TonalButton,
  currentScheme,
  hexOf,
  highlightNames,
  highlightSwatch,
  highlights,
  overlays,
  rgba,
  showSnackBar,
  useOverlay,
} from './m3';
import { historySettled, openDialog, openScreen, openSheet } from './overlaySettle';
import { showMapSheet } from './mapSheet';
import { showBibleNavigator } from './navigatorSheet';
import {
  PosttestCard,
  PretestCard,
  loadLibraryScreen,
  loadOpenSocial,
  loadPlansScreen,
  loadQuizScreen,
  loadSettingsScreen,
  type PlanReading,
  type PosttestCardProps,
  type PretestCardProps,
} from './optionalScreens';
import { showOriginal } from './originalSheet';
import { hasReader, registerReaderGoTo } from './readerNav';
import { showSearch } from './searchScreen';
import { showInstallGuide } from './tutorial/installGuide';
import { VerseSharing, copyText, showVerseImageSheet, type ShareParams } from './verseShare';
import { LinkedText, ScriptureBlock, ScriptureStyle, tintLayer, tintOver, useVerseGestures } from './widgets/scriptureText';
import './readerScreen.css';

/**
 * Whether `bible` has this chapter. A plan is built on the whole English
 * Bible, and an imported translation may be a New Testament, or lack the
 * odd chapter.
 */
function hasChapter(bible: Bible | null, chapter: Reference): boolean {
  return bible?.bookByCode(chapter.bookCode)?.chapterNumbers.includes(chapter.chapter) ?? false;
}

function reduceMotion(): boolean {
  return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** A plan chapter's questions and how the guess and the answer went. */
class Pretest {
  before: number | null = null;
  after: number | null = null;
  constructor(readonly questions: QuizQuestion[]) {}
}

/** What the reader's state asks of the pages: Flutter's `PageController`. */
interface PagerHandle {
  /** Slides to a neighbouring page; anything further is a jump. */
  animateToPage(page: number): void;
}

/**
 * The state of the reading surface — Flutter's `_ReaderScreenState`, kept
 * as one object so that the dozens of things it holds change together and
 * are read by one render. `ReaderScreen` listens to it.
 */
class ReaderController extends ChangeNotifier {
  readonly settings: Settings;
  readonly reading: ReadingStore;
  readonly library: LibraryController;

  /** The pages on screen, once they are; null before and after. */
  pager: PagerHandle | null = null;

  index: Reference[] = [];
  page = 0;

  /**
   * Which neighbour a swipe under way has crossed to, so the app bar can
   * name the chapter coming into view before the page settles on it.
   */
  peek = 0;

  /**
   * A verse to scroll to, and the page it belongs to. Pairing them matters:
   * jumping to another chapter changes the page, and without the page a
   * pending verse would be cleared before the chapter had a chance to use
   * it.
   */
  pendingVerse: number | null = null;
  pendingPage: number | null = null;

  /** Counts the jumps, so going to the same verse twice still scrolls to it. */
  jumpToken = 0;

  private matcherFor: Bible | null = null;
  private indexedFor: Bible | null = null;
  private indexedDeuterocanon = false;

  /**
   * The plan day the reader was last sent to read, so the end of each of
   * its chapters can offer to tick it off — and keep offering Undo after
   * the day is finished and the plan has moved on to the next.
   */
  planFocus: PlanReading | null = null;

  /**
   * Verses chosen together to copy, share or highlight, and the page they
   * are on. A selection belongs to one chapter; turning the page ends it.
   */
  readonly selected = new Set<number>();
  selectionPage: number | null = null;

  get selecting(): boolean {
    return this.selected.size > 0;
  }

  /** Reading aloud: made once, and following the translation that is open. */
  readAloud: ReadAloud | null = null;

  get voice(): ReadAloud {
    return (this.readAloud ??= this.makeReadAloud());
  }

  private makeReadAloud(): ReadAloud {
    const voice = new ReadAloud({
      engine: createSpeechEngine(),
      chapterFor: (reference) => this.bible.bookByCode(reference.bookCode)?.chapter(reference.chapter),
      nextChapter: (chapter) => this.chapterAfterListening(chapter),
      onChapterHeard: (chapter) => this.heardChapter(chapter),
      onPlace: (place) => (this.reading.listeningPlace = place?.encode() ?? null),
    });
    voice.addListener(this.followVoice);
    return voice;
  }

  /** Whether this platform can read aloud at all. */
  get canListen(): boolean {
    return this.voice.engine.isAvailable;
  }

  /**
   * What to read after `chapter`: the rest of the plan day it belongs to,
   * where it belongs to one, and otherwise simply the next chapter.
   */
  private chapterAfterListening(chapter: Reference): Reference | null {
    const hit = this.planSlotFor(chapter);
    if (hit !== null) {
      const day = hit.day;
      for (let i = hit.slot - day.firstSlot + 1; i < day.slotCount; i++) {
        if (hasChapter(this.bible, day.chapters[i])) return day.chapters[i];
      }
      // The day is heard; that is where a plan's listening stops.
      return null;
    }
    const page = this.pageFor(chapter);
    return page + 1 < this.index.length ? this.index[page + 1] : null;
  }

  /**
   * A plan chapter heard from its first verse to its last counts as read,
   * since nobody listening can reach the button at the end of it.
   */
  private heardChapter(chapter: Reference): void {
    // A day with listening in it, for the account's record of the day.
    void this.account?.recordActivity('listen');
    const hit = this.planSlotFor(chapter);
    if (hit === null) return;
    this.reading.setPlanSlot(hit.progress.plan.id, hit.slot, true);
    this.planFocus = { planId: hit.progress.plan.id, day: hit.day.number, chapter };
  }

  /** Keeps the page on the chapter being read. */
  private readonly followVoice = (): void => {
    if (this.disposedNow) return;
    const voice = this.readAloud;
    if (voice === null) return;
    const current = voice.current;
    if (current !== null && (current.bookCode !== this.current.bookCode || current.chapter !== this.current.chapter)) {
      const page = this.pageFor(current);
      this.setPage(page);
      this.pendingPage = page;
      this.pendingVerse = null;
      this.notifyListeners();
      void this.reading.savePosition(current.withVerse(null));
    } else {
      this.notifyListeners();
    }
    const error = voice.error;
    if (error !== null && !voice.isActive) {
      voice.error = null;
      showSnackBar(error);
    }
  };

  /**
   * Hands the voice its settings, and gets it ready to speak — its model
   * unpacked and loaded — so that Listen is heard at once. `load` leaves
   * the model unloaded where the voice has not been made yet.
   */
  private configureVoice(options: { load?: boolean } = {}): void {
    const load = options.load ?? true;
    const voice = load && this.canListen ? this.voice : this.readAloud;
    voice?.configure({
      language: this.bible.translation.language,
      rate: this.settings.speechRate,
      voice: this.settings.speechVoice,
    });
    if (load) voice?.prepare();
  }

  /**
   * Said once, when this device turns out to make speech more slowly
   * than it is heard, which is heard only as pauses.
   */
  private toldTooSlow = false;
  private neural: NeuralVoices | null = null;

  private readonly onNeuralVoices = (): void => {
    if (this.disposedNow || this.toldTooSlow || !(this.neural?.fallingBehind ?? false)) return;
    this.toldTooSlow = true;
    showSnackBar('This device makes speech more slowly than it is heard, so reading aloud pauses between sentences.', {
      duration: 10000,
    });
  };

  /** Where listening got to in `chapter` before, if it got anywhere. */
  private keptPlaceIn(chapter: Reference): ListeningPlace | null {
    const place = ListeningPlace.decode(this.reading.listeningPlace);
    if (
      place === null ||
      place.atTop ||
      place.verse.bookCode !== chapter.bookCode ||
      place.verse.chapter !== chapter.chapter
    ) {
      return null;
    }
    return place;
  }

  /**
   * What the chapter's own Listen does: pauses or resumes what is being
   * read of it, takes up where listening to it stopped before, or starts
   * it from the top.
   */
  readonly listenToChapter = (chapter: Reference): void => {
    const voice = this.readAloud;
    const current = voice?.current ?? null;
    if (voice !== null && current !== null && current.bookCode === chapter.bookCode && current.chapter === chapter.chapter) {
      if (voice.isPlaying) voice.pause();
      else voice.resume();
      return;
    }
    const kept = this.keptPlaceIn(chapter);
    if (kept !== null) {
      this.listen(kept.verse, { offset: kept.offset, fromTop: kept.fromTop });
    } else {
      this.listen(chapter);
    }
  };

  /** What the chapter's Listen says it will do. */
  listenLabel(chapter: Reference): string {
    const voice = this.readAloud;
    const current = voice?.current ?? null;
    if (voice !== null && current !== null && current.bookCode === chapter.bookCode && current.chapter === chapter.chapter) {
      return voice.isPlaying ? 'PAUSE' : 'RESUME';
    }
    return this.keptPlaceIn(chapter) !== null ? 'RESUME' : 'LISTEN';
  }

  listen(from: Reference, options: { only?: Set<number> | null; offset?: number; fromTop?: boolean } = {}): void {
    this.configureVoice();
    this.voice.play(from, options);
    // Handed to the system as well, so it goes on with the screen off and
    // answers the lock screen. Started the first time it is wanted rather
    // than at launch, and never in the way if it cannot be had.
    const scheme = currentScheme();
    const colours = new ArtColours({
      from: hexOf(scheme.primaryContainer),
      to: hexOf(scheme.tertiaryContainer),
      ink: hexOf(scheme.onPrimaryContainer),
      accent: hexOf(scheme.primary),
    });
    void startReadAloudSession(this.voice, () => this.bible.translation.name, {
      artwork: (chapter) => chapterArtFile(chapter, { colours }),
    }).then((session) => {
      if (this.disposedNow) return;
      this.session = session;
      const error = readAloudSessionError;
      if (session === null && error !== null && !this.toldAboutSession) {
        // Said once, so that a lock screen that stays blank has a reason
        // someone can pass on, rather than silence.
        this.toldAboutSession = true;
        showSnackBar(`Lock-screen controls could not start, so reading aloud stops when the screen does. (${error})`, {
          duration: 10000,
        });
      }
    });
  }

  private toldAboutSession = false;

  /** The system's media session, once reading aloud has started it. */
  private session: ReadAloudHandler | null = null;

  readonly openVoiceSettings = async (): Promise<void> => {
    await openSheet(
      <VoiceSheet settings={this.settings} engine={this.voice.engine} language={this.bible.translation.language} />,
      { name: 'voice' },
    );
    this.configureVoice();
  };

  // Held directly rather than looked up on demand, so they are still
  // reachable from dispose().
  bible!: Bible;

  /**
   * Built once per translation; finds citations inside notes and
   * parallel-passage lines.
   */
  matcher: ReferenceMatcher | null = null;

  /** Book introductions, read from the bundle the first time one is opened. */
  readonly intros: BookIntros;

  /**
   * The atlas, read once in the background: the chapter heading has to know
   * whether there is anything to show before it can offer a map.
   */
  private readonly atlas: Atlas;
  atlasData: AtlasData | null = null;
  private readonly xrefs: CrossReferences;
  private readonly originals: Originals;

  private disposedNow = false;

  /** The reader's account, where the app has one running. */
  private readonly account: AppScopeValue['account'] | null;

  constructor(scope: AppScopeValue) {
    super();
    this.settings = scope.settings;
    this.reading = scope.reading;
    this.library = scope.library;
    this.account = scope.account ?? null;
    const bundle = scope.library.bundle;
    this.intros = new BookIntros(bundle);

    // Read in the background, each rebuilding once it is there, so
    // opening a chapter never waits on them. The Hebrew and Greek are four
    // megabytes: the verse sheet offers them once they have arrived.
    this.atlas = new Atlas(bundle);
    void this.atlas.load().then((data) => {
      if (this.disposedNow || data.isEmpty) return;
      this.atlasData = data;
      this.notifyListeners();
    });
    this.xrefs = new CrossReferences(bundle);
    void this.xrefs.load().then(() => this.notifyListeners());
    this.originals = new Originals(bundle);
    void this.originals.load().then(() => this.notifyListeners());

    this.sync();

    // Where the reader left off, or the beginning.
    const resume = this.reading.lastPosition;
    const target = resume !== null && this.bible.bookByCode(resume.bookCode) !== undefined ? resume : new Reference('GEN', 1);
    this.page = this.pageFor(target);
    this.pendingPage = this.page;
    this.pendingVerse = target.verse;
  }

  /**
   * Catches up with the stores before a render — what Flutter's
   * `didChangeDependencies` did: the translation in hand, the matcher
   * built for it, and the flattened list of its chapters.
   */
  sync(): void {
    const bible = this.library.bible;
    if (bible === null) return;
    if (this.matcherFor !== bible) {
      this.matcherFor = bible;
      this.matcher = new ReferenceMatcher(bible.books);
    }
    if (this.readAloud !== null && this.bible !== bible) {
      // A different translation: what was being read is not this one.
      this.readAloud.stop();
    }
    this.bible = bible;
    this.loadOwnOriginals();
    const showDeuterocanon = this.settings.showDeuterocanon;
    if (this.indexedFor !== bible || this.indexedDeuterocanon !== showDeuterocanon) {
      const current = this.index.length === 0 ? null : this.index[this.page];
      this.indexedFor = bible;
      this.indexedDeuterocanon = showDeuterocanon;
      this.rebuildIndex();
      if (current !== null) this.page = this.pageFor(current);
    }
  }

  /** Starts listening to the stores. Called once the reader is on screen. */
  mount(): void {
    this.settings.addListener(this.onSettingsChanged);
    this.neural = neuralVoices;
    this.neural.addListener(this.onNeuralVoices);
    this.syncComparison();
    // Someone who has listened before will likely listen again: the
    // voice starts loading as the app opens, rather than on Listen.
    if (this.settings.speechVoice !== null || this.reading.listeningPlace !== null) {
      this.configureVoice();
    }
  }

  override dispose(): void {
    this.disposedNow = true;
    this.settings.removeListener(this.onSettingsChanged);
    this.neural?.removeListener(this.onNeuralVoices);
    const voice = this.readAloud;
    if (voice !== null) {
      voice.removeListener(this.followVoice);
      this.session?.release(voice);
      voice.dispose();
    }
    super.dispose();
  }

  private readonly onSettingsChanged = (): void => {
    // Any setting at all: the model is loaded only for listening.
    this.configureVoice({ load: false });
    this.syncComparison();
  };

  /** Loads or drops the side-by-side translation to match the setting. */
  private syncComparison(): void {
    const wanted = this.settings.compareTranslationId;
    if (wanted === null) {
      this.library.clearComparison();
    } else if (this.library.comparison?.translation.id !== wanted) {
      void this.library.loadComparison(wanted);
    }
  }

  /**
   * Flattens the Bible into one list of chapters so the pages can carry
   * the whole book-to-book flow.
   */
  private rebuildIndex(): void {
    const showDeuterocanon = this.settings.showDeuterocanon;
    const index: Reference[] = [];
    for (const book of this.bible.books) {
      if (!showDeuterocanon && book.section === BookSection.deuterocanon) continue;
      // From the outline: flattening the Bible must not unpack it.
      for (const number of book.chapterNumbers) index.push(new Reference(book.code, number));
    }
    this.index = index;
    if (this.page >= index.length) this.page = index.length === 0 ? 0 : index.length - 1;
  }

  pageFor(reference: Reference): number {
    const exact = this.index.findIndex(
      (entry) => entry.bookCode === reference.bookCode && entry.chapter === reference.chapter,
    );
    if (exact >= 0) return exact;
    const book = this.index.findIndex((entry) => entry.bookCode === reference.bookCode);
    return book >= 0 ? book : 0;
  }

  get current(): Reference {
    return this.index.length === 0 ? new Reference('GEN', 1) : this.index[this.page];
  }

  get currentBook(): Book {
    return this.bible.bookByCode(this.current.bookCode)!;
  }

  get currentChapter(): Chapter {
    return this.currentBook.chapter(this.current.chapter) ?? this.currentBook.chapters[0];
  }

  /** Turns to a page, ending a selection made on another. */
  private setPage(page: number): void {
    this.page = page;
    this.peek = 0;
    if (this.selectionPage !== page) {
      this.selected.clear();
      this.selectionPage = null;
    }
  }

  readonly goTo = (reference: Reference, options: { animate?: boolean } = {}): void => {
    const page = this.pageFor(reference);
    const from = this.page;
    this.pendingPage = page;
    this.pendingVerse = reference.verse;
    this.jumpToken++;
    if (options.animate === true && Math.abs(page - from) === 1 && this.pager !== null && !reduceMotion()) {
      this.notifyListeners();
      this.pager.animateToPage(page);
    } else {
      this.setPage(page);
      this.notifyListeners();
    }
    void this.reading.savePosition(reference);
  };

  /** The pages settled on another chapter: a swipe, or a slide asked for. */
  readonly onPageChanged = (page: number): void => {
    if (page < 0 || page >= this.index.length || page === this.page) return;
    const programmatic = page === this.pendingPage;
    this.setPage(page);
    if (!programmatic) {
      this.pendingPage = null;
      this.pendingVerse = null;
    }
    this.notifyListeners();
    // A jump has already saved its own position, verse and all.
    if (!programmatic) void this.reading.savePosition(this.index[page]);
  };

  readonly onPeek = (delta: number): void => {
    if (delta === this.peek) return;
    this.peek = delta;
    this.notifyListeners();
  };

  readonly step = (delta: number): void => {
    const next = this.page + delta;
    if (next < 0 || next >= this.index.length) return;
    this.goTo(this.index[next], { animate: true });
  };

  readonly openNavigator = async (): Promise<void> => {
    const reference = await showBibleNavigator({
      books: this.bible.books.filter(
        (book) => this.settings.showDeuterocanon || book.section !== BookSection.deuterocanon,
      ),
      settings: this.settings,
      reading: this.reading,
      current: this.current.withVerse(this.pendingVerse),
    });
    if (reference === undefined || this.disposedNow) return;
    this.goTo(reference);
  };

  readonly openSearch = async (): Promise<void> => {
    const result = await showSearch({ bible: this.bible, from: this.current });
    if (result !== undefined && !this.disposedNow) this.goTo(result);
  };

  /** The library: what is being learnt, how it is going, what is saved. */
  readonly openLibrary = async (initialTab = 0): Promise<void> => {
    const LibraryScreen = await loadLibraryScreen();
    if (LibraryScreen === null) {
      showSnackBar('The library is not here yet.');
      return;
    }
    const result = await openScreen<Reference>(<LibraryScreen initialTab={initialTab} />, { name: 'library' });
    // A screen that knows the reader has sent it there already (readerNav);
    // one that does not closes with the place and leaves it to this.
    if (result instanceof Reference && !hasReader() && !this.disposedNow) this.goTo(result);
  };

  /**
   * Somewhere a screen over the reader has sent it: a verse from the
   * library, a chapter of a plan with the day it belongs to.
   */
  readonly goToFromScreen = (reference: Reference, plan?: PlanReading): void => {
    if (this.disposedNow) return;
    if (plan !== undefined) {
      this.planFocus = plan;
      this.notifyListeners();
      if (!hasChapter(this.bible, plan.chapter)) return;
    }
    this.goTo(reference);
  };

  readonly openSettings = async (): Promise<void> => {
    const SettingsScreen = await loadSettingsScreen();
    if (SettingsScreen === null) {
      showSnackBar('Settings are not here yet.');
      return;
    }
    await openScreen(<SettingsScreen />, { name: 'settings' });
  };

  /** Friends, the feed and the account. */
  readonly openSocial = async (tab: string): Promise<void> => {
    const open = await loadOpenSocial();
    if (open === null) {
      showSnackBar('Friends are not here yet.');
      return;
    }
    await historySettled();
    open(tab);
  };

  /** The verse being read aloud, where it is on this page. */
  speakingVerseOn(chapter: Reference): number | null {
    const current = this.readAloud?.current ?? null;
    if (current === null || current.bookCode !== chapter.bookCode || current.chapter !== chapter.chapter) return null;
    return current.verse;
  }

  /**
   * A page's highlights with the selection laid over them, so a
   * selected verse shows as selected whatever colour it already had.
   */
  withSelection(page: number, tints: Map<number, string>): Map<number, string> {
    if (page !== this.selectionPage || this.selected.size === 0) return tints;
    const tint = rgba(currentScheme().primary, 0.28);
    const out = new Map(tints);
    for (const verse of this.selected) out.set(verse, tintOver(tint, tints.get(verse)));
    return out;
  }

  readonly openPlans = async (): Promise<void> => {
    const PlansScreen = await loadPlansScreen();
    if (PlansScreen === null) {
      showSnackBar('Reading plans are not here yet.');
      return;
    }
    const result = await openScreen<PlanReading>(<PlansScreen />, { name: 'plans' });
    if (result === undefined || result === null || typeof result !== 'object' || hasReader() || this.disposedNow) return;
    this.goToFromScreen(result.chapter, result);
  };

  /**
   * Where `chapter` falls in a plan the reader is following: the day they
   * were sent to first, then each plan's current day.
   */
  private planSlotFor(chapter: Reference): { progress: PlanProgress; day: PlanDay; slot: number } | null {
    const candidates: [PlanProgress, PlanDay][] = [];
    const focus = this.planFocus;
    if (focus !== null) {
      const progress = this.reading.progressFor(focus.planId);
      if (progress !== null && focus.day >= 1 && focus.day <= progress.plan.length) {
        candidates.push([progress, progress.plan.days[focus.day - 1]]);
      }
    }
    for (const progress of this.reading.plans) {
      const day = progress.currentDay;
      if (day !== null) candidates.push([progress, day]);
    }
    for (const [progress, day] of candidates) {
      for (let i = 0; i < day.slotCount; i++) {
        const entry = day.chapters[i];
        if (entry.bookCode === chapter.bookCode && entry.chapter === chapter.chapter) {
          return { progress, day, slot: day.firstSlot + i };
        }
      }
    }
    return null;
  }

  /**
   * The next chapter of the day still to read after `slot`, skipping any
   * this translation does not have.
   */
  private nextInDay(progress: PlanProgress, day: PlanDay, slot: number): Reference | null {
    for (let i = 0; i < day.slotCount; i++) {
      const candidate = day.firstSlot + i;
      if (candidate === slot || progress.isRead(candidate)) continue;
      const chapter = day.chapters[i];
      if (hasChapter(this.bible, chapter)) return chapter;
    }
    return null;
  }

  /**
   * A plan chapter's questions to guess at before reading and answer
   * after, and how each went, by chapter.
   */
  private readonly pretests = new Map<string, Pretest>();

  private pretestFor(chapter: Reference): Pretest | null {
    const key = chapter.withVerse(null).encode();
    const existing = this.pretests.get(key);
    if (existing !== undefined) return existing;
    const hit = this.planSlotFor(chapter);
    if (hit === null || hit.progress.isRead(hit.slot)) return null;
    const questions = new QuizMaker(this.bible).makeForChapter(chapter.withVerse(null));
    if (questions.length === 0) return null;
    const pretest = new Pretest(questions);
    this.pretests.set(key, pretest);
    return pretest;
  }

  /** Before the chapter: guess, where there is a plan chapter unread. */
  pretestCardFor(chapter: Reference): VNode | null {
    const pretest = this.pretestFor(chapter);
    if (pretest === null || pretest.after !== null) return null;
    const Card = PretestCard ?? PretestCardStandIn;
    return (
      <Card questions={pretest.questions.length} guessed={pretest.before} onGuess={() => void this.runPretest(pretest, true)} />
    );
  }

  private async runPretest(pretest: Pretest, before: boolean): Promise<void> {
    const QuizScreen = await loadQuizScreen();
    if (QuizScreen === null) {
      showSnackBar('The questions are not here yet.');
      return;
    }
    const opened = await openScreen<Reference>(
      <QuizScreen
        kind={QuizKind.finishVerse}
        questions={pretest.questions}
        title={before ? 'Guess before you read' : 'After reading'}
        onFinished={(right) => {
          if (before) pretest.before = right;
          else pretest.after = right;
          this.notifyListeners();
        }}
      />,
      { name: 'pretest' },
    );
    if (opened instanceof Reference && !hasReader() && !this.disposedNow) this.goTo(opened);
  }

  planCardFor(chapter: Reference): VNode | null {
    const hit = this.planSlotFor(chapter);
    if (hit === null) return null;
    const { progress, day, slot } = hit;
    const next = this.nextInDay(progress, day, slot);
    const plan = progress.plan;
    const pretest = this.pretests.get(chapter.withVerse(null).encode());
    const card = (
      <PlanChapterCard
        planName={plan.name}
        day={day.number}
        read={progress.isRead(slot)}
        nextLabel={next === null ? null : Passage.labelFor(next)}
        onDone={() => {
          this.reading.setPlanSlot(plan.id, slot, true);
          this.planFocus = { planId: plan.id, day: day.number, chapter };
          if (next !== null) {
            this.goTo(next);
            return;
          }
          const after = this.reading.progressFor(plan.id);
          const finishedDay = after !== null && after.isDayRead(day);
          if (!finishedDay) {
            // Everything else in the day is in a book this translation
            // lacks; the plan page says so.
            this.notifyListeners();
            return;
          }
          showSnackBar(
            after.isComplete ? `You finished ${plan.name}. Well done.` : `Day ${day.number} done. That’s today’s reading.`,
            { action: { label: 'Plans', onPressed: () => void this.openPlans() } },
          );
          this.notifyListeners();
        }}
        onUndo={() => this.reading.setPlanSlot(plan.id, slot, false)}
        onNext={next === null ? null : () => this.goTo(next)}
      />
    );
    if (pretest === undefined || pretest.before === null) return card;
    const After = PosttestCard ?? PosttestCardStandIn;
    return (
      <>
        <After
          questions={pretest.questions.length}
          guessed={pretest.before}
          answered={pretest.after}
          onAnswer={() => void this.runPretest(pretest, false)}
        />
        {card}
      </>
    );
  }

  readonly openDisplay = (): void => {
    void showDisplaySheet({ settings: this.settings, current: this.bible.translation });
  };

  /** Holding a verse starts a selection, or adds to the one under way. */
  readonly onVerseLongPress = (verse: number): void => {
    navigator.vibrate?.(1);
    if (this.selectionPage !== this.page) this.selected.clear();
    this.selectionPage = this.page;
    this.selected.add(verse);
    this.notifyListeners();
  };

  /** Runs a selection action on one verse, from the verse's own sheet. */
  private startWith(verse: number, action: () => Promise<void>): void {
    this.selected.clear();
    this.selected.add(verse);
    this.selectionPage = this.page;
    this.notifyListeners();
    void action();
  }

  private toggleSelected(verse: number): void {
    if (!this.selected.delete(verse)) this.selected.add(verse);
    if (this.selected.size === 0) this.selectionPage = null;
    this.notifyListeners();
  }

  readonly clearSelection = (): void => {
    if (!this.selecting) return;
    this.selected.clear();
    this.selectionPage = null;
    this.notifyListeners();
  };

  get selectionCitation(): string {
    return VerseSelection.citation(this.current, this.selected);
  }

  get selectionQuotation(): string {
    return VerseSelection.quotation({
      chapter: this.currentChapter,
      reference: this.current,
      verses: this.selected,
      translation: this.bible.translation.abbreviation,
    });
  }

  readonly copySelection = async (): Promise<void> => {
    const citation = this.selectionCitation;
    await copyText(this.selectionQuotation);
    if (this.disposedNow) return;
    this.clearSelection();
    showSnackBar(`Copied ${citation}`);
  };

  readonly shareSelection = async (): Promise<void> => {
    const params: ShareParams = { text: this.selectionQuotation, subject: this.selectionCitation };
    this.clearSelection();
    try {
      await VerseSharing.share(params);
    } catch (error) {
      if (this.disposedNow) return;
      showSnackBar(`Could not share: ${error}`);
    }
  };

  readonly shareSelectionAsImage = async (): Promise<void> => {
    const text = VerseSelection.text(this.currentChapter, this.selected);
    const citation = this.selectionCitation;
    if (text.length === 0) return;
    await showVerseImageSheet({ text, citation, translation: this.bible.translation.name });
    this.clearSelection();
  };

  readonly highlightSelection = async (): Promise<void> => {
    const verses = [...this.selected];
    const chapter = this.current;
    const chosen = await openSheet<number>(<HighlightSheet title={`Highlight ${VerseSelection.citation(chapter, verses)}`} />, {
      name: 'highlight',
    });
    if (chosen === undefined || this.disposedNow) return;
    for (const verse of verses) {
      this.reading.setHighlight(chapter.withVerse(verse), chosen < 0 ? null : chosen);
    }
    this.clearSelection();
  };

  readonly onVerseTap = (verse: number): void => {
    if (this.selecting) {
      this.toggleSelected(verse);
      return;
    }
    const reference = this.current.withVerse(verse);
    const chapter = this.currentChapter;
    void openSheet(
      <VerseSheet
        reference={reference}
        text={chapter.verseText(verse)}
        // Matthew 17:21 and the others the critical texts leave out are
        // numbered in the tradition and absent from the text. Saying so
        // beats an empty sheet with no explanation.
        omitted={chapter.isOmitted(verse)}
        reading={this.reading}
        crossReferences={this.references?.forVerse(reference) ?? []}
        onCrossReferences={() => void this.openCrossReferences(reference)}
        originalWords={this.originalLanguages?.wordsFor(reference) ?? []}
        onOriginal={() => void this.openOriginal(reference)}
        onSelect={() => this.onVerseLongPress(verse)}
        onListen={this.canListen ? () => this.listen(reference) : null}
        onShare={() => this.startWith(verse, this.shareSelection)}
        onImage={() => this.startWith(verse, this.shareSelectionAsImage)}
      />,
      { name: 'verse' },
    );
  };

  /**
   * The translation's own cross-references, where its file brought them.
   * Rebuilt whenever the translation changes.
   */
  private ownXrefs: CrossReferences | null = null;
  private ownXrefsFor: string | null = null;

  /**
   * The cross-references to use: the translation's own where it has them,
   * the bundled English set where its numbering allows, and none at all
   * otherwise.
   */
  private get references(): CrossReferences | null {
    const id = this.bible.translation.id;
    if (this.ownXrefsFor !== id) {
      this.ownXrefsFor = id;
      const chunk = this.bible.extras.get(CrossReferences.chunkTag);
      this.ownXrefs = chunk === undefined ? null : CrossReferences.fromChunk(chunk);
    }
    return this.ownXrefs ?? (this.anchored ? this.xrefs : null);
  }

  /**
   * Whether this translation numbers its verses the way the bundled
   * cross-references and original-language layer do.
   *
   * Both are anchored to one numbering. Against a Bible that numbers
   * differently they would not fail — they would land on the wrong verse,
   * confidently — so where an import has been measured and does not
   * match, they are not offered. A translation that never said gets the
   * benefit of the doubt, which is every file written before this was
   * checked; and a reader who wants them regardless can say so in
   * Settings, which is the one judgement the app is in no position to
   * make for them.
   */
  private get anchored(): boolean {
    return this.settings.offersVerseKeyedLayers(this.bible.translation);
  }

  /**
   * The translation's own Hebrew and Greek, where its file brought them.
   * Unpacked in its own time, so it appears once it is ready.
   */
  private ownOriginals: Originals | null = null;
  private ownOriginalsFor: string | null = null;

  /**
   * Starts reading a translation's own layer, where its file brought one.
   *
   * Eagerly, when the translation changes, rather than when a verse is
   * first tapped: unpacking is measured in megabytes, and a verse sheet
   * already on screen does not gain the Hebrew when it arrives — it was
   * built with what there was.
   */
  private loadOwnOriginals(): void {
    const id = this.bible.translation.id;
    if (this.ownOriginalsFor === id) return;
    this.ownOriginalsFor = id;
    this.ownOriginals = null;
    const chunk = this.bible.extras.get(Originals.chunkTag);
    if (chunk === undefined) return;
    void Originals.fromChunk(chunk).then((own) => {
      // The reader may have moved on to another translation while those
      // megabytes were being unpacked.
      if (this.disposedNow || this.ownOriginalsFor !== id || own === null) return;
      this.ownOriginals = own;
      this.notifyListeners();
    });
  }

  /**
   * The original-language layer to use: the translation's own where its
   * file carries one, the bundled layer where its numbering allows, and
   * none at all otherwise.
   */
  private get originalLanguages(): Originals | null {
    return this.ownOriginals ?? (this.anchored ? this.originals : null);
  }

  /**
   * The Hebrew or Greek of a verse, and from there its dictionary entry
   * and everywhere else the word is used.
   */
  private async openOriginal(reference: Reference): Promise<void> {
    const originals = this.originalLanguages;
    if (originals === null) return;
    const words = originals.wordsFor(reference);
    if (words.length === 0) return;
    const verse = reference.verse;
    const wanted = await showOriginal({
      reference,
      english: verse === null ? '' : this.currentChapter.verseText(verse),
      words,
      originals,
    });
    if (wanted === undefined || this.disposedNow) return;
    await this.openConcordance(wanted);
  }

  /** Every verse a Strong's number occurs in; choosing one goes there. */
  private async openConcordance(number: StrongsNumber): Promise<void> {
    const originals = this.originalLanguages;
    if (originals === null) return;
    const chosen = await showConcordance({ number, originals, bible: this.bible });
    if (chosen === undefined || this.disposedNow) return;
    if (this.bible.bookByCode(chosen.bookCode) === undefined) return;
    this.goTo(chosen);
  }

  /**
   * Opens the cross-references of a verse, and goes wherever one of them
   * leads.
   */
  private async openCrossReferences(reference: Reference): Promise<void> {
    const anchors: XrefAnchor[] = this.references?.forVerse(reference) ?? [];
    if (anchors.length === 0) return;
    const chosen = await showCrossReferences({ reference, anchors, bible: this.bible });
    if (chosen === undefined || this.disposedNow) return;
    if (this.bible.bookByCode(chosen.bookCode) === undefined) return;
    this.goTo(chosen);
  }

  readonly onNoteTap = (index: number): void => {
    const notes = this.currentChapter.notes;
    if (index < 0 || index >= notes.length) return;
    void openSheet(
      <NoteSheet
        title={`Note on ${this.current.label}`}
        text={notes[index]}
        matcher={this.matcher}
        onReference={(reference) => this.goTo(reference)}
      />,
      { name: 'note' },
    );
  };

  /**
   * Opens a feature by name: the tutorial's "Try it", a home-screen
   * shortcut, a notification's link.
   */
  readonly openFeature = (feature: Feature): boolean => {
    switch (feature) {
      case 'navigator':
        void this.openNavigator();
        return true;
      case 'listen':
        if (this.canListen && this.library.comparison === null) this.listenToChapter(this.current);
        else showSnackBar('This browser cannot read aloud.');
        return true;
      case 'library':
        void this.openLibrary(2);
        return true;
      case 'learn':
        void this.openLibrary(0);
        return true;
      case 'plans':
        void this.openPlans();
        return true;
      case 'search':
        void this.openSearch();
        return true;
      case 'settings':
        void this.openSettings();
        return true;
      case 'friends':
        void this.openSocial('feed');
        return true;
      case 'account':
        void this.openSocial('account');
        return true;
      case 'install':
        void historySettled().then(() => showInstallGuide());
        return true;
      default:
        return false;
    }
  };
}

/** The main reading surface: one swipeable page per chapter. */
export function ReaderScreen() {
  const scope = useAppScope();
  const controller = useMemo(() => new ReaderController(scope), [scope]);
  const { settings, reading, library } = controller;
  useNotifier(controller, settings, reading, library);
  // The system going dark or light repaints the page; the tints here are
  // worked out from the palette, so they are worked out again.
  useMediaQuery('(prefers-color-scheme: dark)');
  controller.sync();

  useEffect(() => {
    controller.mount();
    return () => controller.dispose();
  }, [controller]);

  useEffect(() => registerFeatureOpener(controller.openFeature), [controller]);
  useEffect(() => registerReaderGoTo(controller.goToFromScreen), [controller]);

  // The reading face arrives a moment after the first frame; what was
  // measured in its stand-in is measured again.
  useEffect(() => {
    let live = true;
    void document.fonts?.ready.then(() => {
      if (live) controller.notifyListeners();
    });
    return () => {
      live = false;
    };
  }, [controller]);

  // The keyboard, while nothing is open over the text.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return;
      if (!overlays.isEmpty) return;
      const target = event.target as HTMLElement | null;
      if (target !== null && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
      switch (event.key) {
        case 'ArrowRight':
        case 'PageDown':
          controller.step(1);
          break;
        case 'ArrowLeft':
        case 'PageUp':
          controller.step(-1);
          break;
        case 'g':
        case 'G':
          void controller.openNavigator();
          break;
        case '/':
          void controller.openSearch();
          break;
        case 'p':
        case 'P':
          void controller.openPlans();
          break;
        case 'Escape':
          controller.clearSelection();
          return;
        default:
          return;
      }
      event.preventDefault();
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [controller]);

  useBackEndsSelection(controller.selecting, controller.clearSelection);

  const pager = useRef<PagerHandle | null>(null);
  useEffect(() => {
    controller.pager = pager.current;
    return () => {
      controller.pager = null;
    };
  });

  const scheme = currentScheme();
  const style = ScriptureStyle.of(settings);
  const palette = highlights(scheme.brightness);
  const comparison = library.comparison;
  const index = controller.index;
  const shown = index[Math.min(Math.max(controller.page + controller.peek, 0), index.length - 1)] ?? controller.current;
  const shownBook = controller.bible.bookByCode(shown.bookCode);
  const voice = controller.readAloud;

  const pageKey = (page: number): string => `${index[page].bookCode}/${index[page].chapter}`;

  const renderPage = (page: number): VNode => {
    const reference = index[page];
    const book = controller.bible.bookByCode(reference.bookCode)!;
    const chapter = book.chapter(reference.chapter) ?? book.chapters[0];
    const tints = new Map<number, string>();
    for (const [verse, colour] of reading.highlightsIn(book.code, chapter.number)) {
      tints.set(verse, tintLayer(palette[colour % ReadingStore.paletteSize]));
    }
    return (
      <ChapterPage
        key={`${reference.bookCode}/${reference.chapter}/${comparison?.translation.id ?? ''}`}
        book={book}
        chapter={chapter}
        direction={controller.bible.translation.direction}
        style={style}
        highlights={controller.withSelection(page, tints)}
        flagged={reading.flaggedVersesIn(book.code, chapter.number)}
        matcher={controller.matcher}
        onReferenceTap={controller.goTo}
        intros={controller.intros}
        atlas={controller.atlasData}
        comparison={comparison?.bookByCode(book.code)?.chapter(chapter.number) ?? null}
        comparisonLabel={comparison?.translation.abbreviation ?? ''}
        primaryLabel={controller.bible.translation.abbreviation}
        scrollToVerse={page === controller.pendingPage ? controller.pendingVerse : null}
        jumpToken={controller.jumpToken}
        onVerseTap={controller.onVerseTap}
        onVerseLongPress={controller.onVerseLongPress}
        onNoteTap={controller.onNoteTap}
        onTopVerseChanged={(verse) => {
          if (page !== controller.page) return;
          void reading.savePosition(new Reference(book.code, chapter.number, verse));
        }}
        onStep={controller.step}
        planCard={controller.planCardFor(reference)}
        pretestCard={controller.pretestCardFor(reference)}
        onListen={controller.canListen && comparison === null ? () => controller.listenToChapter(reference) : null}
        listenLabel={controller.listenLabel(reference)}
        speakingVerse={controller.speakingVerseOn(reference)}
        hasPrevious={page > 0}
        hasNext={page < index.length - 1}
      />
    );
  };

  return (
    <Screen
      class="ow-reader"
      bodyClass="ow-reader__body"
      appBar={
        <AppBar
          class="ow-reader__bar"
          leading="none"
          title={
            <ReferenceButton
              label={`${shownBook?.name ?? shown.bookName} ${shown.chapter}`}
              badge={comparison?.translation.abbreviation ?? null}
              onTap={() => void controller.openNavigator()}
            />
          }
          actions={
            <>
              <IconButton icon="search" label="Search (/)" onClick={() => void controller.openSearch()} />
              {/* A dot while today's reading in a plan is still to do;
                  nothing louder than that. The theme's colour, not the
                  error red a badge defaults to: a reading waiting is not
                  a fault. */}
              <Dotted show={reading.hasPlanReadingDue}>
                <IconButton icon="event_note" label="Reading plans (P)" onClick={() => void controller.openPlans()} />
              </Dotted>
              {/* The same dot while a verse being learnt is due. */}
              <Dotted show={reading.hasMemoryDue}>
                <IconButton icon="school" label="Learn, and what you have saved" onClick={() => void controller.openLibrary()} />
              </Dotted>
              <IconButton icon="group" label="Friends" onClick={() => void controller.openSocial('feed')} />
              <IconButton icon="text_fields" label="Display" onClick={controller.openDisplay} />
              <IconButton icon="settings" label="Settings" onClick={() => void controller.openSettings()} />
            </>
          }
        />
      }
      bottom={
        controller.selecting ? (
          <SelectionBar
            citation={controller.selectionCitation}
            count={controller.selected.size}
            onClose={controller.clearSelection}
            onCopy={() => void controller.copySelection()}
            onShare={() => void controller.shareSelection()}
            onImage={() => void controller.shareSelectionAsImage()}
            onHighlight={() => void controller.highlightSelection()}
          />
        ) : voice !== null && voice.isActive ? (
          <PlayerBar voice={voice} rate={settings.speechRate} onSettings={() => void controller.openVoiceSettings()} />
        ) : null
      }
    >
      {index.length > 0 && (
        <ChapterPager
          page={controller.page}
          count={index.length}
          pageKey={pageKey}
          renderPage={renderPage}
          onPageChanged={controller.onPageChanged}
          onPeek={controller.onPeek}
          handle={pager}
        />
      )}
    </Screen>
  );
}

/**
 * Back ends a selection before it leaves anything — Flutter's `PopScope`.
 *
 * The reader is the bottom of the app, so there is nothing for the back
 * button to go back to but out. While verses are selected the reader
 * keeps one entry of its own in the browser's history: going back lands
 * on what was there before it, which is the cue to let the selection go;
 * and a selection ended any other way takes its entry away again.
 */
function useBackEndsSelection(selecting: boolean, clear: () => void): void {
  useEffect(() => {
    if (!selecting || typeof history === 'undefined') return;
    let ended = false;
    let pushed = false;
    const mine = () => (history.state as { owSelection?: boolean } | null)?.owSelection === true;

    // After whatever closed to start it — the verse sheet's "Select more".
    void historySettled().then(() => {
      if (ended) return;
      history.pushState({ owDepth: overlays.live.length, owSelection: true }, '');
      pushed = true;
    });

    const onPop = () => {
      // Back past the selection's own entry, with nothing open over it.
      if (pushed && !mine() && overlays.isEmpty) clear();
    };
    addEventListener('popstate', onPop);

    return () => {
      ended = true;
      removeEventListener('popstate', onPop);
      if (!pushed) return;
      void historySettled().then(() => {
        if (mine()) history.back();
      });
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selecting]);
}

/** An app-bar button with a small dot on it while something is waiting. */
function Dotted({ show, children }: { show: boolean; children: ComponentChildren }) {
  return (
    <span class="ow-reader__dotted">
      {children}
      {show && <span class="ow-reader__dot" />}
    </span>
  );
}

/**
 * The pages: one chapter across, the whole Bible long.
 *
 * Only three are ever in the page — the chapter being read and the one on
 * either side — in a row that snaps. When a swipe settles on a neighbour
 * it becomes the middle one, the row is re-centred under it, and the page
 * that fell off the far side is let go; so the reader can swipe from
 * Genesis to Revelation without the document ever holding more than three
 * chapters.
 */
function ChapterPager({
  page,
  count,
  pageKey,
  renderPage,
  onPageChanged,
  onPeek,
  handle,
}: {
  page: number;
  count: number;
  pageKey: (page: number) => string;
  renderPage: (page: number) => VNode;
  onPageChanged: (page: number) => void;
  onPeek: (delta: number) => void;
  handle: RefObject<PagerHandle | null>;
}) {
  const element = useRef<HTMLDivElement>(null);
  const latest = useRef({ page, count, onPageChanged, onPeek });
  latest.current = { page, count, onPageChanged, onPeek };
  const state = useRef({
    settle: 0 as ReturnType<typeof setTimeout> | 0,
    fallback: 0 as ReturnType<typeof setTimeout> | 0,
    touching: false,
  });

  const pages: number[] = [];
  if (page > 0) pages.push(page - 1);
  pages.push(page);
  if (page < count - 1) pages.push(page + 1);
  const keys = pages.map(pageKey).join('|');

  /** Which of the pages in the row is the one being read. */
  const centre = () => (latest.current.page > 0 ? 1 : 0);

  const place = () => {
    const row = element.current;
    if (row === null) return;
    const left = centre() * row.clientWidth;
    if (Math.abs(row.scrollLeft - left) > 0.5) row.scrollLeft = left;
  };

  // The row is put back under the chapter being read whenever that
  // changes — before the browser paints, so the turn is never seen.
  useLayoutEffect(place, [page, keys]);

  useEffect(() => {
    const row = element.current;
    if (row === null) return;
    const s = state.current;

    /** Where the row has come to rest, if it has: the page under it. */
    const check = () => {
      s.settle = 0;
      if (s.touching || row.clientWidth === 0) return;
      const slot = Math.round(row.scrollLeft / row.clientWidth);
      if (Math.abs(row.scrollLeft - slot * row.clientWidth) > 1.5) return;
      const delta = slot - centre();
      if (delta === 0) return;
      // Wherever a slide was headed, this is where the pages are now.
      if (s.fallback !== 0) clearTimeout(s.fallback);
      s.fallback = 0;
      latest.current.onPageChanged(latest.current.page + delta);
    };
    const onScroll = () => {
      if (row.clientWidth === 0) return;
      const slot = Math.round(row.scrollLeft / row.clientWidth);
      latest.current.onPeek(slot - centre());
      if (s.settle !== 0) clearTimeout(s.settle);
      s.settle = setTimeout(check, 90);
    };
    const onScrollEnd = () => {
      if (s.settle !== 0) clearTimeout(s.settle);
      check();
    };
    const onTouchStart = () => {
      s.touching = true;
      if (s.fallback !== 0) clearTimeout(s.fallback);
      s.fallback = 0;
    };
    const onTouchEnd = (event: TouchEvent) => {
      s.touching = event.touches.length > 0;
      if (!s.touching) {
        if (s.settle !== 0) clearTimeout(s.settle);
        s.settle = setTimeout(check, 90);
      }
    };
    row.addEventListener('scroll', onScroll, { passive: true });
    row.addEventListener('scrollend', onScrollEnd);
    row.addEventListener('touchstart', onTouchStart, { passive: true });
    row.addEventListener('touchend', onTouchEnd);
    row.addEventListener('touchcancel', onTouchEnd);
    // A window made wider or narrower moves every page; the row follows.
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(() => place());
    observer?.observe(row);

    handle.current = {
      animateToPage(target: number) {
        const delta = target - latest.current.page;
        if (Math.abs(delta) !== 1 || row.clientWidth === 0) {
          latest.current.onPageChanged(target);
          return;
        }
        row.scrollTo({ left: (centre() + delta) * row.clientWidth, behavior: 'smooth' });
        // A slide that never arrives — the tab hidden, the scroll
        // interrupted — still ends on the page that was asked for.
        if (s.fallback !== 0) clearTimeout(s.fallback);
        s.fallback = setTimeout(() => {
          s.fallback = 0;
          if (latest.current.page !== target) latest.current.onPageChanged(target);
        }, 1200);
      },
    };

    return () => {
      row.removeEventListener('scroll', onScroll);
      row.removeEventListener('scrollend', onScrollEnd);
      row.removeEventListener('touchstart', onTouchStart);
      row.removeEventListener('touchend', onTouchEnd);
      row.removeEventListener('touchcancel', onTouchEnd);
      observer?.disconnect();
      if (s.settle !== 0) clearTimeout(s.settle);
      if (s.fallback !== 0) clearTimeout(s.fallback);
      handle.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    // The pages turn the way the device reads, whatever the translation.
    <div class="ow-pager" ref={element} dir="ltr">
      {pages.map((index) => (
        <div class="ow-pager__page" key={pageKey(index)} aria-hidden={index === page ? undefined : true}>
          {renderPage(index)}
        </div>
      ))}
    </div>
  );
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

const easeOutCubic = (t: number): number => 1 - Math.pow(1 - t, 3);
const easeInOutCubic = (t: number): number => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/**
 * Twice, because once reads as a trick of the eye and three times is
 * fussing. The whole point is to be noticed and then to be over. The
 * pulse itself is in scriptureText.css; this is how long it runs.
 */
const flashLength = 1100;

interface ChapterPageProps {
  book: Book;
  chapter: Chapter;

  /**
   * Which way this translation runs. Everything shipped here runs
   * left-to-right; an imported Hebrew or Arabic Bible does not, and the
   * file says so.
   */
  direction: ReadingDirection;

  style: ScriptureStyle;
  highlights: ReadonlyMap<number, string>;
  flagged: ReadonlySet<number>;
  matcher: ReferenceMatcher | null;
  onReferenceTap: (reference: Reference) => void;
  intros: BookIntros | null;

  /** Read once the atlas asset is decoded; null until then. */
  atlas: AtlasData | null;

  /** The same chapter in a second translation, when comparing. */
  comparison: Chapter | null;
  comparisonLabel: string;
  primaryLabel: string;

  scrollToVerse: number | null;

  /** Changes with every jump, so the same verse can be gone to again. */
  jumpToken: number;

  onVerseTap: (verse: number) => void;
  onVerseLongPress?: (verse: number) => void;
  onNoteTap: (index: number) => void;
  onTopVerseChanged: (verse: number) => void;
  onStep: (delta: number) => void;
  hasPrevious: boolean;
  hasNext: boolean;

  /**
   * Where the chapter is part of a reading plan, the card that ticks it
   * off; it sits where the reader finishes the chapter.
   */
  planCard: VNode | null;

  /**
   * Shown under the chapter's heading: a plan chapter's questions to
   * guess at before reading.
   */
  pretestCard: VNode | null;

  /** Starts reading the chapter aloud, where the platform can. */
  onListen: (() => void) | null;

  /** LISTEN, or PAUSE or RESUME while it is being read or has been begun. */
  listenLabel: string;

  /** The verse being read aloud, which is marked and kept in view. */
  speakingVerse: number | null;
}

/** One chapter, scrollable, with the position-tracking that powers resume. */
function ChapterPage(props: ChapterPageProps) {
  const { book, chapter, style } = props;
  const scroller = useRef<HTMLDivElement>(null);
  const latest = useRef(props);
  latest.current = props;
  const s = useRef({
    debounce: 0 as ReturnType<typeof setTimeout> | 0,
    reportedVerse: 0,
    flashTimer: 0 as ReturnType<typeof setTimeout> | 0,
    animation: 0,
    /** Until when scrolling is the page's own doing rather than the reader's. */
    quietUntil: 0,
    readerScrolled: false,
  }).current;

  const comparing = props.comparison !== null;
  const labelFor = useMemo(() => (verse: number) => chapter.labelFor(verse), [chapter]);
  const gestures = useVerseGestures({ onVerseTap: props.onVerseTap, onVerseLongPress: props.onVerseLongPress });

  /**
   * The mark where `verse` begins, or the nearest one before it. Every
   * verse that begins on the page carries one; a verse folded into
   * another's number does not.
   */
  const anchorFor = (verse: number): Element | null => {
    const root = scroller.current;
    if (root === null) return null;
    const exact = root.querySelector(`[data-vs="${verse}"]`);
    if (exact !== null) return exact;
    let best = 0;
    let found: Element | null = null;
    for (const candidate of root.querySelectorAll('[data-vs]')) {
      const number = Number(candidate.getAttribute('data-vs'));
      if (number < verse && number > best) {
        best = number;
        found = candidate;
      }
    }
    return found;
  };

  const stopScrolling = () => {
    if (s.animation !== 0) cancelAnimationFrame(s.animation);
    s.animation = 0;
  };

  /**
   * Brings `target` to `alignment` of the way down the page — Flutter's
   * `Scrollable.ensureVisible`. `quiet` keeps the move from being taken
   * for the reader's own scrolling, which would save the place it passes.
   */
  const ensureVisible = (
    target: Element,
    options: { duration: number; curve: (t: number) => number; alignment: number; quiet: boolean },
  ) => {
    const view = scroller.current;
    if (view === null) return;
    const rect = target.getClientRects()[0] ?? target.getBoundingClientRect();
    const frame = view.getBoundingClientRect();
    const wanted = view.scrollTop + (rect.top - frame.top) - (view.clientHeight - rect.height) * options.alignment;
    const to = clamp(wanted, 0, Math.max(0, view.scrollHeight - view.clientHeight));
    const from = view.scrollTop;
    stopScrolling();
    const hush = () => {
      if (options.quiet) s.quietUntil = performance.now() + 200;
    };
    if (options.duration <= 0 || Math.abs(to - from) < 1) {
      hush();
      view.scrollTop = to;
      return;
    }
    const started = performance.now();
    const frameStep = (now: number) => {
      const t = Math.min(1, (now - started) / options.duration);
      hush();
      view.scrollTop = from + (to - from) * options.curve(t);
      s.animation = t < 1 ? requestAnimationFrame(frameStep) : 0;
    };
    s.animation = requestAnimationFrame(frameStep);
  };

  const clearFlash = () => {
    if (s.flashTimer !== 0) clearTimeout(s.flashTimer);
    s.flashTimer = 0;
    scroller.current?.querySelectorAll('[data-flash]').forEach((marked) => marked.removeAttribute('data-flash'));
  };

  /**
   * Marks a verse the reader was sent to, so they do not have to hunt for
   * it.
   *
   * Scrolling a verse into view is not the same as showing it: in prose a
   * verse is a sentence or two in the middle of a paragraph, with nothing
   * but a small number to find it by. This puts a colour behind it and
   * takes it away again, twice, and then the page is as it was.
   *
   * Only the verse's own runs are touched. Animating the whole chapter
   * would redraw every paragraph of it to colour one sentence.
   */
  const pointOut = (verse: number) => {
    const root = scroller.current;
    if (root === null) return;
    clearFlash();
    const marked = root.querySelectorAll(`.ow-verse[data-verse="${verse}"], .ow-compare__row[data-vs="${verse}"]`);
    // Read back, so a verse pointed out twice running starts over.
    void root.offsetWidth;
    marked.forEach((element) => element.setAttribute('data-flash', ''));
    s.flashTimer = setTimeout(clearFlash, flashLength + 50);
  };

  /**
   * Scrolls the chapter to a verse. Used by the pending-jump machinery and
   * by the map, where tapping a reference should land on the words.
   */
  const scrollToVerse = (verse: number | null, options: { instant?: boolean } = {}) => {
    if (verse === null || verse < 1) return;
    if (options.instant !== true) pointOut(verse);
    // Verse 1 is already at the top of the chapter; there is nowhere to
    // scroll to, which is not a reason to leave it unmarked.
    if (verse === 1) return;
    const target = anchorFor(verse);
    if (target === null) return;
    ensureVisible(target, {
      duration: options.instant === true ? 0 : 420,
      curve: easeOutCubic,
      alignment: 0.08,
      quiet: true,
    });
  };

  /**
   * Follows the voice down the page, gently: the verse being read is
   * brought a third of the way down, not snapped to the top.
   */
  const keepInView = (verse: number) => {
    const target = anchorFor(verse);
    if (target === null) return;
    ensureVisible(target, { duration: reduceMotion() ? 0 : 500, curve: easeInOutCubic, alignment: 0.3, quiet: false });
  };

  /**
   * Finds the verse nearest the top of the viewport so the app can resume
   * exactly where the reader left off, independent of font size.
   */
  const reportTopVerse = () => {
    s.debounce = 0;
    const view = scroller.current;
    if (view === null) return;
    const top = view.getBoundingClientRect().top;
    let best = 0;
    for (const anchor of view.querySelectorAll('[data-vs]')) {
      const rect = anchor.getClientRects()[0];
      if (rect === undefined) continue;
      // In reading order, so the first one below the line ends the search.
      if (rect.top > top + 24) break;
      const verse = Number(anchor.getAttribute('data-vs'));
      if (verse > best) best = verse;
    }
    if (best > 0 && best !== s.reportedVerse) {
      s.reportedVerse = best;
      latest.current.onTopVerseChanged(best);
    }
  };

  const onScroll = () => {
    // The page moving itself to a verse it was sent to is not the reader
    // reading on: the place they were sent to stays the place kept.
    if (performance.now() < s.quietUntil) return;
    s.readerScrolled = true;
    if (s.debounce !== 0) clearTimeout(s.debounce);
    s.debounce = setTimeout(reportTopVerse, 450);
  };

  // The verse the reader was sent to: on arriving, and each time after.
  useEffect(() => {
    let live = true;
    const verse = props.scrollToVerse;
    s.readerScrolled = false;
    scrollToVerse(verse);
    // The reading face may still be on its way; when it lands the lines
    // fall differently, and the verse is found again where it now is.
    if (verse !== null && typeof document !== 'undefined' && document.fonts !== undefined && document.fonts.status !== 'loaded') {
      void document.fonts.ready.then(() => {
        if (live && !s.readerScrolled) scrollToVerse(verse, { instant: true });
      });
    }
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.scrollToVerse, props.jumpToken]);

  useEffect(() => {
    if (props.speakingVerse !== null) keepInView(props.speakingVerse);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.speakingVerse]);

  useEffect(
    () => () => {
      if (s.debounce !== 0) clearTimeout(s.debounce);
      if (s.flashTimer !== 0) clearTimeout(s.flashTimer);
      stopScrolling();
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  /** The highlights with the verse being read aloud laid over them. */
  const highlightsNow = useMemo(() => {
    const verse = props.speakingVerse;
    if (verse === null) return props.highlights;
    const tint = rgba(currentScheme().tertiary, 0.22);
    const out = new Map(props.highlights);
    out.set(verse, tintOver(tint, props.highlights.get(verse)));
    return out;
  }, [props.highlights, props.speakingVerse]);

  /**
   * The places this chapter names, with their verses, once the atlas has
   * been read.
   */
  const places: readonly ChapterPlace[] = props.atlas?.inChapter(book.code, chapter.number) ?? [];

  // The cards are the app talking, not the text, so they keep the
  // device's direction even under a right-to-left translation.
  const deviceDirection = typeof document !== 'undefined' && document.dir === 'rtl' ? 'rtl' : 'ltr';

  const heading = (
    <div class="ow-chapter__heading">
      {/* Wraps rather than runs off a narrow phone: a long book name,
          its places and Listen do not always fit on one line. */}
      <div class="ow-chapter__links">
        {/* Tapping the book's name opens its background note. */}
        <button
          type="button"
          class="ow-chapter__link ow-chapter__link--book m3-interactive"
          onClick={() => showBookSheet(book, { intros: props.intros })}
        >
          <span>{book.name.toUpperCase()}</span>
          <Icon name="info_outlined" size={14} />
        </button>
        {/* Offered only where the chapter names somewhere on the map. */}
        {places.length > 0 && props.atlas !== null && (
          <button
            type="button"
            class="ow-chapter__link m3-interactive"
            onClick={() =>
              showMapSheet({
                data: props.atlas!,
                title: `${book.name} ${chapter.number}`,
                places,
                // A verse tapped on the map is somewhere to read, so the
                // map gets out of the way and the chapter scrolls to it.
                onVerse: (verse) => scrollToVerse(verse),
              })
            }
          >
            <Icon name="map_outlined" size={14} />
            <span>{places.length === 1 ? '1 PLACE' : `${places.length} PLACES`}</span>
          </button>
        )}
        {props.onListen !== null && (
          <button type="button" class="ow-chapter__link m3-interactive" onClick={props.onListen}>
            <Icon
              name={props.listenLabel === 'PAUSE' ? 'pause' : props.listenLabel === 'RESUME' ? 'play_arrow' : 'headphones'}
              size={14}
            />
            <span>{props.listenLabel}</span>
          </button>
        )}
      </div>
      <div class="ow-chapter__title">
        {/* What the translation calls it, where it says: the Psalter
            has psalms, not chapters. */}
        {chapter.label.length > 0 ? chapter.label : book.chapterCount > 1 ? `Chapter ${chapter.number}` : book.name}
      </div>
    </div>
  );

  let body: ComponentChildren;
  if (props.comparison !== null) {
    body = compareBody(props, props.comparison, gestures);
  } else {
    let isFirst = true;
    body = chapter.blocks.map((block, i) => {
      const firstOfBlock = isFirst;
      // A heading, title or stanza break starts a new passage, and the
      // paragraph opening it is set flush like the chapter's first.
      isFirst = !isVerseText(block.style);
      return (
        <ScriptureBlock
          key={i}
          block={block}
          labelFor={labelFor}
          style={style}
          highlights={highlightsNow}
          flagged={props.flagged}
          isFirst={firstOfBlock}
          matcher={props.matcher}
          onReferenceTap={props.onReferenceTap}
          onVerseTap={props.onVerseTap}
          onVerseLongPress={props.onVerseLongPress}
          onNoteTap={props.onNoteTap}
        />
      );
    });
  }

  return (
    // No scrollbar over the text: a page of Scripture is read, not scrubbed,
    // and the browser would draw one down the margin.
    <div
      class="ow-chapter"
      ref={scroller}
      onScroll={onScroll}
      onWheel={stopScrolling}
      onTouchStart={stopScrolling}
      onPointerDown={stopScrolling}
    >
      {/* The page runs the way the translation does. The chrome around
          it keeps following the device, which is the reader's own
          language rather than the text's. */}
      <div
        class={`ow-chapter__column${comparing ? ' ow-chapter__column--compare' : ''}`}
        dir={props.direction === ReadingDirection.rtl ? 'rtl' : 'ltr'}
      >
        {heading}
        {props.pretestCard !== null && <div dir={deviceDirection}>{props.pretestCard}</div>}
        {body}
        {props.planCard !== null && (
          <div class="ow-chapter__plan" dir={deviceDirection}>
            {props.planCard}
          </div>
        )}
        <ChapterFooter hasPrevious={props.hasPrevious} hasNext={props.hasNext} onStep={props.onStep} />
      </div>
    </div>
  );
}

/**
 * Verse-by-verse view of two translations. Wide windows put them in
 * columns; narrow ones stack each pair.
 */
function compareBody(props: ChapterPageProps, other: Chapter, gestures: ReturnType<typeof useVerseGestures>): VNode {
  const chapter = props.chapter;
  const count = chapter.verseCount > other.verseCount ? chapter.verseCount : other.verseCount;
  const rows: VNode[] = [];
  for (let verse = 1; verse <= count; verse++) {
    const mine = chapter.verseText(verse);
    const theirs = other.verseText(verse);
    if (mine.length === 0 && theirs.length === 0) continue;
    const tint = props.highlights.get(verse);
    rows.push(
      <div class="ow-compare__row" key={verse} data-vs={verse}>
        <div
          class="ow-sb ow-compare__cell ow-flashable"
          data-verse={verse}
          style={tint === undefined ? undefined : { backgroundImage: tint }}
        >
          <span class="ow-vn ow-compare__number">{verse}</span>
          {mine.length === 0 ? '—' : mine}
        </div>
        <div class="ow-sb ow-compare__cell ow-compare__cell--other">
          <span class="ow-vn ow-compare__number">{verse}</span>
          {theirs.length === 0 ? '—' : theirs}
        </div>
      </div>,
    );
  }
  return (
    <div class="ow-compare" {...gestures}>
      <div class="ow-compare__labels">
        <span class="ow-compare__chip ow-compare__chip--primary">{props.primaryLabel}</span>
        <span class="ow-compare__chip">{props.comparisonLabel}</span>
      </div>
      {rows}
    </div>
  );
}

/**
 * The end of a chapter that belongs to a plan: one tap marks it read and
 * goes on to the next chapter of the day.
 */
export function PlanChapterCard({
  planName,
  day,
  read,
  nextLabel,
  onDone,
  onUndo,
  onNext,
}: {
  planName: string;
  day: number;
  read: boolean;

  /**
   * The next chapter of the day still to read, or null when this is the
   * last.
   */
  nextLabel: string | null;
  onDone: () => void;
  onUndo: () => void;
  onNext: (() => void) | null;
}) {
  return (
    <div class="ow-plan-card">
      <div class="ow-plan-card__head">
        <Icon name={read ? 'check_circle' : 'event_note'} size={18} />
        <span class="m3-label-large" style="flex:1;min-width:0">
          {planName} · day {day}
        </span>
      </div>
      {!read ? (
        <Button icon="check" class="ow-plan-card__done" onClick={onDone}>
          {nextLabel === null ? `Done — that’s day ${day}` : `Done — next: ${nextLabel}`}
        </Button>
      ) : (
        <div class="ow-plan-card__read">
          <span class="m3-body-large" style="flex:1">
            Read
          </span>
          <TextButton onClick={onUndo}>Undo</TextButton>
          {onNext !== null && <Button onClick={onNext}>Next: {nextLabel}</Button>}
        </div>
      )}
    </div>
  );
}

/**
 * Before a plan chapter is read: a nudge to guess at two of its verses
 * first. Guessing before studying makes the guessed-at material stick,
 * even when the guess is wrong.
 *
 * Stands in for `PretestCard` of `pretestCard.tsx` until that file is
 * there; the words and the shape are the same.
 */
function PretestCardStandIn({ questions, guessed, onGuess }: PretestCardProps) {
  return (
    <div class="ow-pretest-card" style="margin-bottom:20px">
      <Icon name="psychology_alt" />
      <div style="flex:1;min-width:0">
        <div class="m3-title-small">{guessed === null ? 'Guess before you read' : `You guessed ${guessed} of ${questions}`}</div>
        <div class="m3-body-small">
          {guessed === null
            ? `${questions} of this chapter’s verses to finish. A wrong guess still helps the right one stick.`
            : 'Read on; the same questions wait at the end.'}
        </div>
      </div>
      {guessed === null && <TonalButton onClick={onGuess}>Guess</TonalButton>}
    </div>
  );
}

/**
 * After the chapter: the same questions again, and how the two went.
 * Stands in for `PosttestCard` of `pretestCard.tsx` until that file is
 * there.
 */
function PosttestCardStandIn({ questions, guessed, answered, onAnswer }: PosttestCardProps) {
  return (
    <div class="ow-pretest-card" style="margin-bottom:12px">
      <Icon name={answered === null ? 'quiz' : 'check_circle'} />
      <div class="m3-body-medium" style="flex:1;min-width:0">
        {answered === null
          ? `You guessed ${guessed} of ${questions} before reading. Answer again now?`
          : `Before reading, ${guessed} of ${questions}; after, ${answered} of ${questions}.`}
      </div>
      {answered === null && <TonalButton onClick={onAnswer}>Answer</TonalButton>}
    </div>
  );
}

function ChapterFooter({ hasPrevious, hasNext, onStep }: { hasPrevious: boolean; hasNext: boolean; onStep: (delta: number) => void }) {
  return (
    <div class="ow-chapter__footer">
      <TextButton icon="chevron_left" disabled={!hasPrevious} onClick={() => onStep(-1)}>
        Previous
      </TextButton>
      <TextButton class="ow-chapter__next" disabled={!hasNext} onClick={() => onStep(1)}>
        Next
        <Icon name="chevron_right" />
      </TextButton>
    </div>
  );
}

/** The book-and-chapter button in the app bar. */
function ReferenceButton({
  label,
  onTap,
  badge = null,
}: {
  label: string;
  onTap: () => void;

  /** Abbreviation of the translation being compared, when there is one. */
  badge?: string | null;
}) {
  return (
    <button type="button" class="ow-reference-button m3-interactive" onClick={onTap} aria-label={`${label}. Go to another place (G)`}>
      <span class="ow-reference-button__label">{label}</span>
      {badge !== null && <span class="ow-reference-button__badge">{badge}</span>}
      <Icon name="arrow_drop_down" size={20} />
    </button>
  );
}

/** The footnote behind a marker, with any citations in it made tappable. */
function NoteSheet({
  title,
  text,
  matcher,
  onReference,
}: {
  title: string;
  text: string;
  matcher: ReferenceMatcher | null;
  onReference: (reference: Reference) => void;
}) {
  const overlay = useOverlay();
  return (
    <Sheet class="ow-note-sheet">
      <div class="m3-title-medium">{title}</div>
      <div style="margin-top:12px">
        <LinkedText
          text={text}
          class="m3-body-large"
          matcher={matcher}
          onTap={(reference) => {
            overlay.close();
            onReference(reference);
          }}
        />
      </div>
    </Sheet>
  );
}

/** The palette, to colour every verse of a selection at once. Answers the colour, or -1 to remove. */
function HighlightSheet({ title }: { title: string }) {
  const overlay = useOverlay();
  const swatches = [];
  for (let i = 0; i < ReadingStore.paletteSize; i++) {
    swatches.push(<Swatch color={highlightSwatch(i)} name={highlightNames[i]} selected={false} onTap={() => overlay.close(i)} />);
  }
  return (
    <Sheet class="ow-highlight-sheet">
      <div class="m3-title-medium">{title}</div>
      <div class="ow-highlight-sheet__row">
        {swatches}
        <TextButton icon="format_color_reset" onClick={() => overlay.close(-1)}>
          Remove
        </TextButton>
      </div>
    </Sheet>
  );
}

/** Actions for a tapped verse: highlight, bookmark, note, copy. */
function VerseSheet({
  reference,
  text,
  reading,
  crossReferences,
  onCrossReferences,
  originalWords,
  onOriginal,
  onSelect,
  onShare,
  onImage,
  onListen = null,
  omitted = false,
}: {
  reference: Reference;
  text: string;

  /** Whether this translation leaves the verse out on purpose. */
  omitted?: boolean;
  reading: ReadingStore;
  crossReferences: readonly XrefAnchor[];
  onCrossReferences: () => void;
  originalWords: readonly { strongs: StrongsNumber | null }[];
  onOriginal: () => void;

  /** Starts a selection with this verse, to add more to it. */
  onSelect: () => void;
  onShare: () => void;
  onImage: () => void;

  /** Reads aloud from this verse on, where the platform can. */
  onListen?: (() => void) | null;
}) {
  const overlay = useOverlay();
  useNotifier(reading);
  const mark = reading.markFor(reference);

  let passageCount = 0;
  for (const anchor of crossReferences) passageCount += anchor.ranges.length;

  const editNote = async () => {
    const note = await openDialog<string>(<NoteDialog title={reference.label} initial={reading.markFor(reference)?.note ?? ''} />);
    if (note === undefined) return;
    reading.setNote(reference, note);
  };

  const swatches = [];
  for (let i = 0; i < ReadingStore.paletteSize; i++) {
    swatches.push(
      <Swatch
        color={highlightSwatch(i)}
        name={highlightNames[i]}
        selected={mark?.colorIndex === i}
        onTap={() => reading.setHighlight(reference, mark?.colorIndex === i ? null : i)}
      />,
    );
  }

  const bookmarked = mark?.bookmarked ?? false;
  const hasNote = mark?.hasNote ?? false;
  const memorising = reading.isMemorising(reference);
  const absent = omitted && text.length === 0;

  return (
    <Sheet class="ow-verse-sheet">
      <div class="m3-title-medium">{reference.label}</div>
      <div class={`ow-verse-sheet__text${absent ? ' ow-verse-sheet__text--absent' : ''}`}>
        {absent
          ? 'This translation does not include this verse. It is numbered in the tradition and absent from the manuscripts this edition follows.'
          : text}
      </div>
      <div class="ow-verse-sheet__swatches">
        {swatches}
        {(mark?.highlighted ?? false) && (
          <IconButton icon="format_color_reset" label="Remove highlight" onClick={() => reading.setHighlight(reference, null)} />
        )}
      </div>
      <div class="ow-verse-sheet__actions">
        <TonalButton
          icon={bookmarked ? 'bookmark_remove' : 'bookmark_add'}
          onClick={() => {
            const added = reading.toggleBookmark(reference);
            showSnackBar(added ? `Bookmarked ${reference.label}` : 'Bookmark removed');
          }}
        >
          {bookmarked ? 'Bookmarked' : 'Bookmark'}
        </TonalButton>
        {originalWords.length > 0 && (
          <TonalButton
            icon="translate"
            onClick={() => {
              overlay.close();
              onOriginal();
            }}
          >
            {originalWords.some((word) => word.strongs?.isHebrew ?? false) ? 'Hebrew' : 'Greek'}
          </TonalButton>
        )}
        {crossReferences.length > 0 && (
          <TonalButton
            icon="hub_outlined"
            onClick={() => {
              overlay.close();
              onCrossReferences();
            }}
          >
            {passageCount} cross-references
          </TonalButton>
        )}
        {text.length > 0 && (
          <TonalButton
            icon={memorising ? 'psychology' : 'psychology_outlined'}
            onClick={() => {
              const added = reading.toggleMemorise(reference);
              showSnackBar(
                added
                  ? `Memorising ${reference.label}: practise it under Learn in your library`
                  : `No longer memorising ${reference.label}`,
              );
            }}
          >
            {memorising ? 'Memorising' : 'Memorise'}
          </TonalButton>
        )}
        <TonalButton icon={hasNote ? 'edit_note' : 'note_add_outlined'} onClick={() => void editNote()}>
          {hasNote ? 'Note' : 'Add note'}
        </TonalButton>
        <TonalButton
          icon="content_copy"
          onClick={async () => {
            await copyText(`${reference.label} — ${text}`);
            overlay.close();
            showSnackBar('Verse copied');
          }}
        >
          Copy
        </TonalButton>
        {text.length > 0 && onListen !== null && (
          <TonalButton
            icon="headphones"
            onClick={() => {
              overlay.close();
              onListen();
            }}
          >
            Listen from here
          </TonalButton>
        )}
        {text.length > 0 && (
          <>
            <TonalButton
              icon="share"
              onClick={() => {
                overlay.close();
                onShare();
              }}
            >
              Share
            </TonalButton>
            <TonalButton
              icon="image_outlined"
              onClick={() => {
                overlay.close();
                onImage();
              }}
            >
              Image
            </TonalButton>
          </>
        )}
        <TonalButton
          icon="checklist"
          onClick={() => {
            overlay.close();
            onSelect();
          }}
        >
          Select more
        </TonalButton>
      </div>
      {hasNote && <div class="ow-verse-sheet__note m3-body-medium">{mark!.note}</div>}
    </Sheet>
  );
}

/** The reader's own note on a verse. Answers the text, or nothing if cancelled. */
function NoteDialog({ title, initial }: { title: string; initial: string }) {
  const overlay = useOverlay();
  const [text, setText] = useState(initial);
  return (
    <AlertDialog
      title={title}
      actions={
        <>
          <DialogAction>Cancel</DialogAction>
          <Button onClick={() => overlay.close(text)}>Save</Button>
        </>
      }
    >
      <TextField value={text} onInput={setText} placeholder="Your note" multiline rows={3} autoFocus />
    </AlertDialog>
  );
}

/** "1×", "1.25×", "1.5×". */
export function rateLabel(rate: number): string {
  return `${rate.toFixed(2).replace(/\.?0+$/, '')}×`;
}

/**
 * Reading aloud, along the bottom of the reader while it goes on: where
 * it has got to, and the few controls a listener needs.
 */
function PlayerBar({ voice, rate, onSettings }: { voice: ReadAloud; rate: number; onSettings: () => void }) {
  // The voice's own state as well as the reading's: the first Listen
  // fetches sixty megabytes and loads a model before a word is heard, and
  // a bar that said "Reading aloud" through all of it would look stuck.
  useNotifier(neuralVoices);
  const current = voice.current;
  const where =
    current === null ? '' : current.verse === null ? ReadAloud.announcement(current).replaceAll('.', '') : current.label;
  const download = neuralVoices.progress;
  const waiting = voice.isWaitingForVoice;
  const fetched =
    download !== null && download.total > 0 ? Math.min(1, download.received / download.total) : download !== null ? 0 : null;
  const status = !voice.isPlaying
    ? 'Paused'
    : waiting && fetched !== null
      ? `Getting the voice · ${Math.round(fetched * 100)}% · once only`
      : waiting
        ? 'Preparing the voice…'
        : `Reading aloud · ${rateLabel(rate)}`;
  return (
    <div class="ow-reader-bar">
      {waiting && (
        <div class="ow-reader-bar__progress">
          <LinearProgress value={fetched ?? undefined} />
        </div>
      )}
      <IconButton icon="close" label="Stop reading aloud" onClick={() => voice.stop()} />
      <div class="ow-reader-bar__text">
        <div class="m3-title-small ow-truncate">{where}</div>
        <div class="m3-label-small m3-on-surface-variant ow-truncate" role="status">
          {status}
        </div>
      </div>
      <IconButton icon="skip_previous" label="Previous verse" onClick={() => voice.skip(-1)} />
      <IconButton
        variant="filled"
        icon={voice.isPlaying ? 'pause' : 'play_arrow'}
        label={voice.isPlaying ? 'Pause' : 'Resume'}
        onClick={() => (voice.isPlaying ? voice.pause() : voice.resume())}
      />
      <IconButton icon="skip_next" label="Next verse" onClick={() => voice.skip(1)} />
      <IconButton icon="tune" label="Speed and voice" onClick={onSettings} />
    </div>
  );
}

/** How fast, and in whose voice. */
function VoiceSheet({ settings, engine, language }: { settings: Settings; engine: SpeechEngine; language: string }) {
  useNotifier(settings);
  const voices = useAsync<SpeechVoice[]>(() => engine.voices(language).catch(() => []), [engine, language]);
  const list = voices.value ?? [];
  // A voice kept from an earlier version, or none: the first is the one
  // heard.
  const chosen = list.some((voice) => voice.name === settings.speechVoice) ? settings.speechVoice : (list[0]?.name ?? null);
  return (
    <Sheet class="ow-voice-sheet">
      <div class="m3-title-medium">Speed</div>
      <div class="ow-voice-sheet__rates">
        {Settings.speechRates.map((rate) => (
          <Chip
            variant="choice"
            label={rateLabel(rate)}
            selected={settings.speechRate === rate}
            onClick={() => (settings.speechRate = rate)}
          />
        ))}
      </div>
      <div class="m3-title-medium" style="margin-top:20px">
        Voice
      </div>
      <div style="margin-top:4px">
        {voices.loading ? (
          <div style="padding:16px">
            <LinearProgress />
          </div>
        ) : (
          list.map((voice) => (
            <ListTile
              class="ow-voice-sheet__voice"
              icon={voice.name === chosen ? 'radio_button_checked' : 'radio_button_unchecked'}
              title={voice.title ?? voice.name}
              subtitle={voice.locale}
              onClick={() => (settings.speechVoice = voice.name)}
            />
          ))
        )}
      </div>
      <div class="m3-body-small m3-on-surface-variant" style="margin-top:8px">
        OpenWord’s own voices are read by KittenTTS (Apache-2.0), on this device with ONNX Runtime. Nothing leaves it. The
        others are this device’s own.
      </div>
    </Sheet>
  );
}

/**
 * What can be done with the verses selected, along the bottom of the
 * reader while there are any.
 */
function SelectionBar({
  citation,
  count,
  onClose,
  onCopy,
  onShare,
  onImage,
  onHighlight,
}: {
  citation: string;
  count: number;
  onClose: () => void;
  onCopy: () => void;
  onShare: () => void;
  onImage: () => void;
  onHighlight: () => void;
}) {
  return (
    <div class="ow-reader-bar">
      <IconButton icon="close" label="Clear selection" onClick={onClose} />
      <div class="ow-reader-bar__text">
        <div class="m3-title-small ow-truncate">{citation}</div>
        <div class="m3-label-small m3-on-surface-variant ow-truncate">
          {count === 1 ? '1 verse · tap more to add' : `${count} verses`}
        </div>
      </div>
      <IconButton icon="content_copy" label="Copy" onClick={onCopy} />
      <IconButton icon="share" label="Share" onClick={onShare} />
      <IconButton icon="image_outlined" label="Share as an image" onClick={onImage} />
      <IconButton icon="format_color_fill" label="Highlight" onClick={onHighlight} />
    </div>
  );
}

function Swatch({ color, name, selected, onTap }: { color: string; name: string; selected: boolean; onTap: () => void }) {
  const label = selected ? `Remove ${name} highlight` : `Highlight ${name}`;
  return (
    <button
      type="button"
      class={`ow-swatch m3-interactive${selected ? ' ow-swatch--selected' : ''}`}
      style={{ background: color }}
      aria-label={label}
      aria-pressed={selected}
      title={label}
      onClick={onTap}
    >
      {selected && <Icon name="check" size={18} />}
    </button>
  );
}
