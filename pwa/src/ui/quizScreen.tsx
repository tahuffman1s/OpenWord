import { useEffect, useMemo } from 'preact/hooks';
import { useAppScope, type AppScopeValue } from '../app/scope';
import { createSpeechEngine } from '../data/createSpeechEngine';
import { LearnVoice } from '../data/learnVoice';
import { ChangeNotifier, useNotifier } from '../infra/changeNotifier';
import type { Achievement } from '../model/achievements';
import type { Reference } from '../model/bible';
import { Xp } from '../model/learnProgress';
import { QuizKind, QuizMaker, quizBooks, type QuizQuestion } from '../model/quiz';
import { seededRandom } from '../model/random';
import { AppBar, FilledButton, Icon, LinearProgress, ListTile, OutlinedButton, Screen, useOverlay } from './m3';
import { AutoSpeakButton, BadgeWon, GoodNews, SpeakButtons, StatTile, StreakBadge, XpChip } from './memoryScreen';
import { openInReader } from './readerNav';
import { scriptureBodyStyle } from './scriptureStyle';
import { Confetti } from './widgets/confetti';
import './shared.css';
import './quizScreen.css';

export interface QuizScreenProps {
  kind: QuizKind;

  /** Questions in the round. */
  count?: number;

  /**
   * Questions to ask instead of drawing any: a chapter's own, before
   * and after it is read.
   */
  questions?: readonly QuizQuestion[] | null;

  /** What the screen is called, where not the kind. */
  title?: string | null;

  /** Told the score when the round ends. */
  onFinished?: ((right: number, total: number) => void) | null;

  /** Fixes the draw, for a test; the app leaves it to chance. */
  seed?: number | null;
}

/** Questions in a round, unless the caller asks for another number. */
export const questionsPerRound = 10;

function haptic(millis: number): void {
  try {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') navigator.vibrate(millis);
  } catch {
    // Not allowed here, or not there.
  }
}

/** A round's state: the questions, where the round has got to, and what was missed. */
class QuizRound extends ChangeNotifier {
  questions: readonly QuizQuestion[] = [];
  index = 0;
  chosen: number | null = null;
  missed: QuizQuestion[] = [];
  right = 0;

  // The round's tally.
  xp = 0;
  combo = 0;
  lastXp = 0;
  lastBonus = 0;
  perfectBonus = false;
  won: Achievement[] = [];
  goalMetBefore = false;
  levelBefore = 1;

  /** The voice, where there is one. */
  readonly voice: LearnVoice | null = null;

  private closed = false;
  private readonly voiceChanged = (): void => this.notifyListeners();

  constructor(
    private readonly scope: AppScopeValue,
    private readonly props: QuizScreenProps,
  ) {
    super();
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
    this.draw();
    this.speakPrompt();
  }

  get canListen(): boolean {
    return this.voice?.isAvailable ?? false;
  }

  get speaking(): boolean {
    return this.voice?.isSpeaking ?? false;
  }

  get finished(): boolean {
    return this.index >= this.questions.length;
  }

  override dispose(): void {
    this.closed = true;
    this.voice?.removeListener(this.voiceChanged);
    this.voice?.dispose();
    super.dispose();
  }

  /**
   * What the question has to be heard: its Scripture, where it shows
   * any.
   */
  get promptText(): string {
    if (this.index >= this.questions.length) return '';
    const question = this.questions[this.index];
    return question.kind === QuizKind.finishVerse ? question.prompt.substring(0, question.prompt.length - 2) : question.prompt;
  }

  /** The whole verse, once a Finish the verse question is answered. */
  private get answerText(): string {
    const question = this.questions[this.index];
    return question.kind === QuizKind.finishVerse ? `${this.promptText} ${question.correct}` : this.promptText;
  }

  private get autoSpeak(): boolean {
    return this.canListen && this.scope.settings.learnAutoSpeak;
  }

  /** Reads the question's Scripture as it appears, where that is wanted. */
  private speakPrompt(): void {
    if (!this.canListen || !this.scope.settings.learnAutoSpeak) return;
    const text = this.promptText;
    if (text.length === 0) return;
    const index = this.index;
    setTimeout(() => {
      if (!this.closed && index === this.index) void this.voice?.say(text);
    }, 0);
  }

  speak(slow = false): void {
    const voice = this.voice;
    if (voice === null || !this.canListen) return;
    if (voice.isSpeaking && !slow) {
      void voice.stop();
      return;
    }
    const text = this.chosen === null ? this.promptText : this.answerText;
    if (text.length > 0) void voice.say(text, { slow });
  }

  private draw(): void {
    const { scope, props } = this;
    const bible = scope.library.bible;
    this.questions =
      props.questions != null
        ? props.questions
        : bible === null
          ? []
          : new QuizMaker(bible, {
              books: quizBooks(bible, scope.settings.showDeuterocanon),
              random: props.seed == null ? undefined : seededRandom(props.seed),
            }).make(props.kind, props.count ?? questionsPerRound);
    this.index = 0;
    this.chosen = null;
    this.missed = [];
    this.right = 0;
    this.xp = 0;
    this.combo = 0;
    this.lastXp = 0;
    this.lastBonus = 0;
    this.perfectBonus = false;
    this.won = [];
    this.goalMetBefore = scope.reading.progress.goalMetOn(scope.reading.today);
    this.levelBefore = scope.reading.progress.level;
  }

  again(): void {
    this.draw();
    this.speakPrompt();
    this.notifyListeners();
  }

  choose(option: number): void {
    if (this.chosen !== null) return;
    const question = this.questions[this.index];
    const reading = this.scope.reading;
    const right = option === question.answer;
    if (right) {
      this.right++;
      this.combo++;
      this.lastBonus = Xp.comboBonus(this.combo);
      this.lastXp = Xp.quizRight + this.lastBonus;
      haptic(15);
    } else {
      this.missed.push(question);
      this.combo = 0;
      this.lastBonus = 0;
      this.lastXp = 0;
      haptic(30);
    }
    this.xp += this.lastXp;
    this.won.push(...reading.recordLearning({ xp: this.lastXp, right }));
    this.chosen = option;
    this.notifyListeners();
    // Finishing a verse ends with the whole of it heard.
    if (this.autoSpeak && question.kind === QuizKind.finishVerse) {
      void this.voice?.say(this.answerText);
    }
  }

  next(): void {
    this.index++;
    this.chosen = null;
    // A round finished is a day's learning done, and a perfect one earns
    // a bonus on top.
    if (this.index >= this.questions.length) {
      void this.voice?.stop();
      const reading = this.scope.reading;
      if (this.right === this.questions.length) {
        this.perfectBonus = true;
        this.xp += Xp.perfectRound;
        this.won.push(...reading.recordLearning({ xp: Xp.perfectRound, perfectRound: true }));
      } else {
        reading.recordPractice();
      }
      // Friends see a round finished; the account says so where there is one.
      try {
        (this.scope.account as { recordActivity?: (kind: 'quiz') => unknown } | null | undefined)?.recordActivity?.('quiz');
      } catch (error) {
        console.warn(`OpenWord: could not record the round: ${String(error)}`);
      }
      this.props.onFinished?.(this.right, this.questions.length);
    } else {
      this.speakPrompt();
    }
    this.notifyListeners();
  }
}

/**
 * A round of questions drawn from the translation being read. Closes with
 * a reference when the reader asks to open a passage — and sends the
 * reader there — and with nothing otherwise.
 */
export function QuizScreen(props: QuizScreenProps) {
  const scope = useAppScope();
  const overlay = useOverlay();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const round = useMemo(() => new QuizRound(scope, props), []);
  useNotifier(round);
  useEffect(() => () => round.dispose(), [round]);

  const reading = scope.reading;
  const questions = round.questions;
  const finished = round.finished;
  const open = (reference: Reference): void => {
    overlay.close(reference);
    openInReader(reference);
  };
  const canSpeak = round.canListen && round.promptText.length > 0;

  return (
    <Screen
      class="ow-quiz"
      appBar={(scrolled) => (
        <>
          <AppBar scrolled={scrolled} title={props.title ?? props.kind.label} actions={round.canListen ? <AutoSpeakButton /> : null} />
          {questions.length > 0 && <LinearProgress value={(finished ? questions.length : round.index) / questions.length} />}
        </>
      )}
    >
      {questions.length === 0 ? (
        <Empty />
      ) : finished ? (
        <Result
          right={round.right}
          total={questions.length}
          missed={round.missed}
          streak={reading.streak.currentOn(reading.today)}
          xp={round.xp}
          perfectBonus={round.perfectBonus}
          won={round.won}
          goalMetNow={!round.goalMetBefore && reading.progress.goalMetOn(reading.today)}
          levelledUp={reading.progress.level > round.levelBefore}
          onAgain={() => round.again()}
          onOpen={open}
        />
      ) : (
        <Question
          key={round.index}
          question={questions[round.index]}
          number={round.index + 1}
          total={questions.length}
          chosen={round.chosen}
          onChoose={(option) => round.choose(option)}
          onNext={() => round.next()}
          onOpen={open}
          isLast={round.index === questions.length - 1}
          xp={round.lastXp}
          bonus={round.lastBonus}
          combo={round.combo}
          speaking={round.speaking}
          onSpeak={canSpeak ? () => round.speak() : null}
          onSpeakSlowly={canSpeak ? () => round.speak(true) : null}
        />
      )}
    </Screen>
  );
}

function Question({
  question,
  number,
  total,
  chosen,
  onChoose,
  onNext,
  onOpen,
  isLast,
  xp,
  bonus,
  combo,
  speaking,
  onSpeak,
  onSpeakSlowly,
}: {
  question: QuizQuestion;
  number: number;
  total: number;
  chosen: number | null;
  onChoose: (option: number) => void;
  onNext: () => void;
  onOpen: (reference: Reference) => void;
  isLast: boolean;

  /** What the answer earned, the combo bonus within it, and the run. */
  xp: number;
  bonus: number;
  combo: number;
  speaking: boolean;
  onSpeak: (() => void) | null;
  onSpeakSlowly: (() => void) | null;
}) {
  const { settings } = useAppScope();
  const scripture = scriptureBodyStyle(settings);
  const answered = chosen !== null;
  const right = chosen === question.answer;

  return (
    <div class="ow-quiz__page">
      <div class="m3-label-large ow-muted">
        Question {number} of {total}
      </div>
      <div class="ow-quiz__stem">
        <div class="m3-title-large ow-quiz__stem-text">{question.stem}</div>
        {onSpeak !== null && onSpeakSlowly !== null && <SpeakButtons speaking={speaking} onSpeak={onSpeak} onSpeakSlowly={onSpeakSlowly} />}
      </div>
      {question.prompt.length > 0 && (
        <div class="ow-quiz__prompt" style={scripture}>
          {question.prompt}
        </div>
      )}
      <div class="ow-quiz__options">
        {question.options.map((text, i) => (
          <Option
            key={i}
            text={text}
            scripture={question.kind === QuizKind.finishVerse ? scripture : null}
            state={!answered ? 'open' : i === question.answer ? 'right' : i === chosen ? 'wrong' : 'dimmed'}
            onTap={answered ? null : () => onChoose(i)}
          />
        ))}
      </div>
      {answered && (
        <div class="ow-quiz__told">
          <div class="ow-quiz__verdict">
            <span class={`m3-title-medium ${right ? 'm3-primary' : 'm3-error'}`} role="status">
              {right ? 'Right.' : 'Not that one.'}
            </span>
            {right && <XpChip xp={xp} />}
          </div>
          {right && bonus > 0 && (
            <div class="m3-label-large m3-primary">
              {combo} in a row! +{bonus} XP
            </div>
          )}
          <div class="ow-quiz__buttons">
            <OutlinedButton icon="menu_book" class="ow-quiz__passage" onClick={() => onOpen(question.reference)}>
              <span class="ow-ellipsis">{question.reference.label}</span>
            </OutlinedButton>
            <FilledButton icon={isLast ? 'flag' : 'arrow_forward'} onClick={onNext}>
              {isLast ? 'Finish' : 'Next'}
            </FilledButton>
          </div>
        </div>
      )}
    </div>
  );
}

type OptionState = 'open' | 'right' | 'wrong' | 'dimmed';

function Option({
  text,
  state,
  onTap,
  scripture = null,
}: {
  text: string;
  state: OptionState;
  onTap: (() => void) | null;

  /** Set when the option is Scripture and should read in its face. */
  scripture?: string | null;
}) {
  const icon = state === 'right' ? 'check' : state === 'wrong' ? 'close' : null;
  return (
    <button
      type="button"
      class={`ow-option ow-option--${state}${onTap === null ? '' : ' m3-interactive'}`}
      disabled={onTap === null}
      onClick={() => onTap?.()}
    >
      <span class="ow-option__text" style={scripture === null ? undefined : `${scripture};line-height:1.4`}>
        {text}
      </span>
      {icon !== null && <Icon name={icon} class="ow-option__icon" label={state === 'right' ? 'Right' : 'Wrong'} />}
    </button>
  );
}

function Result({
  right,
  total,
  missed,
  streak,
  xp,
  perfectBonus,
  won,
  goalMetNow,
  levelledUp,
  onAgain,
  onOpen,
}: {
  right: number;
  total: number;
  missed: readonly QuizQuestion[];

  /** Days in a row with learning done, this round counted. */
  streak: number;

  /** What the round earned, and whether the perfect bonus is in it. */
  xp: number;
  perfectBonus: boolean;
  won: readonly Achievement[];
  goalMetNow: boolean;
  levelledUp: boolean;
  onAgain: () => void;
  onOpen: (reference: Reference) => void;
}) {
  const { reading } = useAppScope();
  const overlay = useOverlay();
  const celebrate = perfectBonus || goalMetNow || levelledUp || won.length > 0;
  const remark = right === total ? 'Every one.' : right >= total * 0.7 ? 'Well done.' : right >= total * 0.4 ? 'Getting there.' : 'Worth another go.';
  const progress = reading.progress;
  return (
    <Confetti play={celebrate}>
      <div class="ow-quiz__page ow-quiz__result">
        <div class="m3-display-small m3-primary ow-centre ow-quiz__score">
          {right} of {total}
        </div>
        <div class="m3-title-medium ow-centre">{remark}</div>
        <div class="ow-learn-stats ow-quiz__stats">
          <StatTile dataKey="stat/xp" label={perfectBonus ? 'Earned, with bonus' : 'Earned'} value={`+${xp} XP`} icon="bolt" />
          <StatTile label="Right" value={`${Math.round((100 * right) / total)}%`} icon="check_circle_outline" />
        </div>
        {perfectBonus && <GoodNews icon="workspace_premium" text={`Perfect round: +${Xp.perfectRound} XP on top.`} />}
        {goalMetNow && <GoodNews icon="emoji_events" text={`Today’s goal met: ${progress.goal.xp} XP.`} />}
        {levelledUp && <GoodNews icon="star" text={`Level ${progress.level}!`} />}
        {won.map((badge) => (
          <BadgeWon key={badge.id} badge={badge} />
        ))}
        {streak > 0 && (
          <div class="ow-centre ow-quiz__streak">
            <StreakBadge days={streak} large />
          </div>
        )}
        <div class="ow-quiz__buttons ow-quiz__ending">
          <OutlinedButton icon="check" onClick={() => overlay.close()}>
            Done
          </OutlinedButton>
          <FilledButton icon="replay" onClick={onAgain}>
            Again
          </FilledButton>
        </div>
        {missed.length > 0 && (
          <div class="ow-quiz__missed">
            <div class="m3-title-medium">To read again</div>
            <div class="m3-body-medium ow-muted">The ones that got away, each a tap from the passage.</div>
            {missed.map((question) => (
              <ListTile
                class="ow-quiz__missed-tile"
                icon="menu_book"
                title={question.reference.label}
                subtitle={<span class="ow-clamp-2">{question.prompt.length === 0 ? question.stem : `${question.stem} ${question.correct}`}</span>}
                onClick={() => onOpen(question.reference)}
              />
            ))}
          </div>
        )}
      </div>
    </Confetti>
  );
}

function Empty() {
  return <div class="ow-quiz__empty m3-body-large ow-muted">This translation has too little text to ask about.</div>;
}
