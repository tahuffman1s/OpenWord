// A page to try the library, learning, plans, quiz and settings screens on
// their own, with the real bundled Bible and a reader made of cardboard:
//   npx vite --port 5204   →   http://localhost:5204/library-demo.html
// Query parameters, for screenshots and scripts:
//   ?open=library&tab=1      the library on Progress (0 Learn, 1 Progress, 2 Saved)
//   ?open=memory             a practice session of what is due
//   ?open=quiz&kind=whichBook&seed=1&count=3
//   ?open=plans  ?open=days  ?open=settings  ?open=licences
//   ?sheet=goal|badges|sleep|suggestions|import|voice|preview
//   ?dark=1                  the dark theme        ?colour=1   another seed colour
//   ?empty=1                 nothing seeded: the empty states
//   ?voice=fake|none|real    a silent stand-in (default), no voice, or the real one
//   ?clock=real              the real time of day rather than two in the afternoon
//   ?noreader=1              no reader registered: screens answer through their pop results
import { render, type VNode } from 'preact';
import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import '../ui/m3/m3.css';
import '../ui/app.css';
import { AppScope, setGlobalScope, type AppScopeValue } from '../app/scope';
import { registerFeatureOpener } from '../app/openFlow';
import { AccountController } from '../data/account';
import { setCreateSpeechEngine } from '../data/createSpeechEngine';
import { LibraryController } from '../data/library';
import { ReadingStore } from '../data/marks';
import { NeuralModel } from '../data/neuralVoices';
import { NoSpeechEngine, SpeechVoice, type ConfigureOptions, type SpeechEngine } from '../data/readAloud';
import { Settings, ThemeMode } from '../data/settings';
import { Shelf } from '../data/shelf';
import { rootBundle } from '../infra/assets';
import { useNotifier } from '../infra/changeNotifier';
import { Prefs } from '../infra/prefs';
import { Reference } from '../model/bible';
import { Confidence } from '../model/learnProgress';
import { millisPerDay } from '../model/localDate';
import { QuizKind, QuizMaker } from '../model/quiz';
import { Passage, ReadingPlans } from '../model/readingPlan';
import { SleepPolicy } from '../model/sleepPolicy';
import { SuggestedVerse } from '../model/suggestedVerses';
import { AppUpdates, type VersionInfo } from '../pwa/serviceWorker';
import { showImportSheet } from '../ui/importSheet';
import { showAchievementsSheet, showDailyGoalSheet } from '../ui/learnProgressCard';
import { showSuggestionsSheet } from '../ui/learnTab';
import { hasSomethingDue, LibraryScreen } from '../ui/libraryScreen';
import {
  AppBar,
  Button,
  LinearProgress,
  OverlayHost,
  Screen,
  SectionHeader,
  TonalButton,
  installRipples,
  nav,
  showSnackBar,
  watchTheme,
} from '../ui/m3';
import { MemoryScreen } from '../ui/memoryScreen';
import { PlanChapterCard, PlanDaysScreen, PlanReading, PlansScreen, hasChapter, nextInDay, planSlotFor } from '../ui/plansScreen';
import { PosttestCard, PretestCard } from '../ui/pretestCard';
import { QuizScreen } from '../ui/quizScreen';
import { registerReaderGoTo } from '../ui/readerNav';
import { LicencesScreen, SettingsScreen, showVoiceSheet } from '../ui/settingsScreen';
import { showSleepPolicySheet } from '../ui/sleepSheet';
import { SimpleMarkdown } from '../ui/widgets/simpleMarkdown';

const params = new URLSearchParams(location.search);

/** A voice that says nothing and takes about as long as saying it would. */
class DemoSpeech implements SpeechEngine {
  readonly said: string[] = [];
  private generation = 0;
  rate = 1;
  get isAvailable(): boolean {
    return true;
  }
  get canPause(): boolean {
    return false;
  }
  async configure(options: ConfigureOptions): Promise<void> {
    this.rate = options.rate;
  }
  async speak(text: string): Promise<boolean> {
    const mine = ++this.generation;
    this.said.push(text);
    (globalThis as { demoSaid?: string[] }).demoSaid = this.said;
    await new Promise((resolve) => setTimeout(resolve, Math.min(1800, 300 + (text.length * 25) / this.rate)));
    return mine === this.generation;
  }
  async stop(): Promise<void> {
    this.generation++;
  }
  async pause(): Promise<void> {}
  async resume(): Promise<void> {}
  async voices(): Promise<SpeechVoice[]> {
    return [
      ...NeuralModel.kitten.voices,
      new SpeechVoice({ name: 'Samantha', locale: 'en-US' }),
      new SpeechVoice({ name: 'Daniel', locale: 'en-GB' }),
    ];
  }
}

/** The updates notifier with nothing behind it: a build to name and a check that finds nothing. */
class DemoUpdates extends AppUpdates {
  private looking = false;
  private found = params.get('update') === '1';
  override get version(): VersionInfo | null {
    return { version: '2.0.0', builtAt: '2026-11-05T12:00:00Z', commit: 'demo123' };
  }
  override get supported(): boolean {
    return true;
  }
  override get offlineReady(): boolean {
    return true;
  }
  override get checking(): boolean {
    return this.looking;
  }
  override get updateAvailable(): boolean {
    return this.found;
  }
  override async checkNow(): Promise<void> {
    this.looking = true;
    this.notifyListeners();
    await new Promise((resolve) => setTimeout(resolve, 700));
    this.looking = false;
    this.notifyListeners();
  }
  override applyUpdate(): void {
    showSnackBar('The page would reload into the new build');
  }
}

interface Booted extends AppScopeValue {
  prefs: Prefs;
}

/** Today at two in the afternoon: neither morning nor evening, whenever the page is opened. */
function demoNow(): Date {
  if (params.get('clock') === 'real') return new Date();
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate(), 14, 0, 0);
}

/** A couple of verses on the ladder, a plan under way, marks and a week of points. */
function seed(reading: ReadingStore, clock: { now: Date }): void {
  const today = demoNow();
  const at = (daysAgo: number): Date => new Date(today.getTime() - daysAgo * millisPerDay);

  // Marks: bookmarks, highlights, notes.
  reading.toggleBookmark(new Reference('JHN', 3, 16));
  reading.toggleBookmark(new Reference('PSA', 23, 1));
  reading.toggleBookmark(new Reference('GEN', 1, 3));
  reading.setHighlight(new Reference('ROM', 8, 28), 1);
  reading.setHighlight(new Reference('GEN', 1, 1), 0);
  reading.setHighlight(new Reference('PSA', 119, 105), 3);
  reading.setNote(new Reference('PHP', 4, 13), 'Not about winning: about being content, whatever comes.');
  reading.setNote(new Reference('GEN', 1, 3), 'The first thing said.');
  for (const chapter of [new Reference('GEN', 1), new Reference('PSA', 23), new Reference('MAT', 5), new Reference('ROM', 8), new Reference('JHN', 3)]) {
    void reading.savePosition(chapter);
  }

  // Verses on the ladder, each reviewed on the day it fell due, from two
  // months back: one on each rung an exercise is set for, due today.
  const climb = (reference: Reference, recalls: number): void => {
    clock.now = at(60);
    reading.toggleMemorise(reference);
    for (let i = 0; i < recalls; i++) {
      const verse = reading.memoryFor(reference)!;
      clock.now = new Date(Math.max(clock.now.getTime(), verse.due.getTime() + 12 * 3_600_000));
      reading.reviewMemory(reference, { remembered: true });
    }
  };
  climb(new Reference('GEN', 1, 3), 1); // fill the blanks
  climb(new Reference('PSA', 23, 1), 2); // tap what you hear
  climb(new Reference('PHP', 4, 13), 4); // write it out
  climb(new Reference('PRO', 3, 5), 6); // learnt, and not due for a while
  reading.setMemoryHook(new Reference('PSA', 23, 1), 'shepherd');
  reading.setMemoryHook(new Reference('PHP', 4, 13), 'strength');

  // Nine days of practice ending yesterday: a streak, a freeze, a week of bars.
  const earned = [30, 45, 20, 40, 60, 10, 45, 25, 50];
  for (let i = 0; i < earned.length; i++) {
    clock.now = at(earned.length - i);
    reading.recordLearning({ xp: earned[i] - 12, right: true, confidence: i % 3 === 0 ? Confidence.fairly : Confidence.sure });
    reading.recordLearning({ xp: 12, right: true, scribed: i === 4, confidence: Confidence.sure });
    if (i % 4 === 1) reading.recordLearning({ xp: 0, right: false, confidence: i === 1 ? Confidence.sure : Confidence.guessing });
    if (i === 6) reading.recordLearning({ xp: 20, perfectRound: true });
  }

  // A plan five days in with two days read — behind, gently — and one begun today.
  clock.now = at(4);
  reading.startPlan(ReadingPlans.gospels);
  const gospels = ReadingPlans.gospels;
  reading.setPlanDay(gospels.id, gospels.days[0], true);
  reading.setPlanSlot(gospels.id, gospels.days[1].firstSlot, true);
  clock.now = today;
  reading.startPlan(ReadingPlans.proverbsMonth);

  // A new verse, added today: met first, then built up a clause at a time.
  reading.toggleMemorise(new Reference('JHN', 3, 16));
  reading.setSleepPolicy(SleepPolicy.standard);
}

async function boot(): Promise<Booted> {
  const persist = params.get('persist') === '1';
  const prefs = persist ? Prefs.open() : Prefs.memory();
  const fresh = !persist || !prefs.containsKey('marks');
  // Seeded with the timing off, so that every seeded verse climbs the
  // plain ladder; the trial is switched on once they are in.
  if (fresh) prefs.setString('sleep', JSON.stringify({ mode: 'off' }));
  const settings = await Settings.load(prefs);
  if (params.get('dark') === '1') settings.themeMode = ThemeMode.dark;
  else if (params.get('dark') === '0') settings.themeMode = ThemeMode.light;
  if (params.get('colour') === '1') settings.seedColor = Settings.seedChoices[1];
  if (params.get('font') === 'sans') settings.readingFont = 1;

  const voice = params.get('voice') ?? 'fake';
  if (voice === 'fake') {
    const speech = new DemoSpeech();
    setCreateSpeechEngine(() => speech);
  } else if (voice === 'none') {
    setCreateSpeechEngine(() => new NoSpeechEngine());
  }

  const clock = { now: demoNow() };
  const reading = await ReadingStore.load({ prefs, clock: () => (params.get('clock') === 'real' ? new Date() : clock.now) });
  if (fresh && params.get('empty') !== '1') seed(reading, clock);
  else if (fresh) reading.setSleepPolicy(SleepPolicy.standard);
  clock.now = demoNow();

  const shelf = await Shelf.open();
  await shelf?.refresh();
  const library = new LibraryController({ bundle: rootBundle, shelf });
  void library.load(settings.translationId);
  const updates = new DemoUpdates();
  // Signed out and never started: nothing here reaches for a server.
  const account = new AccountController({ prefs, reading, fetch: () => Promise.reject(new Error('The demo has no server')) });
  return { prefs, settings, reading, library, updates, account };
}

function Demo({ booted }: { booted: Booted }) {
  const { settings, library, reading } = booted;
  useNotifier(settings, library, reading);
  const scope = useMemo<AppScopeValue>(() => booted, [booted]);
  useEffect(() => setGlobalScope(scope), [scope]);
  useEffect(() => watchTheme(() => ({ seed: settings.seedColor, mode: settings.themeMode })), [settings.seedColor, settings.themeMode, settings]);

  // The cardboard reader: where it has been sent, and from which plan day.
  const [current, setCurrent] = useState(new Reference('JHN', 3));
  const [planFocus, setPlanFocus] = useState<PlanReading | null>(null);
  const [guessed, setGuessed] = useState<number | null>(null);
  const [answered, setAnswered] = useState<number | null>(null);
  const bible = library.bible;

  // For a script driving the page: a verse's text by its label, and the books in order.
  useEffect(() => {
    const hooks = globalThis as { demoTextOf?: (label: string) => string; demoBooks?: string[] };
    hooks.demoBooks = bible?.books.map((book) => book.name) ?? [];
    hooks.demoTextOf = (label) => {
      for (const verse of reading.memoryVerses) {
        if (verse.reference.label !== label) continue;
        return bible?.bookByCode(verse.reference.bookCode)?.chapter(verse.reference.chapter)?.verseText(verse.reference.verse!) ?? '';
      }
      return '';
    };
  }, [bible, reading]);

  const goTo = (reference: Reference, plan?: PlanReading): void => {
    setCurrent(reference);
    if (plan !== undefined) setPlanFocus(plan);
    (globalThis as { demoReaderAt?: string }).demoReaderAt = reference.label;
    showSnackBar(`Reader: ${reference.label}${plan === undefined ? '' : ` (plan day ${plan.day})`}`);
  };

  useEffect(() => {
    if (params.get('noreader') === '1') return;
    return registerReaderGoTo(goTo);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /** Pushes a screen and goes where it closed with, as a reader that awaits its screens does. */
  const push = async (screen: VNode): Promise<void> => {
    const result = await nav.push<Reference | PlanReading>(screen);
    if (result === undefined || params.get('noreader') !== '1') return;
    if (result instanceof Reference) goTo(result);
    else goTo(result.chapter, result);
  };

  const openers: Record<string, () => void> = {
    library: () => void push(<LibraryScreen initialTab={Number(params.get('tab') ?? 0)} />),
    learn: () => void push(<LibraryScreen />),
    memory: () => void push(<MemoryScreen seed={params.get('seed') === null ? null : Number(params.get('seed'))} />),
    quiz: () =>
      void push(
        <QuizScreen
          kind={QuizKind.values.find((kind) => kind.name === params.get('kind')) ?? QuizKind.mixed}
          seed={params.get('seed') === null ? null : Number(params.get('seed'))}
          count={params.get('count') === null ? undefined : Number(params.get('count'))}
        />,
      ),
    plans: () => void push(<PlansScreen />),
    days: () => void push(<PlanDaysScreen planId={ReadingPlans.gospels.id} />),
    settings: () => void push(<SettingsScreen />),
    licences: () => void push(<LicencesScreen />),
  };
  const sheets: Record<string, () => void> = {
    goal: () => void showDailyGoalSheet(reading),
    badges: () => void showAchievementsSheet(reading),
    sleep: () => void showSleepPolicySheet(reading),
    suggestions: () => bible !== null && void showSuggestionsSheet(reading, SuggestedVerse.available(bible, (r) => reading.isMemorising(r))),
    import: () => library.shelf !== null && void showImportSheet({ shelf: library.shelf, library, settings }),
    voice: () => void showVoiceSheet({ settings, engine: new DemoSpeech(), language: 'en' }),
  };

  // What the reader does for the features this page stands in for.
  useEffect(
    () =>
      registerFeatureOpener((feature) => {
        const open = openers[feature];
        if (open !== undefined) open();
        else showSnackBar(`The reader would open: ${feature}`);
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  // Straight to a screen or a sheet, for a screenshot — once, not again
  // each time another translation has been read in.
  const opened = useRef(false);
  useEffect(() => {
    if (!library.isReady || opened.current) return;
    opened.current = true;
    const timer = setTimeout(() => {
      const open = params.get('open');
      const sheet = params.get('sheet');
      if (open !== null) openers[open]?.();
      if (sheet !== null) setTimeout(() => sheets[sheet]?.(), open === null ? 0 : 350);
    }, 0);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [library.isReady]);

  // The end of the chapter the reader is "on", where a plan has it.
  const hit = planSlotFor(reading, current, planFocus);
  const next = hit === null ? null : nextInDay(bible, hit.progress, hit.day, hit.slot);
  const pretest = useMemo(
    () => (bible === null || hit === null ? [] : new QuizMaker(bible).makeForChapter(current.withVerse(null))),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [bible, current.key, hit === null],
  );

  if (!library.isReady) {
    return (
      <div class="ow-splash">
        <div class="ow-splash__title">Library demo</div>
        {library.errorMessage ?? (
          <div style="width:120px">
            <LinearProgress />
          </div>
        )}
      </div>
    );
  }

  return (
    <Screen
      appBar={(s) => <AppBar scrolled={s} leading="none" title="Library demo" subtitle={`${library.translation.abbreviation} · something due: ${hasSomethingDue(reading) ? 'yes' : 'no'}`} />}
      padded
    >
      <div class="ow-content">
        <SectionHeader>Screens</SectionHeader>
        <div class="ow-row" style="flex-wrap:wrap">
          <Button onClick={openers.learn}>Library</Button>
          <TonalButton onClick={() => void push(<LibraryScreen initialTab={1} />)}>Progress</TonalButton>
          <TonalButton onClick={() => void push(<LibraryScreen initialTab={2} />)}>Saved</TonalButton>
          <Button onClick={openers.memory}>Practise</Button>
          <Button onClick={openers.plans}>Plans</Button>
          <Button onClick={openers.settings}>Settings</Button>
          <TonalButton onClick={openers.licences}>Licences</TonalButton>
        </div>
        <SectionHeader>Rounds</SectionHeader>
        <div class="ow-row" style="flex-wrap:wrap">
          {QuizKind.values.map((kind) => (
            <TonalButton key={kind.name} onClick={() => void push(<QuizScreen kind={kind} />)}>
              {kind.label}
            </TonalButton>
          ))}
          <TonalButton onClick={() => void push(<QuizScreen kind={QuizKind.bookOrder} count={3} />)}>Three questions</TonalButton>
        </div>
        <SectionHeader>Sheets</SectionHeader>
        <div class="ow-row" style="flex-wrap:wrap">
          {Object.keys(sheets).map((name) => (
            <TonalButton key={name} onClick={sheets[name]}>
              {name}
            </TonalButton>
          ))}
        </div>

        <SectionHeader>The reader, in cardboard</SectionHeader>
        <div class="m3-title-large" data-key="reader-at">
          {current.label}
        </div>
        <div class="m3-body-medium" style="padding:4px 0 16px;color:var(--md-sys-color-on-surface-variant)">
          Screens send the reader here. Where a plan has this chapter, the cards the reader shows before and after it are below.
        </div>
        {hit !== null && pretest.length > 0 && answered === null && (
          <PretestCard
            questions={pretest.length}
            guessed={guessed}
            onGuess={() =>
              void push(
                <QuizScreen kind={QuizKind.finishVerse} questions={pretest} title="Guess before you read" onFinished={(right) => setGuessed(right)} />,
              )
            }
          />
        )}
        {hit !== null && guessed !== null && (
          <PosttestCard
            questions={pretest.length}
            guessed={guessed}
            answered={answered}
            onAnswer={() => void push(<QuizScreen kind={QuizKind.finishVerse} questions={pretest} title="After reading" onFinished={(right) => setAnswered(right)} />)}
          />
        )}
        {hit !== null && (
          <PlanChapterCard
            planName={hit.progress.plan.name}
            day={hit.day.number}
            read={hit.progress.isRead(hit.slot)}
            nextLabel={next === null ? null : Passage.labelFor(next)}
            onDone={() => {
              reading.setPlanSlot(hit.progress.plan.id, hit.slot, true);
              setPlanFocus(new PlanReading({ planId: hit.progress.plan.id, day: hit.day.number, chapter: current }));
              if (next !== null) {
                setCurrent(next);
                setGuessed(null);
                setAnswered(null);
                return;
              }
              const after = reading.progressFor(hit.progress.plan.id);
              if (after !== null && after.isDayRead(hit.day)) {
                showSnackBar(after.isComplete ? `You finished ${after.plan.name}. Well done.` : `Day ${hit.day.number} done. That’s today’s reading.`, {
                  action: { label: 'Plans', onPressed: openers.plans },
                });
              }
            }}
            onUndo={() => reading.setPlanSlot(hit.progress.plan.id, hit.slot, false)}
            onNext={next === null || !hasChapter(bible, next) ? null : () => setCurrent(next)}
          />
        )}

        <SectionHeader>Markdown</SectionHeader>
        <SimpleMarkdown
          source={'Setting\n=======\n\nGenesis is the book\nof **beginnings**, and *first things*.\n\nOutline\n-------\n\n* Creation\n* The patriarchs\n\n1. Abraham\n2. Isaac\n\n-----\n\nCC BY\\-SA 4\\.0'}
        />
      </div>
    </Screen>
  );
}

function Root() {
  const [booted, setBooted] = useState<Booted | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  useEffect(() => {
    installRipples();
    boot().then(setBooted, (error) => {
      console.error('Library demo: could not start', error);
      setFailure(String(error));
    });
  }, []);
  if (booted === null) return <div class="ow-splash">{failure ?? 'Starting…'}</div>;
  return (
    <AppScope value={booted}>
      <Demo booted={booted} />
      <OverlayHost />
    </AppScope>
  );
}

render(<Root />, document.getElementById('app')!);
