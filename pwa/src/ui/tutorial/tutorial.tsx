import type { ComponentChildren, VNode } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import type { Prefs } from '../../infra/prefs';
import { useNotifier } from '../../infra/changeNotifier';
import { installPrompt, isStandalone } from '../../pwa/install';
import { Button, Icon, TextButton, TonalButton, showSheet, useOverlay } from '../m3';
import { showInstallGuide } from './installGuide';
import './tutorial.css';

/**
 * The walkthrough shown on first launch and from Settings: seven cards,
 * one a feature, each with a picture, a few words and — where the host
 * provides it — a "Try it" that closes the walkthrough and opens the
 * feature. Swipe, the arrow keys, the dots and the buttons all move
 * between cards.
 */
export type TutorialFeature = 'navigator' | 'listen' | 'library' | 'plans' | 'learn' | 'search' | 'friends' | 'settings' | 'install';

/** Called with the feature the reader asked to try, after the walkthrough has closed. */
export type TryHandler = (feature: TutorialFeature) => void;

// ------------------------------------------------------------------ prefs

export const tutorialSeenKey = 'tutorialSeen';

export function hasSeenTutorial(prefs: Prefs): boolean {
  return prefs.getBool(tutorialSeenKey) === true;
}

export function markTutorialSeen(prefs: Prefs): void {
  prefs.setBool(tutorialSeenKey, true);
}

/** For a "show the walkthrough again on next launch" switch. */
export function resetTutorialSeen(prefs: Prefs): void {
  prefs.remove(tutorialSeenKey);
}

// ------------------------------------------------------------------ cards

type Tone = 'primary' | 'secondary' | 'tertiary' | 'error' | 'surface';
type Corner = 'tl' | 'tr' | 'bl' | 'br' | 'l' | 'r' | 't' | 'b';

interface Satellite {
  icon: string;
  tone: Tone;
  at: Corner;
}

interface Art {
  main: string;
  tone: Tone;
  satellites: Satellite[];
  /** A mock of the control the card talks about, under the circles. */
  mock?: VNode;
}

interface CardSpec {
  key: string;
  title: string;
  text: string[];
  art: Art;
  /** The "Try it" button: the feature it opens and its label. */
  tryIt?: { feature: TutorialFeature; label: string };
}

const Blob = ({ tone, cls, children }: { tone: Tone; cls: string; children: ComponentChildren }) => (
  <div class={`ow-tut__blob ow-tut__blob--${tone} ${cls}`}>{children}</div>
);

const wave = (heights: number[]) => (
  <span class="ow-tut__wave" aria-hidden="true">
    {heights.map((h, i) => (
      <i key={i} style={`--h:${h}px`} />
    ))}
  </span>
);

const cards: CardSpec[] = [
  {
    key: 'welcome',
    title: 'Welcome to OpenWord',
    text: [
      'A Bible to read, hear and learn by heart, with three public-domain translations and the Hebrew and Greek behind every verse.',
      'Everything is on your device: it works entirely offline, and nothing about your reading is sent anywhere.',
    ],
    art: {
      main: 'menu_book',
      tone: 'primary',
      satellites: [
        { icon: 'translate', tone: 'secondary', at: 'tl' },
        { icon: 'wifi_off', tone: 'tertiary', at: 'br' },
        { icon: 'lock', tone: 'secondary', at: 'tr' },
      ],
    },
  },
  {
    key: 'reading',
    title: 'Read it like a printed Bible',
    text: [
      'Paragraphs, poetry, headings and the words of Jesus in red, laid out as the translation itself is.',
      'Tap the title to go anywhere — type "jn 3:16", "ps 23" or just "mat" — and swipe between chapters.',
      'Tap a verse for highlights, bookmarks, notes, cross-references, the Hebrew and Greek, and maps.',
    ],
    art: {
      main: 'auto_stories',
      tone: 'primary',
      satellites: [
        { icon: 'bookmark', tone: 'tertiary', at: 'tl' },
        { icon: 'map', tone: 'secondary', at: 'tr' },
        { icon: 'sticky_note_2', tone: 'secondary', at: 'bl' },
        { icon: 'translate', tone: 'tertiary', at: 'br' },
      ],
      mock: (
        <span class="ow-tut__mock ow-tut__mock--field" aria-hidden="true">
          <Icon name="search" />
          jn 3:16
          <span class="ow-tut__caret" />
        </span>
      ),
    },
    tryIt: { feature: 'navigator', label: 'Go somewhere' },
  },
  {
    key: 'listen',
    title: 'Listen',
    text: [
      'A natural voice on the device reads the chapter, with the verse being read kept in view.',
      'It carries on with the screen off; the lock screen, your headphones and the car pause it and step it verse by verse.',
      'Where it got to is kept, down to the word, so Listen becomes Resume.',
    ],
    art: {
      main: 'headphones',
      tone: 'tertiary',
      satellites: [
        { icon: 'volume_up', tone: 'primary', at: 'tl' },
        { icon: 'bedtime', tone: 'secondary', at: 'tr' },
        { icon: 'smartphone', tone: 'secondary', at: 'bl' },
      ],
      mock: (
        <span class="ow-tut__mock ow-tut__mock--player" aria-hidden="true">
          <Icon name="skip_previous" />
          <span class="ow-tut__play">
            <Icon name="pause" />
          </span>
          <Icon name="skip_next" />
          {wave([8, 16, 22, 12, 18, 10, 20, 14])}
          <span class="ow-tut__verse">Ps 23:1</span>
        </span>
      ),
    },
    tryIt: { feature: 'listen', label: 'Hear this chapter' },
  },
  {
    key: 'learn',
    title: 'Learn verses by heart',
    text: [
      'Memorise a verse and it goes on a ladder timed to your memory: asked for today, then after a day, two, five, a month… just before you would forget it.',
      'Practise it with tiles, then blanks, then by typing it out.',
      'Days in a row make a streak with a flame, every seventh day earns a freeze, and points, levels and twelve badges mark the way.',
    ],
    art: {
      main: 'school',
      tone: 'secondary',
      satellites: [
        { icon: 'local_fire_department', tone: 'tertiary', at: 'tr' },
        { icon: 'ac_unit', tone: 'primary', at: 'bl' },
        { icon: 'military_tech', tone: 'tertiary', at: 'br' },
      ],
      mock: (
        <span class="ow-tut__mock-row" aria-hidden="true">
          <span class="ow-tut__tiles">
            <span class="ow-tut__tile ow-tut__tile--placed">For</span>
            <span class="ow-tut__tile ow-tut__tile--placed">God</span>
            <span class="ow-tut__tile ow-tut__tile--blank">so</span>
            <span class="ow-tut__tile">loved</span>
          </span>
          <span class="ow-tut__flame">
            <Icon name="local_fire_department" /> 7
          </span>
        </span>
      ),
    },
    tryIt: { feature: 'learn', label: 'Open today’s lesson' },
  },
  {
    key: 'plans',
    title: 'Plans and quizzes',
    text: [
      'Six reading plans, from the Gospels in 30 days to the whole Bible in a year. Days are numbered, not dated, so a plan waits for you and a missed day is still there tomorrow.',
      'Test yourself with rounds of ten questions drawn from the translation you are reading — which book, how the verse goes on, which book comes next.',
    ],
    art: {
      main: 'event_note',
      tone: 'primary',
      satellites: [
        { icon: 'quiz', tone: 'tertiary', at: 'tr' },
        { icon: 'check_circle', tone: 'secondary', at: 'bl' },
        { icon: 'today', tone: 'secondary', at: 'tl' },
      ],
      mock: (
        <span class="ow-tut__mock" aria-hidden="true">
          <Icon name="check" />
          Done — next: Matthew 2
        </span>
      ),
    },
    tryIt: { feature: 'plans', label: 'See the plans' },
  },
  {
    key: 'friends',
    title: 'Friends',
    text: [
      'An account is optional — everything above works without one.',
      'With one, add friends, keep a streak together and cheer each other’s achievements.',
      'A reminder arrives before a streak breaks.',
    ],
    art: {
      main: 'group',
      tone: 'tertiary',
      satellites: [
        { icon: 'handshake', tone: 'primary', at: 'tl' },
        { icon: 'celebration', tone: 'secondary', at: 'br' },
        { icon: 'notifications', tone: 'secondary', at: 'tr' },
      ],
      mock: (
        <span class="ow-tut__mock-row" aria-hidden="true">
          <span class="ow-tut__avatars">
            <span class="ow-tut__avatar ow-tut__blob--primary">A</span>
            <span class="ow-tut__avatar ow-tut__blob--secondary">R</span>
            <span class="ow-tut__avatar ow-tut__blob--tertiary">M</span>
          </span>
          <span class="ow-tut__flame">
            <Icon name="local_fire_department" /> 12 days together
          </span>
        </span>
      ),
    },
    tryIt: { feature: 'friends', label: 'Open Friends' },
  },
  {
    key: 'install',
    title: 'Put it on your home screen',
    text: [
      'Installed, OpenWord opens full screen from an icon of its own, starts faster, and works with no connection at all.',
      'It takes two taps; the guide shows which ones for your phone or computer.',
    ],
    art: {
      main: 'add_to_home_screen',
      tone: 'primary',
      satellites: [
        { icon: 'wifi_off', tone: 'tertiary', at: 'tl' },
        { icon: 'bolt', tone: 'secondary', at: 'tr' },
        { icon: 'crop_free', tone: 'secondary', at: 'br' },
      ],
      mock: (
        <span class="ow-tut__dock" aria-hidden="true">
          <span class="ow-tut__dock-app" />
          <span class="ow-tut__dock-app" />
          <span class="ow-tut__appicon">
            <img src="/icons/Icon-192.png" alt="" />
          </span>
          <span class="ow-tut__dock-app" />
        </span>
      ),
    },
    tryIt: { feature: 'install', label: 'Show me how' },
  },
];

export const tutorialCardCount = cards.length;

// ------------------------------------------------------------- component

function Illustration({ art }: { art: Art }) {
  return (
    <div class="ow-tut__art-wrap">
      <div class="ow-tut__art" aria-hidden="true">
        <Blob tone={art.tone} cls="ow-tut__art-main">
          <Icon name={art.main} />
        </Blob>
        {art.satellites.map((s) => (
          <Blob key={s.icon + s.at} tone={s.tone} cls={`ow-tut__sat ow-tut__sat--${s.at}`}>
            <Icon name={s.icon} />
          </Blob>
        ))}
      </div>
      {art.mock && <div class="ow-tut__mock-row">{art.mock}</div>}
    </div>
  );
}

export interface TutorialProps {
  /** Opens a feature the reader asked to try; the walkthrough closes first. */
  onTry?: TryHandler;
  /** The card to open on (0-based). */
  initialCard?: number;
}

/** The walkthrough's body; `showTutorial` puts it in a full sheet. */
export function Tutorial({ onTry, initialCard = 0 }: TutorialProps) {
  const overlay = useOverlay();
  useNotifier(installPrompt);
  const [index, setIndex] = useState(Math.min(Math.max(initialCard, 0), cards.length - 1));
  const [drag, setDrag] = useState<{ dx: number; dragging: boolean }>({ dx: 0, dragging: false });
  const rootRef = useRef<HTMLDivElement>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const pointer = useRef<{ id: number; x: number; y: number; t: number; dragging: boolean; dx: number } | null>(null);
  const suppressClick = useRef(false);
  const last = cards.length - 1;
  const installed = installPrompt.installed || isStandalone();

  const go = (to: number) => setIndex(Math.min(Math.max(to, 0), last));

  useEffect(() => {
    rootRef.current?.focus({ preventScroll: true });
  }, []);

  const onKeyDown = (e: KeyboardEvent) => {
    const target = e.target as HTMLElement | null;
    if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return;
    switch (e.key) {
      case 'ArrowRight':
      case 'PageDown':
        go(index + 1);
        break;
      case 'ArrowLeft':
      case 'PageUp':
        go(index - 1);
        break;
      case 'Home':
        go(0);
        break;
      case 'End':
        go(last);
        break;
      default:
        return;
    }
    e.preventDefault();
  };

  // Swipe: horizontal pointer drags move the track with the finger and
  // settle on the nearer card; vertical ones are left to the browser
  // (touch-action: pan-y), which cancels ours when it takes over.
  const onPointerDown = (e: PointerEvent) => {
    if (e.button !== 0 || pointer.current) return;
    pointer.current = { id: e.pointerId, x: e.clientX, y: e.clientY, t: performance.now(), dragging: false, dx: 0 };
  };
  const onPointerMove = (e: PointerEvent) => {
    const p = pointer.current;
    if (!p || e.pointerId !== p.id) return;
    const dx = e.clientX - p.x;
    const dy = e.clientY - p.y;
    if (!p.dragging) {
      if (Math.abs(dx) < 10 || Math.abs(dx) < Math.abs(dy) * 1.2) return;
      p.dragging = true;
      try {
        viewportRef.current?.setPointerCapture(e.pointerId);
      } catch {
        // A pointer that is already gone.
      }
    }
    // Resist at the ends.
    const atEdge = (dx > 0 && index === 0) || (dx < 0 && index === last);
    p.dx = atEdge ? dx / 3 : dx;
    setDrag({ dx: p.dx, dragging: true });
  };
  const endPointer = (e: PointerEvent, cancelled: boolean) => {
    const p = pointer.current;
    if (!p || e.pointerId !== p.id) return;
    pointer.current = null;
    if (!p.dragging) return;
    try {
      viewportRef.current?.releasePointerCapture(e.pointerId);
    } catch {
      // Already released.
    }
    suppressClick.current = true;
    setTimeout(() => (suppressClick.current = false), 0);
    setDrag({ dx: 0, dragging: false });
    if (cancelled) return;
    const width = viewportRef.current?.clientWidth ?? 360;
    const dt = Math.max(1, performance.now() - p.t);
    const velocity = p.dx / dt; // px per ms
    if (p.dx < -width * 0.2 || velocity < -0.4) go(index + 1);
    else if (p.dx > width * 0.2 || velocity > 0.4) go(index - 1);
  };
  const onClickCapture = (e: MouseEvent) => {
    if (!suppressClick.current) return;
    e.stopPropagation();
    e.preventDefault();
  };

  const tryFeature = (feature: TutorialFeature) => {
    if (feature === 'install') {
      void showInstallGuide();
      return;
    }
    overlay.close({ feature } satisfies TutorialResult);
  };

  const card = cards[index];
  const transform = `translateX(calc(${-index * 100}% + ${drag.dx}px))`;

  return (
    <div class="ow-tut" ref={rootRef} tabIndex={-1} onKeyDown={onKeyDown} role="region" aria-roledescription="carousel" aria-label="Welcome to OpenWord">
      <div class="ow-tut__top">
        <span class="ow-tut__brand">
          <Icon name="menu_book" size={20} /> OpenWord
        </span>
        <span class="ow-spacer" />
        {index < last && <TextButton onClick={() => overlay.close()}>Skip</TextButton>}
      </div>
      <div
        class="ow-tut__viewport"
        ref={viewportRef}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={(e) => endPointer(e, false)}
        onPointerCancel={(e) => endPointer(e, true)}
        onClickCapture={onClickCapture}
      >
        <div class={`ow-tut__track${drag.dragging ? ' ow-tut__track--dragging' : ''}`} style={{ transform }}>
          {cards.map((c, i) => {
            const current = i === index;
            const inertAttr = current ? {} : { inert: true };
            const isInstallCard = c.key === 'install';
            return (
              <section
                key={c.key}
                class="ow-tut__card"
                aria-hidden={!current}
                aria-roledescription="slide"
                aria-label={`${i + 1} of ${cards.length}: ${c.title}`}
                {...inertAttr}
              >
                <div class="ow-tut__card-inner">
                  <Illustration art={c.art} />
                  <div class="ow-tut__words">
                    <h2 class="ow-tut__title">{c.title}</h2>
                    {c.text.map((t, j) => (
                      <p class="ow-tut__text" key={j}>
                        {t}
                      </p>
                    ))}
                    {isInstallCard ? (
                      <div class="ow-tut__try">
                        {installed ? (
                          <span class="ow-tut__try-hint">
                            <Icon name="check_circle" size={18} style="vertical-align:-4px;margin-right:4px" />
                            You’re already using the installed app.
                          </span>
                        ) : (
                          <TonalButton icon="add_to_home_screen" onClick={() => tryFeature('install')}>
                            {installPrompt.available ? 'Install OpenWord' : (c.tryIt?.label ?? 'Show me how')}
                          </TonalButton>
                        )}
                      </div>
                    ) : (
                      c.tryIt &&
                      onTry && (
                        <div class="ow-tut__try">
                          <TonalButton icon="arrow_forward" onClick={() => tryFeature(c.tryIt!.feature)}>
                            {c.tryIt.label}
                          </TonalButton>
                        </div>
                      )
                    )}
                  </div>
                </div>
              </section>
            );
          })}
        </div>
      </div>
      <div class="ow-tut__bottom">
        <div class="ow-tut__bottom-side">{index > 0 && <TextButton onClick={() => go(index - 1)}>Back</TextButton>}</div>
        <div class="ow-tut__dots" role="tablist" aria-label="Cards">
          {cards.map((c, i) => (
            <button
              key={c.key}
              type="button"
              role="tab"
              aria-selected={i === index}
              aria-label={`${c.title}, ${i + 1} of ${cards.length}`}
              class={`ow-tut__dot${i === index ? ' ow-tut__dot--on' : ''}`}
              onClick={() => go(i)}
            />
          ))}
        </div>
        <div class="ow-tut__bottom-side ow-tut__bottom-side--end">
          {index < last ? (
            <Button onClick={() => go(index + 1)}>Next</Button>
          ) : (
            <Button icon="check" onClick={() => overlay.close()}>
              Done
            </Button>
          )}
        </div>
      </div>
      <span class="ow-sr-only" aria-live="polite">
        {card.title}
      </span>
    </div>
  );
}

interface TutorialResult {
  feature: TutorialFeature;
}

/**
 * Shows the walkthrough as a full sheet and settles when it is closed. If
 * the reader tapped a "Try it", `onTry` is called with the feature once the
 * sheet has gone and the history has settled, so what it opens stacks
 * cleanly on the reader.
 */
export async function showTutorial(onTry?: TryHandler, options: { initialCard?: number } = {}): Promise<void> {
  const result = await showSheet<TutorialResult>(<Tutorial onTry={onTry} initialCard={options.initialCard} />, { full: true, name: 'tutorial' });
  if (result?.feature && onTry) {
    await historySettled();
    onTry(result.feature);
  }
}

/** Resolves once the back-step that closed the sheet has been seen, or soon anyway. */
function historySettled(): Promise<void> {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      removeEventListener('popstate', finish);
      resolve();
    };
    addEventListener('popstate', finish);
    setTimeout(finish, 150);
  });
}
