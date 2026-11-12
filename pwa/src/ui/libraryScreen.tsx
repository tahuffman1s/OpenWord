import { useRef, useState } from 'preact/hooks';
import { useAppScope } from '../app/scope';
import type { Mark, ReadingStore } from '../data/marks';
import { useNotifier } from '../infra/changeNotifier';
import type { Bible, Reference } from '../model/bible';
import { Confidence, confidenceLabel, confidenceValues } from '../model/learnProgress';
import { SleepMode, SleepTrialReport } from '../model/sleepPolicy';
import { LearnProgressCard } from './learnProgressCard';
import { LearnTab } from './learnTab';
import { AppBar, Divider, Icon, ListTile, OutlinedButton, Screen, SegmentedButton, Tabs, highlightSwatch, showSnackBar, useOverlay } from './m3';
import { FriendStreaksCard } from './optionalSocial';
import { openInReader } from './readerNav';
import { Dismissible } from './widgets/dismissible';
import './shared.css';
import './libraryScreen.css';

/**
 * Whether the library has something waiting: a verse to practise now. What
 * the reader's library button carries a dot for (`reading.hasMemoryDue`
 * in the Dart; the plan button's dot is `reading.hasPlanReadingDue`).
 */
export function hasSomethingDue(reading: ReadingStore): boolean {
  return reading.hasMemoryDue;
}

const tabs = [
  { value: 0, label: 'Learn', icon: 'school' },
  { value: 1, label: 'Progress', icon: 'insights' },
  { value: 2, label: 'Saved', icon: 'bookmarks' },
];

/**
 * Learning first, then the rest: a Learn tab with today's lesson, the
 * verses being learnt and the rounds; a Progress tab with the level,
 * the week and the badges; and Saved, where bookmarks, highlights,
 * notes and the chapters read lately live. A reference chosen is opened
 * in the reader, and the library closes with it.
 */
export function LibraryScreen({
  initialTab = 0,
}: {
  /** The tab to open on: Learn, Progress or Saved. */
  initialTab?: number;
}) {
  const scope = useAppScope();
  const overlay = useOverlay();
  const reading = scope.reading;
  useNotifier(reading, scope.library);
  const bible = scope.library.bible;
  const [tab, setTab] = useState(Math.min(Math.max(initialTab, 0), 2));
  const touch = useRef<{ x: number; y: number; blocked: boolean } | null>(null);

  const open = (reference: Reference): void => {
    overlay.close(reference);
    openInReader(reference);
  };

  // A swipe across the page turns to the tab beside it, as a TabBarView
  // does — unless it began on a row that is itself swiped away.
  const onTouchStart = (event: TouchEvent): void => {
    const point = event.touches[0];
    const target = event.target as Element | null;
    touch.current = {
      x: point.clientX,
      y: point.clientY,
      blocked: target?.closest?.('.ow-dismissible, .m3-segmented, .m3-slider, .m3-chip-row--scroll') != null,
    };
  };
  const onTouchEnd = (event: TouchEvent): void => {
    const start = touch.current;
    touch.current = null;
    if (start === null || start.blocked) return;
    const point = event.changedTouches[0];
    const dx = point.clientX - start.x;
    const dy = point.clientY - start.y;
    if (Math.abs(dx) < 72 || Math.abs(dx) < Math.abs(dy) * 2) return;
    setTab((current) => Math.min(Math.max(current + (dx < 0 ? 1 : -1), 0), 2));
  };

  return (
    <Screen
      class="ow-library"
      appBar={(scrolled) => (
        <>
          <AppBar scrolled={scrolled} title="Library" />
          <Tabs tabs={tabs} selected={tab} onSelect={setTab} />
        </>
      )}
    >
      <div class="ow-library__page" key={tab} onTouchStart={onTouchStart} onTouchEnd={onTouchEnd}>
        {tab === 0 ? <LearnTab reading={reading} bible={bible} onOpen={open} /> : tab === 1 ? <ProgressTab reading={reading} /> : <SavedTab reading={reading} bible={bible} onOpen={open} />}
      </div>
    </Screen>
  );
}

const confidenceIcon: Record<Confidence, string> = {
  [Confidence.sure]: 'sentiment_very_satisfied',
  [Confidence.fairly]: 'sentiment_satisfied',
  [Confidence.guessing]: 'sentiment_neutral',
};

/** Level, the week, badges, and the numbers behind them. */
function ProgressTab({ reading }: { reading: ReadingStore }) {
  const progress = reading.progress;
  const streak = reading.streak;
  const report = reading.sleepTrialReport;
  const stats: [string, string][] = [
    ['Points', `${progress.xp} XP`],
    ['Level', `${progress.level}`],
    ['Verses learning', `${reading.memoryVerses.length}`],
    ['Verses learnt', `${reading.versesLearnt}`],
    ['Right answers', `${progress.right}`],
    ['Best streak', `${streak.best} ${streak.best === 1 ? 'day' : 'days'}`],
    ['Perfect rounds', `${progress.perfectRounds}`],
    ['Streak freezes', `${streak.freezes}`],
    ['Sure, and wrong', `${progress.confidentMisses}`],
  ];
  const calibration: { level: Confidence; rate: number; asked: number }[] = [];
  for (const level of confidenceValues) {
    const rate = progress.calibration(level);
    if (rate !== null) calibration.push({ level, rate, asked: progress.confidence.get(level)![0] });
  }
  return (
    <div class="ow-progress ow-content">
      <LearnProgressCard reading={reading} />
      <FriendStreaksCard />
      <div class="m3-title-medium ow-progress__heading">Your memory</div>
      <div class="m3-body-small ow-muted ow-progress__text">{progress.keeping}</div>
      <div class="m3-title-medium ow-progress__heading ow-progress__heading--roomy">Sleeping on it</div>
      <div class="ow-progress__inset">
        <TrialCard report={report} reading={reading} />
      </div>
      {calibration.length > 0 && (
        <>
          <div class="m3-title-medium ow-progress__heading">How well you know what you know</div>
          <div class="m3-body-small ow-muted ow-progress__text ow-progress__text--roomy">
            When answering from memory, how often you were right at each degree of sureness. A sure miss is the one most
            worth a second look.
          </div>
          {calibration.map(({ level, rate, asked }) => (
            <ListTile
              key={level}
              static
              dense
              leading={<Icon name={confidenceIcon[level]} class="m3-primary" />}
              title={confidenceLabel[level]}
              subtitle={`Right ${Math.round(rate * 100)}% of the time, ${asked} ${asked === 1 ? 'answer' : 'answers'}`}
            />
          ))}
        </>
      )}
      <div class="m3-title-medium ow-progress__heading ow-progress__heading--roomy">In numbers</div>
      <div class="ow-progress__numbers">
        {stats.map(([label, value]) => (
          <div class="ow-number" key={label}>
            <div class="m3-title-medium ow-number__value">{value}</div>
            <div class="m3-label-small ow-muted">{label}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

/** What the sleep trial has found, or how far it has to go. */
function TrialCard({ report, reading }: { report: SleepTrialReport; reading: ReadingStore }) {
  const policy = reading.sleepPolicy;
  let line: string;
  if (report.hasEnough) {
    const slept = Math.round(report.sleptRate * 100);
    const awake = Math.round(report.awakeRate * 100);
    const later = report.hasLater
      ? ` A week on, ${Math.round(report.sleptLaterRate * 100)}% against ${Math.round(report.awakeLaterRate * 100)}%.`
      : '';
    line =
      `For you, verses slept on were recalled right the first time ${slept}% of the time (${report.sleptAsked} verses), ` +
      `against ${awake}% for verses asked the same day (${report.awakeAsked}).${later}`;
  } else if (policy.mode === SleepMode.off) {
    line = 'Switched off. Turn it on in Settings to time new verses against sleep and see whether it helps you.';
  } else {
    line =
      `Too soon to say: ${report.sleptAsked} of ${SleepTrialReport.minimum} verses slept on, ` +
      `${report.awakeAsked} of ${SleepTrialReport.minimum} asked the same day. Keep learning; the answer comes.`;
  }
  return (
    <div class="ow-trial" data-key="trial">
      <Icon name="bedtime" class="m3-primary" />
      <div class="m3-body-medium ow-trial__text">{line}</div>
    </div>
  );
}

type Saved = 'bookmarks' | 'highlights' | 'notes' | 'recent';

/**
 * Bookmarks, highlights, notes and recent chapters behind one row of
 * choices, one list at a time.
 */
function SavedTab({ reading, bible, onOpen }: { reading: ReadingStore; bible: Bible | null; onOpen: (reference: Reference) => void }) {
  const [showing, setShowing] = useState<Saved>('bookmarks');
  return (
    <div class="ow-saved ow-content">
      <div class="ow-saved__choices">
        <SegmentedButton<Saved>
          class="ow-saved__segments"
          options={[
            { value: 'bookmarks', label: 'Bookmarks', icon: 'bookmark' },
            { value: 'highlights', label: 'Highlights', icon: 'format_color_fill' },
            { value: 'notes', label: 'Notes', icon: 'sticky_note_2' },
            { value: 'recent', label: 'Recent', icon: 'history' },
          ]}
          selected={showing}
          onSelect={setShowing}
        />
      </div>
      {showing === 'bookmarks' ? (
        <MarkList marks={reading.bookmarks} bible={bible} reading={reading} emptyMessage="Tap a verse while reading to bookmark it." onOpen={onOpen} />
      ) : showing === 'highlights' ? (
        <MarkList marks={reading.highlights} bible={bible} reading={reading} emptyMessage="Tap a verse and pick a colour to highlight it." onOpen={onOpen} />
      ) : showing === 'notes' ? (
        <MarkList marks={reading.notes} bible={bible} reading={reading} emptyMessage="Tap a verse and choose Add note." showNotesFirst onOpen={onOpen} />
      ) : (
        <RecentList reading={reading} onOpen={onOpen} />
      )}
    </div>
  );
}

function MarkList({
  marks,
  bible,
  reading,
  emptyMessage,
  showNotesFirst = false,
  onOpen,
}: {
  marks: readonly Mark[];
  bible: Bible | null;
  reading: ReadingStore;
  emptyMessage: string;
  showNotesFirst?: boolean;
  onOpen: (reference: Reference) => void;
}) {
  if (marks.length === 0) {
    return <div class="ow-saved__empty m3-body-large ow-muted">{emptyMessage}</div>;
  }

  const verseText = (mark: Mark): string => {
    const verse = mark.reference.verse;
    if (bible === null || verse === null) return '';
    return bible.bookByCode(mark.reference.bookCode)?.chapter(mark.reference.chapter)?.verseText(verse) ?? '';
  };

  const leading = (mark: Mark) => {
    if (mark.colorIndex !== null) {
      return <span class="ow-saved__swatch" style={`background:${highlightSwatch(mark.colorIndex)}`} />;
    }
    return <Icon name={mark.bookmarked ? 'bookmark' : 'sticky_note_2'} class="m3-primary" />;
  };

  return (
    <div class="ow-saved__list">
      {marks.map((mark, index) => {
        const text = verseText(mark);
        const subtitle = showNotesFirst && mark.hasNote ? mark.note : text.length === 0 ? mark.note : text;
        return (
          <div key={mark.key}>
            {index > 0 && <Divider />}
            <Dismissible
              label={`Remove ${mark.reference.label}`}
              onDismissed={() => {
                reading.remove(mark.reference);
                showSnackBar(`Removed ${mark.reference.label}`);
              }}
            >
              <ListTile
                leading={leading(mark)}
                title={mark.reference.label}
                subtitle={subtitle.length === 0 ? undefined : <span class="ow-clamp-3">{subtitle}</span>}
                trailing={mark.hasNote && !showNotesFirst ? <Icon name="sticky_note_2_outlined" size={18} label="Has a note" /> : undefined}
                onClick={() => onOpen(mark.reference)}
              />
            </Dismissible>
          </div>
        );
      })}
    </div>
  );
}

function RecentList({ reading, onOpen }: { reading: ReadingStore; onOpen: (reference: Reference) => void }) {
  const history = reading.history;
  if (history.length === 0) {
    return <div class="ow-saved__empty m3-body-large ow-muted">Chapters you read will show up here.</div>;
  }
  return (
    <div class="ow-saved__list">
      {history.map((reference) => (
        <ListTile key={reference.key} icon="history" title={reference.label} onClick={() => onOpen(reference)} />
      ))}
      <div class="ow-saved__clear">
        <OutlinedButton icon="delete_sweep" onClick={() => reading.clearHistory()}>
          Clear history
        </OutlinedButton>
      </div>
    </div>
  );
}
