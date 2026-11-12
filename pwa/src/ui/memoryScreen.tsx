import { toChildArray, type ComponentChildren } from 'preact';
import { useEffect, useMemo } from 'preact/hooks';
import { useAppScope, type AppScopeValue } from '../app/scope';
import { createSpeechEngine } from '../data/createSpeechEngine';
import { LearnVoice } from '../data/learnVoice';
import type { ReadingStore } from '../data/marks';
import type { Settings } from '../data/settings';
import { ChangeNotifier, useNotifier } from '../infra/changeNotifier';
import type { Achievement } from '../model/achievements';
import { BlockStyle, isVerseText, Markup, type Bible, type Reference } from '../model/bible';
import { Confidence, confidenceLabel, confidenceValues, Xp } from '../model/learnProgress';
import { LocalDate } from '../model/localDate';
import { Cloze, MemoryExercise, TypedVerse, VerseSteps, VerseTiles } from '../model/memoryExercise';
import { MemoryPrompt, MemoryStage, TrialArm, type MemoryVerse } from '../model/memoryVerse';
import { seededRandom, shuffle, type RandomSource } from '../model/random';
import { SleepMode, SleepPolicy } from '../model/sleepPolicy';
import { AchievementIcon } from './learnProgressCard';
import { AppBar, Chip, FilledButton, Icon, IconButton, LinearProgress, Screen, TextButton, TextField, useOverlay } from './m3';
import { openInReader } from './readerNav';
import { scriptureBodyStyle } from './scriptureStyle';
import { Confetti } from './widgets/confetti';
import './shared.css';
import './memoryScreen.css';

/** How an exercise ended. */
type Outcome = 'right' | 'wrong' | 'shown';

/** A buzz where the device has one, as `HapticFeedback` gives. */
function haptic(millis: number): void {
  try {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') navigator.vibrate(millis);
  } catch {
    // Not allowed here, or not there: nothing is lost.
  }
}

/**
 * A practice session's state: the queue, the exercise under way and the
 * tally — what `_MemoryScreenState` holds in the Dart, kept apart from the
 * component so that each step reads as it does there.
 */
class MemorySession extends ChangeNotifier {
  readonly queue: Reference[];
  readonly total: number;
  private readonly random: RandomSource;
  done = 0;

  // The session's tally: points, the run of right answers, and badges.
  sessionXp = 0;
  combo = 0;
  bestCombo = 0;
  rightCount = 0;
  answeredCount = 0;
  readonly won: Achievement[] = [];
  readonly goalMetBefore: boolean;
  readonly levelBefore: number;

  /** What the last answer earned, for the verdict. */
  lastXp = 0;
  lastBonus = 0;

  /** How sure the reader said they were, where asked. */
  confidence: Confidence | null = null;

  /**
   * Whether this exercise is a verse's first recall after learning, so
   * that the trial's question is asked before going on.
   */
  firstRecall = false;

  /** The trial's question, answered; null while it waits. */
  slept: boolean | null = null;

  /**
   * The stage and timing of the verse as the exercise began, for what
   * the verdict says comes next.
   */
  stageBefore: MemoryStage = MemoryStage.waiting;
  armBefore: TrialArm | null = null;

  /**
   * Whether the verse is being met before it is built: read over, set
   * in its chapter, and given the reader's own word.
   */
  meeting = false;
  hook = '';
  private readonly met = new Set<string>();

  /**
   * A long verse is built up a clause at a time: the texts of the
   * steps, the step under way, and whether the last check of a step
   * short of the whole fell short.
   */
  steps: string[] = [];
  step = 0;
  stepMissed = false;

  /** The whole verse, where `text` is the step's part of it. */
  whole = '';

  /** When the answering began, for how long it took. */
  private startedAt: number | null = null;

  /** The voice, where there is one. */
  readonly voice: LearnVoice | null = null;

  // The exercise under way.
  reference: Reference | null = null;
  text = '';
  exercise: MemoryExercise = MemoryExercise.arrangeShown;
  tiles: string[] = [];
  placed: number[] = [];
  cloze: Cloze | null = null;
  filled: (string | null)[] = [];
  typed = '';
  hinted = false;
  outcome: Outcome | null = null;

  /** Counts exercises begun, so each gets widgets of its own. */
  round = 0;

  private closed = false;
  private readonly voiceChanged = (): void => this.notifyListeners();

  constructor(
    private readonly scope: Pick<AppScopeValue, 'settings' | 'library' | 'reading'>,
    first: Reference | null,
    seed: number | null,
  ) {
    super();
    this.random = seed === null ? Math.random : seededRandom(seed);
    const reading = scope.reading;
    // The queue is fixed when the screen opens: a verse answered inside
    // the session must not be asked again because it is still due, and
    // one not recalled is put back by hand.
    this.queue = [
      ...(first !== null && reading.isMemorising(first) ? [first] : []),
      ...reading.memoryDue.filter((verse) => !verse.reference.equals(first)).map((verse) => verse.reference),
    ];
    this.total = this.queue.length;
    this.goalMetBefore = reading.progress.goalMetOn(reading.today);
    this.levelBefore = reading.progress.level;

    const bible = scope.library.bible;
    if (bible !== null) {
      this.voice = new LearnVoice({
        engine: createSpeechEngine(),
        language: bible.translation.language,
        rate: scope.settings.speechRate,
        voice: scope.settings.speechVoice,
      });
      this.voice.addListener(this.voiceChanged);
    }
    this.begin();
  }

  get reading(): ReadingStore {
    return this.scope.reading;
  }

  get settings(): Settings {
    return this.scope.settings;
  }

  get bible(): Bible | null {
    return this.scope.library.bible;
  }

  get canListen(): boolean {
    return this.voice?.isAvailable ?? false;
  }

  /**
   * Whether the voice speaks of its own accord: the verse as it appears,
   * a tile as it is tapped, the verse again once checked.
   */
  get autoSpeak(): boolean {
    return this.canListen && this.settings.learnAutoSpeak;
  }

  get speaking(): boolean {
    return this.voice?.isSpeaking ?? false;
  }

  override dispose(): void {
    this.closed = true;
    this.voice?.removeListener(this.voiceChanged);
    this.voice?.dispose();
    super.dispose();
  }

  /**
   * The heading the verse falls under in its chapter, or the chapter's
   * name: where the verse sits, in a line.
   */
  contextOf(reference: Reference): string {
    const chapter = this.bible?.bookByCode(reference.bookCode)?.chapter(reference.chapter);
    const fallback = reference.withVerse(null).label;
    if (chapter === undefined) return fallback;
    let heading: string | null = null;
    for (const block of chapter.blocks) {
      if (block.style === BlockStyle.heading) {
        const text = block.segments
          .map((s) => Markup.strip(s.text).trim())
          .filter((t) => t.length > 0)
          .join(' ');
        if (text.length > 0) heading = text;
        continue;
      }
      if (!isVerseText(block.style)) continue;
      if (block.segments.some((s) => s.verse === reference.verse)) {
        return heading === null ? fallback : `${heading} · ${fallback}`;
      }
    }
    return fallback;
  }

  private textOf(reference: Reference): string {
    const bible = this.bible;
    if (bible === null || reference.verse === null) return '';
    return bible.bookByCode(reference.bookCode)?.chapter(reference.chapter)?.verseText(reference.verse) ?? '';
  }

  /**
   * Sets the exercise for the verse at the head of the queue, and has it
   * spoken where it is shown or is to be heard.
   */
  private begin(): void {
    const autoSpeak = this.settings.learnAutoSpeak;
    this.round++;
    this.outcome = null;
    this.hinted = false;
    this.confidence = null;
    this.slept = null;
    this.placed = [];
    this.typed = '';
    const reference = this.queue.length === 0 ? null : this.queue[0];
    this.reference = reference;
    if (reference === null) return;
    this.whole = this.textOf(reference);
    this.text = this.whole;
    const verse = this.reading.memoryFor(reference);
    this.stageBefore = verse?.stage ?? MemoryStage.waiting;
    // A verse never yet learnt is met first: read, placed, given a word.
    this.meeting =
      this.stageBefore === MemoryStage.waiting &&
      (verse?.recalled ?? 0) === 0 &&
      (verse?.introduced ?? null) === null &&
      this.whole.length > 0 &&
      !this.met.has(reference.key);
    if (this.meeting) this.met.add(reference.key);
    this.hook = verse?.hook ?? '';
    this.steps = this.stageBefore === MemoryStage.waiting ? VerseSteps.of(this.whole) : [this.whole];
    this.step = 0;
    this.stepMissed = false;
    if (this.steps.length > 1) this.text = this.steps[0];
    this.startedAt = this.meeting ? null : Date.now();
    this.armBefore = verse?.arm ?? null;
    this.firstRecall = verse?.awaitsFirstRecall ?? false;
    // A verse not yet learnt is copied out; its first recall is asked
    // bare, the same way for every verse, so the trial compares like
    // with like; after that the rung decides.
    this.exercise =
      this.stageBefore === MemoryStage.waiting
        ? MemoryExercise.arrangeShown
        : this.stageBefore === MemoryStage.introduced
          ? MemoryExercise.arrange
          : MemoryExercise.forRung(verse?.rung ?? 0, this.canListen);
    this.tiles = this.shuffled(VerseTiles.of(this.text));
    this.cloze = this.text.length === 0 ? null : Cloze.make(this.text, this.random);
    this.filled = new Array<string | null>(this.cloze?.blanks.length ?? 0).fill(null);
    const heard = this.exercise === MemoryExercise.listenArrange;
    if (this.text.length > 0 && this.canListen && (heard || (autoSpeak && this.exercise.showsText))) {
      const round = this.round;
      // Once the exercise is on screen, as a post-frame callback has it.
      setTimeout(() => {
        if (!this.closed && round === this.round) void this.voice?.say(this.meeting ? this.whole : this.text);
      }, 0);
    }
  }

  /** The tiles in an order that is not the verse's, where there is one. */
  private shuffled(tiles: string[]): string[] {
    if (tiles.length < 2) return tiles;
    const out = [...tiles];
    for (let i = 0; i < 8; i++) {
      shuffle(out, this.random);
      if (!VerseTiles.inOrder(out, this.text)) return out;
    }
    return out.reverse();
  }

  /** Says the verse, or stops it if it is being said; slowly when asked. */
  speak(slow = false): void {
    const voice = this.voice;
    if (voice === null || !this.canListen || this.whole.length === 0) return;
    if (voice.isSpeaking && !slow) {
      void voice.stop();
      return;
    }
    void voice.say(this.meeting ? this.whole : this.text, { slow });
  }

  setHook(value: string): void {
    this.hook = value;
    this.notifyListeners();
  }

  /** The verse met: its word kept, and the building begun. */
  finishMeeting(): void {
    const reference = this.reference;
    if (reference === null) return;
    this.reading.setMemoryHook(reference, this.hook);
    this.meeting = false;
    this.startedAt = Date.now();
    this.notifyListeners();
    if (this.autoSpeak) void this.voice?.say(this.text);
  }

  /** Seconds the answer took, from the exercise's start. */
  private get seconds(): number | null {
    return this.startedAt === null ? null : (Date.now() - this.startedAt) / 1000;
  }

  private get words(): number {
    return this.whole.split(' ').filter((w) => w.length > 0).length;
  }

  /** A tile tapped is heard, the way a word tile is in a language app. */
  place(i: number): void {
    this.placed = [...this.placed, i];
    this.notifyListeners();
    if (this.autoSpeak) void this.voice?.say(this.tiles[i]);
  }

  unplace(at: number): void {
    this.placed = this.placed.filter((_, index) => index !== at);
    this.notifyListeners();
  }

  fill(word: string): void {
    const at = this.filled.indexOf(null);
    if (at >= 0) {
      this.filled = this.filled.map((w, index) => (index === at ? word : w));
    }
    this.notifyListeners();
    if (this.autoSpeak) void this.voice?.say(word);
  }

  unfill(blank: number): void {
    this.filled = this.filled.map((w, index) => (index === blank ? null : w));
    this.notifyListeners();
  }

  setTyped(value: string): void {
    this.typed = value;
    this.notifyListeners();
  }

  hint(): void {
    this.hinted = true;
    this.notifyListeners();
  }

  setConfidence(level: Confidence): void {
    this.confidence = level;
    this.notifyListeners();
  }

  private get answered(): boolean {
    if (this.exercise === MemoryExercise.fillBlanks) return this.filled.every((w) => w !== null);
    if (this.exercise === MemoryExercise.typeOut) return this.typed.trim().length > 0;
    return this.placed.length === this.tiles.length;
  }

  /**
   * Whether the reader is asked how sure they are: only when answering
   * from memory, where the question means something.
   */
  get asksConfidence(): boolean {
    return !this.exercise.showsText;
  }

  get canCheck(): boolean {
    return this.answered && (!this.asksConfidence || this.confidence !== null);
  }

  check(): void {
    const right =
      this.exercise === MemoryExercise.fillBlanks
        ? this.cloze!.check(this.filled)
        : this.exercise === MemoryExercise.typeOut
          ? TypedVerse.matches(this.typed, this.text)
          : VerseTiles.inOrder(
              this.placed.map((i) => this.tiles[i]),
              this.text,
            );
    // A step short of the whole is not the verse: right, the next clause
    // is added; wrong, the same step is tried again, with nothing lost.
    if (this.step < this.steps.length - 1) {
      haptic(5);
      this.stepMissed = !right;
      if (right) this.step++;
      this.text = this.steps[this.step];
      this.placed = [];
      this.tiles = this.shuffled(VerseTiles.of(this.text));
      this.notifyListeners();
      return;
    }
    this.settle(right ? 'right' : 'wrong');
  }

  show(): void {
    this.settle('shown');
  }

  private settle(outcome: Outcome): void {
    const reference = this.reference!;
    const reading = this.reading;
    const right = outcome === 'right';
    const rung = reading.memoryFor(reference)?.rung ?? 0;
    const sure = this.asksConfidence && this.confidence === Confidence.sure;
    // A first recall is recorded once the reader has said whether they
    // slept, for the trial; everything else is recorded now.
    if (!this.firstRecall) {
      reading.reviewMemory(reference, { remembered: right, sure, seconds: this.seconds, words: this.words });
    }
    this.answeredCount++;
    if (right) {
      this.rightCount++;
      this.combo++;
      if (this.combo > this.bestCombo) this.bestCombo = this.combo;
      this.lastBonus = Xp.comboBonus(this.combo);
      this.lastXp = Xp.memoryRight(rung) + this.lastBonus;
      haptic(15);
    } else {
      this.combo = 0;
      this.lastBonus = 0;
      this.lastXp = 0;
      haptic(30);
    }
    this.sessionXp += this.lastXp;
    this.won.push(
      ...reading.recordLearning({
        xp: this.lastXp,
        right,
        scribed: right && this.exercise === MemoryExercise.typeOut,
        heard: right && this.exercise === MemoryExercise.listenArrange,
        confidence: this.asksConfidence ? this.confidence : null,
      }),
    );
    this.outcome = outcome;
    this.notifyListeners();
    // The verse is heard whole once it is answered, right or not.
    if (this.autoSpeak) void this.voice?.say(this.text);
  }

  /** The trial's question answered: the first recall is recorded with it. */
  answerSlept(slept: boolean): void {
    const reference = this.reference!;
    this.reading.reviewMemory(reference, {
      remembered: this.outcome === 'right',
      slept,
      sure: this.asksConfidence && this.confidence === Confidence.sure,
      seconds: this.seconds,
      words: this.words,
    });
    this.slept = slept;
    this.notifyListeners();
  }

  /**
   * Goes on to the next verse; one not answered is asked again before
   * the session ends.
   */
  continue(): void {
    const reference = this.queue.shift()!;
    if (this.outcome === 'right') {
      this.done++;
    } else {
      this.queue.push(reference);
    }
    this.begin();
    this.notifyListeners();
  }

  /** Skips a verse this translation has no text for. */
  skip(): void {
    this.queue.shift();
    this.begin();
    this.notifyListeners();
  }

  /** Days until the verse is next due, as it now stands. */
  waitDaysFor(verse: MemoryVerse): number {
    return LocalDate.daysBetween(verse.due, LocalDate.only(this.reading.today));
  }
}

/**
 * Practising the verses being learnt by heart: the ones due today, one
 * after another, each set as an exercise the verse's rung calls for —
 * tiles to put in order, blanks to fill, the verse heard and put
 * together, or written out — and checked. A right answer climbs the
 * ladder; a wrong one drops to the bottom and is asked again before the
 * session ends. The verse can be heard at any point, where the device
 * has a voice.
 *
 * Closes with a reference when the reader asks to open a verse in the
 * reader — and sends the reader there — and with nothing otherwise.
 */
export function MemoryScreen({
  first = null,
  seed = null,
}: {
  /** A verse to begin with, whether or not it is due; the due ones follow. */
  first?: Reference | null;

  /** Fixes the shuffle, for a test; the app leaves it to chance. */
  seed?: number | null;
}) {
  const scope = useAppScope();
  const overlay = useOverlay();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const session = useMemo(() => new MemorySession(scope, first, seed), []);
  useNotifier(session, scope.reading);
  useEffect(() => () => session.dispose(), [session]);

  const reading = scope.reading;
  const reference = session.reference;
  const verse = reference === null ? null : reading.memoryFor(reference);
  const open = (target: Reference): void => {
    overlay.close(target);
    openInReader(target);
  };

  return (
    <Screen
      class="ow-memory"
      appBar={(scrolled) => (
        <>
          <AppBar
            scrolled={scrolled}
            title="Practise"
            actions={
              <>
                {session.canListen && <AutoSpeakButton />}
                {reference !== null && <IconButton icon="menu_book" label="Open in the reader" onClick={() => open(reference)} />}
              </>
            }
          />
          {session.total > 0 && <LinearProgress value={session.done / session.total} />}
        </>
      )}
    >
      {reference === null || verse === null ? (
        <Finished
          total={session.total}
          reading={reading}
          xp={session.sessionXp}
          right={session.rightCount}
          answered={session.answeredCount}
          bestCombo={session.bestCombo}
          won={session.won}
          goalMetNow={!session.goalMetBefore && reading.progress.goalMetOn(reading.today)}
          levelledUp={reading.progress.level > session.levelBefore}
        />
      ) : session.text.length === 0 ? (
        <NoText reference={reference} onSkip={() => session.skip()} />
      ) : session.meeting ? (
        <Meet key={`meet/${session.round}`} session={session} reference={reference} context={session.contextOf(reference)} />
      ) : (
        <Exercise key={session.round} session={session} verse={verse} />
      )}
    </Screen>
  );
}

function Exercise({ session, verse }: { session: MemorySession; verse: MemoryVerse }) {
  const { exercise, tiles, placed, filled, outcome, hinted, text } = session;
  const cloze = session.cloze!;
  const over = outcome !== null;
  const steps = session.steps.length;
  const step = session.step;
  const scripture = scriptureBodyStyle(session.settings);
  const tile = `${scriptureBodyStyle(session.settings, 0.9)};line-height:1.3`;
  const canSpeak = session.canListen;

  /**
   * Whether the nth bank word is sitting in a blank. The same word can
   * be in the bank twice only when it is wanted twice, so the first
   * unused copy is the one counted as used.
   */
  const bankUsed = (i: number): boolean => {
    const word = cloze.bank[i];
    const inBlanks = filled.filter((w) => w === word).length;
    let earlier = 0;
    for (let j = 0; j < i; j++) {
      if (cloze.bank[j] === word) earlier++;
    }
    return earlier < inBlanks;
  };

  /**
   * When the verse comes round again, from where it stood when the
   * exercise began.
   */
  const nextWaitLine = (): string => {
    if (outcome !== 'right') {
      return 'Back to the first rung; asked again today.';
    }
    if (session.stageBefore === MemoryStage.waiting) {
      const timed = session.reading.sleepPolicy.mode !== SleepMode.off;
      if (session.armBefore === TrialArm.night && timed) {
        return 'Learnt tonight. Asked for tomorrow morning, after you have slept on it.';
      }
      if (session.armBefore === TrialArm.day && timed) {
        return `Learnt. Asked for again in about ${SleepPolicy.dayGapHours} hours, before this evening.`;
      }
      return 'Asked again tomorrow.';
    }
    const waitDays = session.waitDaysFor(verse);
    return waitDays <= 1 ? 'Asked again tomorrow.' : `Asked again in ${waitDays} days.`;
  };

  return (
    <div class="ow-memory__page">
      <div class="ow-memory__head">
        <div class="ow-memory__head-text">
          <div class="m3-headline-small">{verse.reference.label}</div>
          <div class="m3-body-medium ow-muted">{standing(verse, session.queue.length)}</div>
        </div>
        {canSpeak && <SpeakButtons speaking={session.speaking} onSpeak={() => session.speak()} onSpeakSlowly={() => session.speak(true)} />}
      </div>
      <div class="ow-memory__task">
        <div class="m3-title-medium">{steps > 1 ? `Build it up · ${step + 1} of ${steps}` : exercise.label}</div>
        <div class="m3-body-medium ow-muted">
          {steps > 1
            ? step === 0
              ? 'The first clause. Tap its tiles in order; the next is added each time.'
              : step === steps - 1
                ? 'The whole verse now.'
                : 'So far, and the next clause.'
            : exercise.instruction}
        </div>
        {session.stepMissed && <div class="m3-body-medium m3-error ow-memory__missed">Not quite; once more.</div>}
        {!exercise.showsText && verse.hook.length > 0 && <div class="m3-body-medium ow-memory__hook">Your word for it: {verse.hook}</div>}
        {hinted && !exercise.showsText && (
          <div class="ow-memory__hint ow-muted" style={tile}>
            {MemoryPrompt.hint(text)}
          </div>
        )}
      </div>

      {exercise === MemoryExercise.arrangeShown && (
        <Card>
          <div style={scripture}>{text}</div>
        </Card>
      )}
      {exercise === MemoryExercise.fillBlanks && (
        <Card>
          <ClozeText cloze={cloze} filled={filled} style={scripture} onUnfill={over ? null : (blank) => session.unfill(blank)} />
        </Card>
      )}
      {exercise.usesTiles && (
        <>
          <Answer empty={exercise === MemoryExercise.listenArrange ? 'Listen, then tap the tiles in order.' : 'Tap the tiles in order.'} spaced={exercise === MemoryExercise.arrangeShown}>
            {placed.map((index, at) => (
              <Tile key={`${index}`} text={tiles[index]} style={tile} placed onTap={over ? null : () => session.unplace(at)} />
            ))}
          </Answer>
          <div class="ow-memory__bank" data-key="bank">
            {tiles.map((word, i) => (
              <Tile key={i} dataKey={`bank/${i}`} text={word} style={tile} used={placed.includes(i)} onTap={over || placed.includes(i) ? null : () => session.place(i)} />
            ))}
          </div>
        </>
      )}
      {exercise === MemoryExercise.fillBlanks && (
        <div class="ow-memory__bank" data-key="bank">
          {cloze.bank.map((word, i) => (
            <Tile
              key={i}
              dataKey={`bank/${i}`}
              text={word}
              style={tile}
              used={bankUsed(i)}
              onTap={over || bankUsed(i) || !filled.includes(null) ? null : () => session.fill(word)}
            />
          ))}
        </div>
      )}
      {exercise === MemoryExercise.typeOut && (
        <div class="ow-memory__typed" style={scripture}>
          <TextField
            name="typed"
            value={session.typed}
            onInput={(value) => session.setTyped(value)}
            disabled={over}
            autoFocus
            multiline
            rows={3}
            placeholder="The verse, as you remember it"
            autocomplete="off"
          />
        </div>
      )}

      <div class="ow-memory__actions">
        {!over && session.asksConfidence && (
          <div class="ow-memory__confidence">
            <div class="m3-label-large">How sure are you?</div>
            <div class="ow-memory__chips" role="radiogroup">
              {confidenceValues.map((level) => (
                <Chip key={level} variant="choice" label={confidenceLabel[level]} selected={session.confidence === level} onClick={() => session.setConfidence(level)} />
              ))}
            </div>
          </div>
        )}
        {!over ? (
          <div class="ow-memory__buttons">
            {!exercise.showsText && !hinted && (
              <TextButton icon="lightbulb_outlined" onClick={() => session.hint()}>
                Hint
              </TextButton>
            )}
            <TextButton icon="visibility_outlined" onClick={() => session.show()}>
              Show me
            </TextButton>
            <span class="ow-spacer" />
            <FilledButton icon="check" disabled={!session.canCheck} onClick={() => session.check()}>
              Check
            </FilledButton>
          </div>
        ) : (
          <>
            <Verdict
              outcome={outcome}
              text={text}
              style={scripture}
              xp={session.lastXp}
              bonus={session.lastBonus}
              combo={session.combo}
              sureMiss={session.asksConfidence && session.confidence === Confidence.sure && outcome !== 'right'}
              nextWait={nextWaitLine()}
            />
            {session.firstRecall && <SleptQuestion answer={session.slept} onAnswer={(slept) => session.answerSlept(slept)} />}
            <FilledButton class="ow-memory__continue" icon="arrow_forward" disabled={session.firstRecall && session.slept === null} onClick={() => session.continue()}>
              Continue
            </FilledButton>
          </>
        )}
      </div>
    </div>
  );
}

function standing(verse: MemoryVerse, remaining: number): string {
  const where = verse.isLearnt ? 'Learnt' : verse.rung === 0 ? 'New' : `Rung ${verse.rung}`;
  const times = verse.recalled === 0 ? 'not yet recalled' : verse.recalled === 1 ? 'recalled once' : `recalled ${verse.recalled} times`;
  const left = remaining === 1 ? 'the last one today' : `${remaining} to go`;
  return `${where} · ${times} · ${left}`;
}

/** A verse with its blanks, the filled ones tappable to empty again. */
function ClozeText({ cloze, filled, style, onUnfill }: { cloze: Cloze; filled: readonly (string | null)[]; style: string; onUnfill: ((blank: number) => void) | null }) {
  return (
    <div class="ow-cloze" style={style}>
      {cloze.words.map((word, i) => {
        const blank = cloze.blanks.indexOf(i);
        if (blank < 0) return `${word.lead}${word.core}${word.trail} `;
        const answer = filled[blank];
        return (
          <>
            {word.lead}
            <button
              type="button"
              class={`ow-cloze__blank${answer === null ? '' : ' ow-cloze__blank--filled m3-interactive'}`}
              data-key={`blank/${i}`}
              aria-label={answer === null ? 'Blank' : `${answer}: take it back`}
              disabled={answer === null || onUnfill === null}
              onClick={() => onUnfill?.(blank)}
            >
              {answer ?? ''}
            </button>
            {`${word.trail} `}
          </>
        );
      })}
    </div>
  );
}

function Card({ children }: { children: ComponentChildren }) {
  return <div class="ow-memory__card">{children}</div>;
}

/** Where placed tiles go: a box that reads as the answer being built. */
function Answer({ children, empty, spaced }: { children: ComponentChildren; empty: string; spaced: boolean }) {
  return (
    <div class={`ow-memory__answer${spaced ? ' ow-memory__answer--spaced' : ''}`} data-key="answer">
      {toChildArray(children).length === 0 ? <div class="ow-memory__answer-empty m3-body-medium">{empty}</div> : children}
    </div>
  );
}

function Tile({
  text,
  style,
  onTap,
  placed = false,
  used = false,
  dataKey,
}: {
  text: string;
  style: string;
  onTap: (() => void) | null;

  /** In the answer rather than the bank. */
  placed?: boolean;

  /** A bank tile already placed: its slot stays, emptied. */
  used?: boolean;
  dataKey?: string;
}) {
  return (
    <button
      type="button"
      class={`ow-tile m3-interactive${placed ? ' ow-tile--placed' : ''}${used ? ' ow-tile--used' : ''}`}
      style={style}
      data-key={dataKey}
      disabled={onTap === null}
      aria-hidden={used ? true : undefined}
      onClick={() => onTap?.()}
    >
      {text}
    </button>
  );
}

/** What the check found, and the verse where it was not had. */
function Verdict({
  outcome,
  text,
  style,
  xp,
  bonus,
  combo,
  sureMiss,
  nextWait,
}: {
  outcome: Outcome;
  text: string;
  style: string;
  xp: number;
  bonus: number;
  combo: number;

  /** A miss the reader was sure of: the kind that, corrected now, sticks. */
  sureMiss: boolean;
  nextWait: string;
}) {
  const right = outcome === 'right';
  const heading = outcome === 'right' ? 'Nicely done.' : outcome === 'wrong' ? 'Not quite.' : 'Here it is.';
  return (
    <div class={`ow-verdict${right ? ' ow-verdict--right' : ' ow-verdict--wrong'}`} role="status">
      <div class="ow-verdict__head">
        <Icon name={right ? 'check_circle' : 'replay'} />
        <span class="m3-title-medium ow-verdict__heading">{heading}</span>
        {right && <XpChip xp={xp} />}
      </div>
      {right && bonus > 0 && (
        <div class="m3-label-large ow-verdict__bonus">
          {combo} in a row! +{bonus} XP
        </div>
      )}
      {!right && (
        <div class="ow-verdict__text" style={style}>
          {text}
        </div>
      )}
      {sureMiss && (
        <div class="m3-body-small ow-verdict__sure">
          You were sure of it. A miss like that, once corrected, is the kind that sticks: it comes round again before
          the session ends.
        </div>
      )}
      <div class="m3-body-small">{nextWait}</div>
    </div>
  );
}

/**
 * Meeting a verse before it is built: read over, in the voice where
 * there is one; set in its chapter; and given the reader's own word for
 * what it is about, which is theirs to keep and is shown back whenever
 * the verse is asked for bare. Meaning first: a verse understood is a
 * verse that stays.
 */
function Meet({
  session,
  reference,
  context,
}: {
  session: MemorySession;
  reference: Reference;

  /** Where the verse sits: its heading and chapter. */
  context: string;
}) {
  const scripture = scriptureBodyStyle(session.settings);
  return (
    <div class="ow-memory__page">
      <div class="ow-memory__head">
        <div class="ow-memory__head-text">
          <div class="m3-headline-small">{reference.label}</div>
          <div class="m3-body-medium ow-muted">{context}</div>
        </div>
        {session.canListen && <SpeakButtons speaking={session.speaking} onSpeak={() => session.speak()} onSpeakSlowly={() => session.speak(true)} />}
      </div>
      <div class="ow-memory__task">
        <div class="m3-title-medium">Meet the verse</div>
        <div class="m3-body-medium ow-muted">
          Read it over, aloud if you can. Then say in a word what it is about: that word is yours, and it is what you
          will be given when the verse is asked for from memory.
        </div>
      </div>
      <Card>
        <div style={scripture}>{session.whole}</div>
      </Card>
      <div class="ow-memory__hook-field">
        <TextField
          name="hook"
          value={session.hook}
          onInput={(value) => session.setHook(value)}
          onSubmit={() => session.finishMeeting()}
          label="In a word, what is it about?"
          placeholder="light, trust, rest…"
          maxLength={24}
          autocomplete="off"
          enterKeyHint="go"
        />
      </div>
      <FilledButton class="ow-memory__continue" icon="arrow_forward" onClick={() => session.finishMeeting()}>
        Build it
      </FilledButton>
    </div>
  );
}

/** The trial's one question after a first recall. */
function SleptQuestion({ answer, onAnswer }: { answer: boolean | null; onAnswer: (slept: boolean) => void }) {
  return (
    <div class="ow-slept" data-key="slept">
      <div class="m3-title-small">Have you slept since you learnt this verse?</div>
      <div class="ow-memory__chips" role="radiogroup">
        <Chip variant="choice" label="Yes, I slept" selected={answer === true} onClick={() => onAnswer(true)} />
        <Chip variant="choice" label="Not yet" selected={answer === false} onClick={() => onAnswer(false)} />
      </div>
    </div>
  );
}

function NoText({ reference, onSkip }: { reference: Reference; onSkip: () => void }) {
  return (
    <div class="ow-memory__centre">
      <div class="m3-title-large">{reference.label}</div>
      <div class="m3-body-medium ow-muted">This translation has no text for this verse, so it is left for another.</div>
      <FilledButton onClick={onSkip}>Continue</FilledButton>
    </div>
  );
}

/**
 * The end of a session, or a session with nothing in it: what it
 * earned, how it went, the streak, and anything won along the way.
 */
function Finished({
  total,
  reading,
  xp = 0,
  right = 0,
  answered = 0,
  bestCombo = 0,
  won = [],
  goalMetNow = false,
  levelledUp = false,
}: {
  total: number;
  reading: ReadingStore;
  xp?: number;
  right?: number;
  answered?: number;
  bestCombo?: number;
  won?: readonly Achievement[];

  /** Whether this session is what met today's goal. */
  goalMetNow?: boolean;
  levelledUp?: boolean;
}) {
  const overlay = useOverlay();
  const celebrate = goalMetNow || levelledUp || won.length > 0;
  const verses = reading.memoryVerses;
  const today = reading.today;
  let next: MemoryVerse | null = null;
  for (const verse of verses) {
    if (verse.isDueOn(today)) continue;
    if (next === null || verse.due.getTime() < next.due.getTime()) next = verse;
  }
  const nextLine = (verse: MemoryVerse): string => {
    const days = verse.daysUntilDueOn(today);
    const when = days <= 1 ? 'tomorrow' : `in ${days} days`;
    return `Next up: ${verse.reference.label}, ${when}.`;
  };
  let heading: string;
  let detail: string;
  if (verses.length === 0) {
    heading = 'Nothing to practise yet';
    detail = 'Tap a verse while reading and choose Memorise.';
  } else if (total === 0) {
    heading = 'Nothing due today';
    detail = next === null ? '' : nextLine(next);
  } else {
    heading = total === 1 ? 'That’s the verse for today' : `That’s all ${total} for today`;
    detail = next === null ? '' : nextLine(next);
  }
  const streak = reading.streak.currentOn(today);
  const progress = reading.progress;
  return (
    <Confetti play={celebrate}>
      <div class="ow-memory__page ow-memory__finished">
        <Icon name="psychology" size={56} class="m3-primary ow-memory__finished-icon" />
        <div class="m3-title-large ow-centre">{heading}</div>
        {detail.length > 0 && <div class="m3-body-medium ow-muted ow-centre">{detail}</div>}
        {answered > 0 && (
          <div class="ow-learn-stats">
            <StatTile dataKey="stat/xp" label="Earned" value={`+${xp} XP`} icon="bolt" />
            <StatTile label="Right" value={`${right} of ${answered}`} icon="check_circle_outline" />
            <StatTile label="Best run" value={bestCombo === 0 ? '—' : `${bestCombo} in a row`} icon="trending_up" />
          </div>
        )}
        {goalMetNow && <GoodNews icon="emoji_events" text={`Today’s goal met: ${progress.goal.xp} XP.`} />}
        {levelledUp && <GoodNews icon="star" text={`Level ${progress.level}!`} />}
        {won.map((badge) => (
          <BadgeWon key={badge.id} badge={badge} />
        ))}
        {streak > 0 && (
          <div class="ow-centre ow-memory__streak">
            <StreakBadge days={streak} large />
          </div>
        )}
        <FilledButton class="ow-memory__done" onClick={() => overlay.close()}>
          Done
        </FilledButton>
      </div>
    </Confetti>
  );
}

/** A badge just won, with what won it. */
export function BadgeWon({ badge }: { badge: Achievement }) {
  return (
    <div class="ow-badge-won">
      <AchievementIcon achievement={badge} won />
      <div class="ow-badge-won__text">
        <div class="m3-title-small">Badge won: {badge.title}</div>
        <div class="m3-body-small ow-muted">{badge.description}</div>
      </div>
    </div>
  );
}

/** A number worth a glance, with its name under it. */
export function StatTile({ label, value, icon, dataKey }: { label: string; value: string; icon: string; dataKey?: string }) {
  return (
    <div class="ow-learn-stat" data-key={dataKey}>
      <Icon name={icon} class="m3-primary" />
      <div class="m3-title-small ow-learn-stat__value">{value}</div>
      <div class="m3-label-small ow-muted">{label}</div>
    </div>
  );
}

/** A line of good news, set apart. */
export function GoodNews({ icon, text }: { icon: string; text: string }) {
  return (
    <div class="ow-good-news">
      <Icon name={icon} />
      <span class="m3-title-small">{text}</span>
    </div>
  );
}

/** Points earned, as a small chip. */
export function XpChip({ xp }: { xp: number }) {
  return <span class="ow-xp-chip m3-label-large">+{xp} XP</span>;
}

/** A flame and a count: the days in a row with learning done. */
export function StreakBadge({ days, large = false }: { days: number; large?: boolean }) {
  const label = days === 1 ? '1-day streak' : `${days}-day streak`;
  return (
    <span class={`ow-streak-badge${large ? ' ow-streak-badge--large m3-title-medium' : ' m3-label-large'}`}>
      <Icon name="local_fire_department" size={large ? 24 : 18} />
      {label}
    </span>
  );
}

/**
 * The speaker and its slower twin, as a language app has them: hear
 * it, and hear it slowly.
 */
export function SpeakButtons({ speaking, onSpeak, onSpeakSlowly }: { speaking: boolean; onSpeak: () => void; onSpeakSlowly: () => void }) {
  return (
    <span class="ow-speak-buttons">
      <IconButton variant="tonal" selected={speaking} icon={speaking ? 'stop' : 'volume_up'} label={speaking ? 'Stop' : 'Hear the verse'} onClick={onSpeak} />
      <IconButton variant="outlined" icon="slow_motion_video" label="Hear it slowly" onClick={onSpeakSlowly} />
    </span>
  );
}

/** Switches whether the learning screens speak of their own accord. */
export function AutoSpeakButton() {
  const { settings } = useAppScope();
  useNotifier(settings);
  const on = settings.learnAutoSpeak;
  return (
    <IconButton
      icon={on ? 'volume_up_outlined' : 'volume_off_outlined'}
      label={on ? 'Reading aloud: on' : 'Reading aloud: off'}
      onClick={() => {
        settings.learnAutoSpeak = !on;
      }}
    />
  );
}

/** How a verse's due date reads in a list, today being `today`. */
export function memoryDueLabel(verse: MemoryVerse, today: Date): string {
  const days = verse.daysUntilDueOn(today);
  if (days <= 0) return 'Due today';
  if (days === 1) return 'Tomorrow';
  return `In ${days} days`;
}
