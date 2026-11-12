import { useMemo, useState } from 'preact/hooks';
import { openFromTutorial } from '../app/openFlow';
import { useAppScope } from '../app/scope';
import { Atlas } from '../data/atlas';
import { attachStudyLayers, StudyLayers, type AttachedLayers } from '../data/bibExport';
import { BookIntros } from '../data/bookIntros';
import { createSpeechEngine } from '../data/createSpeechEngine';
import { CrossReferences } from '../data/crossReferences';
import type { LibraryController } from '../data/library';
import type { ReadingStore } from '../data/marks';
import { Originals } from '../data/originals';
import type { SpeechEngine, SpeechVoice } from '../data/readAloud';
import { saveBytes } from '../data/saveFile';
import { ReadingFont, readingFontLabel, Settings, ThemeMode } from '../data/settings';
import { Translations } from '../data/translations';
import { voiceAttribution, voiceLicences } from '../data/voiceLicences';
import { useNotifier } from '../infra/changeNotifier';
import { BibFile } from '../model/bibFile';
import { Versification, type TranslationInfo } from '../model/bible';
import { SleepMode } from '../model/sleepPolicy';
import type { AppUpdates } from '../pwa/serviceWorker';
import { historySettled } from './historySettled';
import { useAsync } from './hooks';
import { showImportSheet } from './importSheet';
import {
  AlertDialog,
  AppBar,
  Chip,
  CircularProgress,
  DialogAction,
  FilledButton,
  IconButton,
  LinearProgress,
  ListTile,
  MenuDivider,
  MenuItem,
  PopupMenuButton,
  Screen,
  SegmentedButton,
  Sheet,
  Slider,
  TextButton,
  TextField,
  confirm,
  hexOf,
  nav,
  showDialog,
  showSheet,
  showSnackBar,
  useOverlay,
} from './m3';
import { openSocial } from './optionalSocial';
import { hourLabel, showSleepPolicySheet } from './sleepSheet';
import { showInstallGuide } from './tutorial/installGuide';
import { showTutorial, type TutorialFeature } from './tutorial/tutorial';
import { RadioListTile, SwitchListTile } from './widgets/listTiles';
import './shared.css';
import './settingsScreen.css';

/** "1×", "1.25×": a pace as the player and the voice sheet say it. */
export function rateLabel(rate: number): string {
  return `${rate.toFixed(2).replace(/\.?0+$/, '')}×`;
}

/** Display, reading, translation and backup preferences. */
export function SettingsScreen() {
  const scope = useAppScope();
  const overlay = useOverlay();
  const { settings, library, reading, updates } = scope;
  useNotifier(settings, library, reading, updates, library.shelf);
  // The engine reading aloud would speak with: asked what it can do, and
  // for its voices, never to speak.
  const engine = useMemo(() => createSpeechEngine(), []);
  const language = library.bible?.translation.language ?? 'en';
  const voices = useAsync(() => engine.voices(language).catch(() => [] as SpeechVoice[]), [engine, language]);
  const voiceTitle = chosenVoice(voices.value ?? [], settings.speechVoice);
  const policy = reading.sleepPolicy;

  const tryFeature = async (feature: TutorialFeature): Promise<void> => {
    // The walkthrough was opened from here; what it leads to opens over
    // the reader, not over Settings.
    if (feature === 'settings') return;
    overlay.close();
    await historySettled();
    openFromTutorial(feature);
  };

  return (
    <Screen class="ow-settings" appBar={(scrolled) => <AppBar scrolled={scrolled} title="Settings" />}>
      <div class="ow-settings__page">
        <Header>Theme</Header>
        <ListTile static title="Appearance" subtitle="Light, dark or follow the system" />
        <div class="ow-settings__inset">
          <SegmentedButton<ThemeMode>
            class="ow-settings__segments"
            options={[
              { value: ThemeMode.system, label: 'System', icon: 'brightness_auto' },
              { value: ThemeMode.light, label: 'Light', icon: 'light_mode' },
              { value: ThemeMode.dark, label: 'Dark', icon: 'dark_mode' },
            ]}
            selected={settings.themeMode}
            onSelect={(mode) => {
              settings.themeMode = mode;
            }}
          />
        </div>
        {/* A page has no wallpaper palette to follow, so the seed is always
            the reader's to pick; "Material You colours" is not offered. */}
        <ListTile static title="Colour" subtitle="The colour the whole palette is drawn from" />
        <div class="ow-settings__swatches" role="radiogroup" aria-label="Colour">
          {Settings.seedChoices.map((color) => (
            <button
              type="button"
              role="radio"
              key={color}
              aria-checked={settings.seedColor === color}
              aria-label={`Colour ${hexOf(color)}`}
              class={`ow-seed-swatch m3-interactive${settings.seedColor === color ? ' ow-seed-swatch--selected' : ''}`}
              style={`background:${hexOf(color)}`}
              onClick={() => {
                settings.seedColor = color;
              }}
            />
          ))}
        </div>

        <Header>Reading</Header>
        <ListTile
          static
          title="Typeface"
          trailing={
            <SegmentedButton<ReadingFont>
              options={[ReadingFont.serif, ReadingFont.sans].map((font) => ({ value: font, label: readingFontLabel[font] }))}
              selected={settings.readingFont}
              onSelect={(font) => {
                settings.readingFont = font;
              }}
            />
          }
        />
        <SliderTile
          title="Text size"
          value={settings.fontScale}
          min={0.8}
          max={2.0}
          divisions={12}
          label={`${Math.round(settings.fontScale * 100)}%`}
          onChanged={(value) => {
            settings.fontScale = value;
          }}
        />
        <SliderTile
          title="Line spacing"
          value={settings.lineHeight}
          min={1.2}
          max={2.4}
          divisions={12}
          label={settings.lineHeight.toFixed(1)}
          onChanged={(value) => {
            settings.lineHeight = value;
          }}
        />
        <SwitchListTile
          value={settings.paragraphLayout}
          title="Paragraph layout"
          subtitle="Verses flow together as in a printed Bible"
          onChange={(value) => {
            settings.paragraphLayout = value;
          }}
        />
        <SwitchListTile
          value={settings.showVerseNumbers}
          title="Verse numbers"
          onChange={(value) => {
            settings.showVerseNumbers = value;
          }}
        />
        <SwitchListTile
          value={settings.redLetter}
          title="Words of Jesus in red"
          onChange={(value) => {
            settings.redLetter = value;
          }}
        />
        <SwitchListTile
          value={settings.showFootnotes}
          title="Footnote markers"
          subtitle="Translator notes and cross references"
          onChange={(value) => {
            settings.showFootnotes = value;
          }}
        />
        <SwitchListTile
          value={settings.showDeuterocanon}
          title="Deuterocanonical books"
          subtitle="Include Tobit through 4 Maccabees where the edition has them"
          onChange={(value) => {
            settings.showDeuterocanon = value;
          }}
        />

        {engine.isAvailable && (
          <>
            <Header>Reading aloud</Header>
            <ListTile
              icon="record_voice_over"
              title="Speed and voice"
              subtitle={voiceTitle === null ? rateLabel(settings.speechRate) : `${rateLabel(settings.speechRate)} · ${voiceTitle}`}
              onClick={() => showVoiceSheet({ settings, engine, language })}
            />
          </>
        )}

        <Header>Learning</Header>
        <ListTile
          icon="bedtime_outlined"
          title="Sleep and new verses"
          subtitle={
            policy.mode === SleepMode.trial
              ? `Measuring it: new verses take turns between night and day. Evening from ${hourLabel(policy.eveningStart)}.`
              : policy.mode === SleepMode.nights
                ? 'Nights only: every new verse is learnt in the evening and asked for next morning.'
                : 'Off: new verses are learnt whenever.'
          }
          onClick={() => showSleepPolicySheet(reading)}
        />
        {engine.isAvailable && (
          <SwitchListTile
            value={settings.learnAutoSpeak}
            title="Read aloud in practice"
            subtitle="A verse is spoken as it appears, a tile as it is tapped, and the verse again once an answer is checked. The speaker button works either way."
            onChange={(value) => {
              settings.learnAutoSpeak = value;
            }}
          />
        )}

        <Header>Translation</Header>
        <div role="radiogroup" aria-label="Translation">
          {library.available.map((translation) => {
            const numbersDifferently = !Versification.mayAnchorEnglish(translation.versification);
            return (
              <RadioListTile
                key={translation.id}
                class="ow-settings__translation"
                checked={settings.translationId === translation.id}
                title={translation.name}
                threeLine={numbersDifferently}
                subtitle={
                  <span class="ow-prewrap">
                    {[
                      `${translation.abbreviation} • ${translation.license}`,
                      // Said here as well as at import, so that a reader
                      // who later wonders where the cross-references
                      // went is not left guessing — and, where they have
                      // asked for them regardless, what they asked for.
                      ...(numbersDifferently
                        ? [
                            settings.anchoredAnyway.has(translation.id)
                              ? 'Numbers its verses differently. Cross-references and the Hebrew and Greek are offered anyway, at your word: expect some to be out by a verse or two.'
                              : 'Numbers its verses differently, so cross-references and the Hebrew and Greek are not offered for it.',
                          ]
                        : []),
                    ].join('\n')}
                  </span>
                }
                trailing={<TranslationMenu translation={translation} settings={settings} library={library} />}
                onSelect={() => {
                  if (translation.id === settings.translationId) return;
                  settings.translationId = translation.id;
                  void library.load(translation.id);
                }}
              />
            );
          })}
        </div>
        {library.shelf !== null && (
          <ListTile
            icon="add"
            title="Add a translation"
            subtitle="Import an EPUB of a Bible, or a .bib file"
            onClick={() => showImportSheet({ shelf: library.shelf!, library, settings })}
          />
        )}
        <ListTile
          static
          icon="compare_arrows"
          title="Compare with"
          subtitle={settings.compareTranslationId === null ? 'Off' : library.infoFor(settings.compareTranslationId).name}
          trailing={
            settings.compareTranslationId === null ? undefined : (
              <IconButton
                icon="close"
                label="Stop comparing"
                onClick={() => {
                  settings.compareTranslationId = null;
                }}
              />
            )
          }
        />
        <div class="ow-settings__chips">
          {library.available
            .filter((translation) => translation.id !== settings.translationId)
            .map((translation) => {
              const selected = settings.compareTranslationId === translation.id;
              return (
                <Chip
                  key={translation.id}
                  variant="choice"
                  label={translation.abbreviation}
                  selected={selected}
                  onClick={() => {
                    settings.compareTranslationId = selected ? null : translation.id;
                  }}
                />
              );
            })}
        </div>

        <Header>Bookmarks, highlights and notes</Header>
        <ListTile
          icon="copy_all"
          title="Copy a backup"
          subtitle={`${reading.all.length} ${reading.all.length === 1 ? 'entry' : 'entries'}${reading.plans.length === 0 ? '' : ' and your reading plans'} as JSON on the clipboard`}
          disabled={!reading.hasBackupContent}
          onClick={() => void copyBackup(reading)}
        />
        <ListTile icon="content_paste" title="Restore from the clipboard" subtitle="Merges a backup in; nothing already here is lost" onClick={() => void restore(reading)} />
        <ListTile
          class="ow-settings__danger"
          icon="delete_outline"
          title="Remove everything"
          disabled={reading.all.length === 0 && reading.memoryVerses.length === 0}
          onClick={() => void confirmClear(reading)}
        />

        <Header>Friends</Header>
        <ListTile icon="group" title="Friends & account" subtitle="Sign in, find friends, and keep your streak where they can see it" onClick={() => openSocial('account')} />

        <Header>Help</Header>
        <ListTile icon="help_outline" title="Show the tutorial again" subtitle="A short walk through what the app does" onClick={() => void showTutorial((feature) => void tryFeature(feature))} />
        <ListTile icon="install_mobile" title="Install the app" subtitle="Put OpenWord on your home screen, to open like any other app" onClick={() => void showInstallGuide()} />

        <Header>Updates</Header>
        <UpdateRow updates={updates} />

        <Header>About</Header>
        <ListTile
          static
          threeLine
          icon="auto_stories"
          title="OpenWord"
          // The version is shown under Updates, where it is useful.
          subtitle="A free and open source Bible reader. The translations, the introductions, the maps, the cross-references and the Hebrew and Greek are all bundled, so reading needs no connection."
        />
        {/* Everything readable, not only what shipped: a translation
            the reader imported may carry wording its licence obliges
            the app to show, and a file that says so is no use if
            nothing reads it out. */}
        {library.available.map((translation) => (
          <ListTile
            key={translation.id}
            static
            dense
            title={translation.name}
            subtitle={
              translation.attribution.length > 0
                ? translation.attribution
                : [translation.license, translation.sourceUrl].filter((part) => part.length > 0).join(' • ')
            }
          />
        ))}
        <ListTile static dense title="Book introductions" subtitle={BookIntros.attribution} />
        <ListTile static dense title="Maps" subtitle={Atlas.attribution} />
        <ListTile static dense title="Cross-references" subtitle={CrossReferences.attribution} />
        <ListTile static dense title="Hebrew, Greek and Strong's" subtitle={Originals.attribution} />
        <ListTile static dense title="Literata, Noto Serif, Noto Serif Hebrew" subtitle="SIL Open Font License 1.1" />
        <ListTile static dense title="Reading aloud" subtitle={voiceAttribution} />
        {/* Every licence in full: the voice's, the fonts' and the app's own. */}
        <ListTile icon="gavel" title="Licences" subtitle="The full text of every licence" onClick={() => void nav.push(<LicencesScreen />)} />
      </div>
    </Screen>
  );
}

/** What the voice chosen is called, or the first where the choice means none. */
function chosenVoice(voices: readonly SpeechVoice[], kept: string | null): string | null {
  const voice = voices.find((v) => v.name === kept) ?? voices[0];
  return voice === undefined ? null : (voice.title ?? voice.name);
}

/** The backup on the clipboard, or shown to be copied by hand where the browser will not. */
async function copyBackup(reading: ReadingStore): Promise<void> {
  const text = reading.export();
  if (await copyText(text)) {
    showSnackBar('Backup copied to the clipboard');
    return;
  }
  await showDialog<void>(
    <AlertDialog title="Copy your backup" actions={<DialogAction>Done</DialogAction>}>
      <p class="ow-settings__dialog-text">This browser would not put it on the clipboard. Select all of it and copy it from here.</p>
      <textarea class="ow-settings__backup" readOnly value={text} rows={10} onFocus={(event) => (event.currentTarget as HTMLTextAreaElement).select()} />
    </AlertDialog>,
  );
}

/** Puts `text` on the clipboard: the clipboard API, or a hidden text area and the old command. */
export async function copyText(text: string): Promise<boolean> {
  try {
    if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText !== undefined) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // Refused: try the old way.
  }
  try {
    const area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    const copied = document.execCommand('copy');
    area.remove();
    return copied;
  } catch {
    return false;
  }
}

/** What is on the clipboard, or null where the browser will not say. */
async function readClipboard(): Promise<string | null> {
  try {
    if (typeof navigator !== 'undefined' && navigator.clipboard?.readText !== undefined) {
      return await navigator.clipboard.readText();
    }
  } catch {
    // Refused, or not allowed without asking.
  }
  return null;
}

async function restore(reading: ReadingStore): Promise<void> {
  let text = await readClipboard();
  if (text === null) {
    // No reading the clipboard here: the backup is pasted in instead.
    const pasted = await showDialog<string>(<PasteDialog />);
    if (pasted === undefined) return;
    text = pasted;
  }
  if (text.trim().length === 0) {
    showSnackBar('The clipboard is empty');
    return;
  }
  const result = reading.import(text);
  showSnackBar(result.ok ? `Restored ${result.added} new and updated ${result.updated}` : 'That does not look like an OpenWord backup');
}

function PasteDialog() {
  const overlay = useOverlay();
  const [text, setText] = useState('');
  return (
    <AlertDialog
      title="Restore a backup"
      actions={
        <>
          <DialogAction>Cancel</DialogAction>
          <TextButton disabled={text.trim().length === 0} onClick={() => overlay.close(text)}>
            Restore
          </TextButton>
        </>
      }
    >
      <p class="ow-settings__dialog-text">This browser does not let a page read the clipboard. Paste your backup here.</p>
      <TextField value={text} onInput={setText} multiline rows={8} placeholder="Paste the backup" autoFocus name="backup" />
    </AlertDialog>
  );
}

async function confirmClear(reading: ReadingStore): Promise<void> {
  const confirmed = await confirm({
    title: 'Remove everything?',
    body: 'Bookmarks, highlights, notes and the verses being memorised will all be deleted. This cannot be undone.',
    confirmLabel: 'Remove',
    destructive: true,
  });
  if (confirmed) reading.clearAll();
}

function Header({ children }: { children: string }) {
  return <div class="ow-settings__header m3-label-large">{children}</div>;
}

function SliderTile({
  title,
  value,
  min,
  max,
  divisions,
  label,
  onChanged,
}: {
  title: string;
  value: number;
  min: number;
  max: number;
  divisions: number;
  label: string;
  onChanged: (value: number) => void;
}) {
  const step = (max - min) / divisions;
  // Kept to the divisions exactly: a slider's arithmetic leaves 1.2000000000000002.
  const snap = (raw: number): number => Number((min + Math.round((raw - min) / step) * step).toFixed(4));
  return (
    <div class="ow-slider-tile">
      <div class="ow-slider-tile__head">
        <span class="m3-body-large">{title}</span>
        <span class="m3-label-large">{label}</span>
      </div>
      <Slider value={Math.min(Math.max(value, min), max)} min={min} max={max} step={Number(step.toFixed(4))} label={title} onChange={(raw) => onChanged(snap(raw))} />
    </div>
  );
}

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** "Built 5 November 2026", or nothing where the build did not say. */
function builtLine(builtAt: string): string {
  const at = new Date(builtAt);
  if (builtAt.length === 0 || Number.isNaN(at.getTime())) return builtAt === 'dev' ? 'A development build.' : '';
  return `Built ${at.getDate()} ${monthNames[at.getMonth()]} ${at.getFullYear()}.`;
}

/**
 * The state of the app's own updating: which build is running, whether a
 * newer one is waiting, and the button that goes and looks.
 *
 * In the Flutter app this asked GitHub for a release to download; a web
 * app is updated by its service worker, which fetches the new build in the
 * background and waits to be let in.
 */
function UpdateRow({ updates }: { updates: AppUpdates }) {
  const [looked, setLooked] = useState(false);
  const version = updates.version;
  const title = version === null ? 'OpenWord' : `Version ${version.version}`;
  const built = version === null ? '' : `${builtLine(version.builtAt)}${version.commit ? ` Commit ${version.commit}.` : ''} `;
  const subtitle = updates.checking
    ? 'Checking for a newer version…'
    : updates.updateAvailable
      ? 'A newer version is ready. Reload to switch to it.'
      : !updates.supported
        ? `${built}Updates arrive when the page is reloaded.`.trim()
        : looked
          ? 'This is the newest version.'
          : `${built}${updates.offlineReady ? 'Ready to read offline.' : 'Checks for a newer version by itself.'}`.trim();
  return (
    <ListTile
      static
      icon="system_update"
      title={title}
      subtitle={subtitle}
      trailing={
        updates.checking ? (
          <CircularProgress size={24} />
        ) : updates.updateAvailable ? (
          <FilledButton onClick={() => updates.applyUpdate()}>Reload</FilledButton>
        ) : (
          <TextButton
            disabled={!updates.supported}
            onClick={() => {
              void updates.checkNow().then(() => setLooked(true));
            }}
          >
            Check for updates
          </TextButton>
        )
      }
    />
  );
}

/** How fast, and in whose voice. */
export function showVoiceSheet(options: { settings: Settings; engine: SpeechEngine; language: string }): Promise<void> {
  return showSheet<void>(<VoiceSheet {...options} />, { name: 'voice' }).then(() => undefined);
}

function VoiceSheet({ settings, engine, language }: { settings: Settings; engine: SpeechEngine; language: string }) {
  useNotifier(settings);
  const voices = useAsync(() => engine.voices(language).catch(() => [] as SpeechVoice[]), [engine, language]);
  const list = voices.value ?? [];
  // A voice kept from an earlier version, or none: the first is the
  // one heard.
  const chosen = list.some((v) => v.name === settings.speechVoice) ? settings.speechVoice : (list[0]?.name ?? null);
  return (
    <Sheet>
      <div class="ow-voice">
        <div class="m3-title-medium">Speed</div>
        <div class="ow-voice__rates" role="radiogroup" aria-label="Speed">
          {Settings.speechRates.map((rate) => (
            <Chip
              key={rate}
              variant="choice"
              label={rateLabel(rate)}
              selected={settings.speechRate === rate}
              onClick={() => {
                settings.speechRate = rate;
              }}
            />
          ))}
        </div>
        <div class="m3-title-medium ow-voice__heading">Voice</div>
      </div>
      {voices.loading ? (
        <div class="ow-voice__loading">
          <LinearProgress />
        </div>
      ) : (
        <div role="radiogroup" aria-label="Voice">
          {list.map((voice) => (
            <RadioListTile
              key={voice.name}
              class="ow-voice__tile"
              checked={voice.name === chosen}
              title={voice.title ?? voice.name}
              subtitle={voice.locale}
              onSelect={() => {
                settings.speechVoice = voice.name;
              }}
            />
          ))}
        </div>
      )}
      <div class="m3-body-small ow-muted ow-voice__note">
        The first voices are OpenWord’s own: KittenTTS (Apache-2.0), made on this device with ONNX Runtime. Nothing
        leaves it. Any after them are this device’s, spoken by the browser.
      </div>
    </Sheet>
  );
}

/**
 * What can be done with a translation: keep a copy of the `.bib`, and —
 * where the reader brought it themselves — take it off the shelf again.
 *
 * Saving works for the three that ship as well as for an import. A format
 * only one app can write is that app's cache; one any of them can hand to
 * the next is a format, and there is no reason the bundled three should be
 * the ones nobody can get out.
 */
function TranslationMenu({ translation, settings, library }: { translation: TranslationInfo; settings: Settings; library: LibraryController }) {
  const id = translation.id;
  const name = translation.name;
  const imported = library.isImported(id);
  const shelved = library.shelf?.byId(id) ?? null;

  /** The `.bib` itself, wherever it lives. */
  const bytes = async (): Promise<Uint8Array | null> => {
    if (imported) return (await library.shelf?.fileBytes(id)) ?? null;
    return library.bundle.load(Translations.assetFor(id));
  };

  // Each message replaces the one before it — the snackbar host hides
  // what is showing for what comes next — so the outcome does not wait
  // behind "Looking through…" for as long as that takes to time out,
  // which would read as nothing having happened.
  const say = (message: string): void => showSnackBar(message);

  /**
   * Takes an edition's furniture out of a translation already on the
   * shelf — the navigation it prints around every book, which used to be
   * read as the last verse of whichever book it followed.
   *
   * This exists because an import is a stored file and updating the app
   * never touches it: a translation imported before a fix keeps the fault
   * for ever, and re-importing needs the EPUB, which the app did not
   * keep. What this looks for needs no EPUB.
   *
   * Nothing is written until the reader has seen what would go. It is
   * their Bible, and a rule with a threshold in it should show its work.
   */
  const tidy = async (): Promise<void> => {
    const shelf = library.shelf;
    if (shelf === null) return;

    say(`Looking through ${name}…`);

    const found = await shelf.tidy(id);
    if (found.failure !== null) {
      say(`Could not read ${name}: ${found.failure}`);
      return;
    }
    if (!found.foundSomething) {
      say(`Nothing in ${name} repeats around every book.`);
      return;
    }

    const lines = found.removed;
    const agreed = await showDialog<boolean>(
      <AlertDialog
        title={`Tidy up ${name}?`}
        actions={
          <>
            <DialogAction result={false}>Leave it</DialogAction>
            <DialogAction result={true}>Take them out</DialogAction>
          </>
        }
      >
        <p class="ow-settings__dialog-text">
          {lines.length === 1
            ? 'This line belongs to no verse and appears in three or more books, so it is the edition’s own furniture rather than Scripture:'
            : `These ${lines.length} lines belong to no verse and each appears in three or more books, so they are the edition’s own furniture rather than Scripture:`}
        </p>
        {lines.slice(0, 12).map((line) => (
          <div class="m3-body-small ow-clamp-2 ow-settings__tidy-line">· {line}</div>
        ))}
        {lines.length > 12 && <div class="m3-body-small">and {lines.length - 12} more</div>}
      </AlertDialog>,
    );
    if (agreed !== true) return;

    const written = await shelf.replace(id, found.bytes!);
    if (!written) {
      say(`Could not rewrite ${name}.`);
      return;
    }
    // Whatever is open is now the old copy; read the new one.
    if (settings.translationId === id) await library.load(id);
    if (settings.compareTranslationId === id) {
      // loadComparison answers at once when the id is already loaded, so
      // the stale copy has to go first.
      library.clearComparison();
      await library.loadComparison(id);
    }
    say(`Took ${lines.length} ${lines.length === 1 ? 'line' : 'lines'} out of ${name}.`);
  };

  /**
   * Saves the `.bib` with the app's cross-references and its Hebrew and
   * Greek written into it, so the file carries them wherever it goes and
   * whatever opens it.
   *
   * Refused where the translation's numbering was measured as different
   * and the reader has not overruled that: baking layers into a file they
   * do not fit would put the mistake beyond reach of anyone who later
   * reads it.
   */
  const saveWithLayers = async (): Promise<void> => {
    if (!settings.offersVerseKeyedLayers(translation)) {
      say(
        `${name} numbers its verses differently, so the bundled layers would land on the wrong verses. ` +
          'Turn them on for it first if you want them anyway.',
      );
      return;
    }

    const file = await bytes();
    if (file === null) return;

    // A translation that brought layers of its own keeps them: they are
    // keyed to its own numbering, and the bundled ones are no improvement
    // on that.
    let tags: string[];
    try {
      tags = BibFile.tags(file);
    } catch {
      tags = [];
    }
    const wanted = new StudyLayers({
      crossReferences: tags.includes(CrossReferences.chunkTag) ? null : await library.bundle.load(CrossReferences.assetPath),
      originals: tags.includes(Originals.chunkTag) ? null : await library.bundle.load(Originals.assetPath),
    });
    if (wanted.isEmpty) {
      say(`${name} already carries both of them.`);
      return;
    }

    say(`Writing the study layers into ${name}…`);
    // A breath, so the message is on screen before the work holds the page.
    await new Promise((resolve) => setTimeout(resolve, 60));
    let written: AttachedLayers;
    try {
      written = attachStudyLayers(file, wanted);
    } catch (error) {
      say(`Could not write them in: ${error instanceof Error ? error.message : String(error)}`);
      return;
    }

    try {
      await saveBytes(`${id}-study${BibFile.extension}`, written.bytes);
    } catch (error) {
      say(`Could not save it: ${error instanceof Error ? error.message : String(error)}`);
      return;
    }
    const megabytes = (written.bytes.length / (1024 * 1024)).toFixed(1);
    // The browser does not say whether its dialog was cancelled, so this
    // says what was made rather than where it went.
    say(`${megabytes} MB with the study layers: ${written.references} verses of cross-references, ${written.verses} of Hebrew and Greek.`);
  };

  const chose = async (choice: string): Promise<void> => {
    // The menu is still stepping back out of the history: a dialog opened
    // before it has would be closed along with it.
    await historySettled();
    if (choice === 'anchor') {
      const wanted = !settings.anchoredAnyway.has(id);
      settings.setAnchoredAnyway(id, wanted);
      showSnackBar(
        wanted
          ? `Cross-references and the Hebrew and Greek are on for ${name}. Some will be out by a verse or two.`
          : `Cross-references and the Hebrew and Greek are off for ${name} again.`,
      );
      return;
    }
    if (choice === 'save') {
      const file = await bytes();
      if (file === null) return;
      try {
        // The browser's own dialog, share sheet or download says where it went.
        await saveBytes(`${id}${BibFile.extension}`, file);
      } catch (error) {
        say(`Could not save it: ${error instanceof Error ? error.message : String(error)}`);
      }
      return;
    }
    if (choice === 'save-with-layers') {
      await saveWithLayers();
      return;
    }
    if (choice === 'tidy') {
      await tidy();
      return;
    }
    if (choice === 'remove') {
      const shelf = library.shelf;
      if (shelf === null) return;
      await shelf.remove(id);
      // Whatever was being read has just gone; fall back to a bundled
      // translation rather than an empty screen.
      if (settings.translationId === id) {
        settings.translationId = Translations.fallback.id;
        await library.load(Translations.fallback.id);
      }
      if (settings.compareTranslationId === id) {
        settings.compareTranslationId = null;
      }
      showSnackBar(`Removed ${name}`);
    }
  };

  return (
    <PopupMenuButton
      icon={imported ? 'inventory_2_outlined' : 'more_vert'}
      label={imported ? 'Imported translation' : 'Translation'}
      onSelected={(choice) => void chose(choice as string)}
      items={() => (
        <>
          {imported && (
            <>
              <MenuItem label={shelved === null ? 'Imported' : shelved.readableSize} value="about" disabled />
              <MenuDivider />
            </>
          )}
          {/* Only where the app has withheld them, since that is the only
              case there is anything to overrule. */}
          {!Versification.mayAnchorEnglish(translation.versification) && (
            <MenuItem label="Cross-references and originals anyway" value="anchor" checked={settings.anchoredAnyway.has(id)} />
          )}
          <MenuItem label="Save a copy…" value="save" />
          <MenuItem label="Save a copy with the study layers…" value="save-with-layers" />
          {imported && <MenuItem label="Tidy up the text…" value="tidy" />}
          {imported && <MenuItem label="Remove" value="remove" />}
        </>
      )}
    />
  );
}

// --- licences -----------------------------------------------------------

/** One entry of the Licences screen: who it covers, in a line, and the text. */
interface Licence {
  title: string;
  summary: string;
  load: () => Promise<string>;
}

/** The app's own licence, as its repository states it. */
const appLicence = `MIT License

Copyright (c) 2026 tahuffman1s

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`;

/** What the page is built with, beside the voice: named, with the licence each is under. */
const libraries: readonly [string, string][] = [
  ['Preact and Preact Signals', 'MIT'],
  ['fflate', 'MIT'],
  ['htmlparser2', 'MIT'],
  ['domhandler and domutils', 'BSD-2-Clause'],
  ['idb', 'ISC'],
  ['Workbox', 'MIT'],
  ['Material Color Utilities', 'Apache-2.0'],
  ['Material Design icons', 'Apache-2.0'],
  ['phonemizer.js', 'Apache-2.0'],
];

/**
 * Every licence in full: the app's own, the voice's — KittenTTS, eSpeak NG
 * and ONNX Runtime, read from the bundled texts — and the fonts'. Flutter
 * gathered its packages' licences into a page of its own; this is that page.
 */
export function LicencesScreen() {
  const { library, updates } = useAppScope();
  useNotifier(updates);
  const bundle = library.bundle;
  const voice = useAsync(() => voiceLicences(bundle), [bundle]);
  const licences: Licence[] = [
    { title: 'OpenWord', summary: 'MIT', load: async () => appLicence },
    ...(voice.value ?? []).map((licence) => ({
      title: licence.packages.join(', '),
      summary: licence.packages.includes('eSpeak NG') ? 'GPL-3.0' : licence.packages.includes('KittenTTS') ? 'Apache-2.0' : 'MIT',
      load: async () => licence.text,
    })),
    { title: 'Literata', summary: 'SIL Open Font License 1.1', load: () => bundle.loadString('assets/fonts/Literata-OFL.txt') },
    {
      title: 'Noto Serif, Noto Serif Hebrew',
      summary: 'SIL Open Font License 1.1',
      load: () => bundle.loadString('assets/fonts/NotoSerif-OFL.txt'),
    },
    {
      title: 'Other libraries',
      summary: 'MIT, ISC, BSD and Apache-2.0',
      load: async () => `OpenWord is also built with:\n\n${libraries.map(([name, licence]) => `${name} — ${licence}`).join('\n')}`,
    },
  ];
  return (
    <Screen class="ow-licences" appBar={(scrolled) => <AppBar scrolled={scrolled} title="Licences" subtitle={updates.version === null ? 'OpenWord' : `OpenWord ${updates.version.version}`} />}>
      <div class="ow-settings__page">
        {voice.loading && <LinearProgress />}
        {voice.error !== undefined && <div class="m3-body-medium m3-error ow-licences__problem">The voice’s licences could not be read.</div>}
        {licences.map((licence) => (
          <ListTile key={licence.title} title={licence.title} subtitle={licence.summary} onClick={() => void nav.push(<LicenceScreen licence={licence} />)} />
        ))}
      </div>
    </Screen>
  );
}

/** A paragraph of a licence: its lines run together, or a line set in the middle. */
export interface LicenceBlock {
  text: string;
  centred: boolean;

  /** How far in the paragraph is set, in steps: a clause under a clause. */
  indent: number;
}

/**
 * A licence's text as paragraphs. The texts are wrapped by hand at some
 * seventy columns, which a phone would wrap again into ragged halves; the
 * lines of a paragraph are run together instead, and a line pushed well
 * in — a title — is set in the middle, as Flutter's licence page does it.
 */
export function licenceBlocks(text: string): LicenceBlock[] {
  const blocks: LicenceBlock[] = [];
  for (const paragraph of text.replaceAll('\r\n', '\n').split(/\n[ \t]*\n/)) {
    const lines = paragraph.split('\n').filter((line) => line.trim().length > 0);
    if (lines.length === 0) continue;
    const leading = (line: string): number => line.length - line.trimStart().length;
    if (lines.every((line) => leading(line) >= 8)) {
      for (const line of lines) blocks.push({ text: line.trim(), centred: true, indent: 0 });
      continue;
    }
    blocks.push({
      text: lines.map((line) => line.trim()).join(' '),
      centred: false,
      indent: Math.min(Math.floor(leading(lines[0]) / 2), 3),
    });
  }
  return blocks;
}

function LicenceScreen({ licence }: { licence: Licence }) {
  const text = useAsync(() => licence.load(), [licence]);
  return (
    <Screen class="ow-licences" appBar={(scrolled) => <AppBar scrolled={scrolled} title={licence.title} subtitle={licence.summary} />}>
      <div class="ow-settings__page">
        {text.loading ? (
          <LinearProgress />
        ) : text.error !== undefined ? (
          <div class="m3-body-medium m3-error ow-licences__problem">That licence could not be read.</div>
        ) : (
          <div class="ow-licences__text m3-body-small">
            {licenceBlocks(text.value ?? '').map((block) => (
              <p class={block.centred ? 'ow-licences__centred' : undefined} style={block.indent > 0 ? `padding-left:${block.indent * 12}px` : undefined}>
                {block.text}
              </p>
            ))}
          </div>
        )}
      </div>
    </Screen>
  );
}
