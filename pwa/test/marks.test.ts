import { beforeEach, describe, expect, it } from 'vitest';
import { ReadingStore } from '../src/data/marks';
import { BookOrder, ReadingFont, Settings, ThemeMode } from '../src/data/settings';
import { Translations } from '../src/data/translations';
import { Prefs } from '../src/infra/prefs';
import { Reference, TranslationInfo, Versification } from '../src/model/bible';

const john = new Reference('JHN', 3, 16);
const psalm = new Reference('PSA', 23, 1);

describe('the reading store', () => {
  let prefs: Prefs;
  beforeEach(() => {
    prefs = Prefs.memory();
  });

  it('bookmarks toggle on and off', async () => {
    const store = await ReadingStore.load({ prefs });
    expect(store.isBookmarked(john)).toBe(false);
    expect(store.toggleBookmark(john)).toBe(true);
    expect(store.isBookmarked(john)).toBe(true);
    expect(store.bookmarks).toHaveLength(1);
    expect(store.bookmarks[0].reference.equals(john)).toBe(true);
    expect(store.flaggedVersesIn('JHN', 3)).toEqual(new Set([16]));

    expect(store.toggleBookmark(john)).toBe(false);
    expect(store.isBookmarked(john)).toBe(false);
    expect(store.all).toEqual([]);
  });

  it('highlights carry a colour and are listed separately', async () => {
    const store = await ReadingStore.load({ prefs });
    store.setHighlight(john, 2);
    expect(store.highlightsIn('JHN', 3)).toEqual(new Map([[16, 2]]));
    expect(store.highlights).toHaveLength(1);
    expect(store.highlights[0].colorIndex).toBe(2);
    expect(store.bookmarks).toEqual([]);

    store.setHighlight(john, null);
    expect(store.highlightsIn('JHN', 3).size).toBe(0);
    expect(store.all).toEqual([]);
  });

  it('one verse can hold a bookmark, a colour and a note at once', async () => {
    const store = await ReadingStore.load({ prefs });
    store.toggleBookmark(john);
    store.setHighlight(john, 1);
    store.setNote(john, '  God so loved  ');

    const mark = store.markFor(john)!;
    expect(mark.bookmarked).toBe(true);
    expect(mark.colorIndex).toBe(1);
    expect(mark.note).toBe('God so loved');
    expect(store.notes).toHaveLength(1);
    expect(store.notes[0].reference.equals(john)).toBe(true);
    expect(store.markedChaptersIn('JHN')).toEqual(new Set([3]));
    expect(store.markedBookCodes).toEqual(new Set(['JHN']));

    // Clearing every part removes the mark.
    store.toggleBookmark(john);
    store.setHighlight(john, null);
    store.setNote(john, '');
    expect(store.markFor(john)).toBeNull();
  });

  it('marks and notes survive a restart, newest first', async () => {
    const store = await ReadingStore.load({ prefs });
    store.toggleBookmark(john);
    store.setNote(psalm, 'My shepherd');

    const reopened = await ReadingStore.load({ prefs });
    expect(reopened.all).toHaveLength(2);
    expect(reopened.all[0].reference.equals(psalm)).toBe(true);
    expect(reopened.markFor(psalm)!.note).toBe('My shepherd');
    expect(reopened.isBookmarked(john)).toBe(true);
  });

  it('version 1.0 bookmarks are migrated', async () => {
    prefs.setString(
      'bookmarks',
      JSON.stringify([
        { b: 'JHN', c: 3, v: 16, t: 1000, n: 'from 1.0' },
        { b: 'GEN', c: 1, v: 1, t: 900 },
      ]),
    );
    const store = await ReadingStore.load({ prefs });
    expect(store.bookmarks).toHaveLength(2);
    expect(store.markFor(john)!.bookmarked).toBe(true);
    expect(store.markFor(john)!.note).toBe('from 1.0');
    expect(store.markFor(john)!.highlighted).toBe(false);

    // And are written forward, so the legacy key is no longer needed.
    expect(prefs.containsKey('marks')).toBe(true);
    const reopened = await ReadingStore.load({ prefs });
    expect(reopened.bookmarks).toHaveLength(2);
  });

  it('export and import round trip, merging by recency', async () => {
    const store = await ReadingStore.load({ prefs });
    store.toggleBookmark(john);
    store.setHighlight(psalm, 3);
    const backup = store.export();
    expect(backup).toContain('"app": "openword"');

    // A fresh device restores everything.
    const fresh = await ReadingStore.load({ prefs: Prefs.memory() });
    const result = fresh.import(backup);
    expect(result.ok).toBe(true);
    expect(result.added).toBe(2);
    expect(fresh.isBookmarked(john)).toBe(true);
    expect(fresh.highlightsIn('PSA', 23)).toEqual(new Map([[1, 3]]));

    // Importing the same backup again changes nothing.
    const again = fresh.import(backup);
    expect(again.total).toBe(0);
    expect(fresh.all).toHaveLength(2);
  });

  it('a backup keeps its keys, so one made by an earlier version restores here', async () => {
    const phone = JSON.stringify({
      app: 'openword',
      version: 1,
      exported: '2026-09-28T09:30:00.000',
      position: 'JHN/3/16',
      marks: [{ b: 'JHN', c: 3, v: 16, t: 1000, m: true, k: 2, n: 'kept' }],
      plans: [{ id: 'proverbs-31', start: '2026-09-01', t: 1000, done: [0, 1] }],
      memory: [{ b: 'PSA', c: 23, v: 1, added: '2026-09-20', due: '2026-09-28', t: 1000, rung: 2, recalled: 2, s: 3.0, d: 0.28 }],
      streak: { count: 3, best: 5, last: '2026-09-27', freezes: 1 },
      progress: { xp: 120, daily: { '2026-09-27': 120 }, right: 9, wrong: 1, perfect: 0, scribed: 0, heard: 0, goal: 60, badges: { first_step: '2026-09-27' } },
      sleep: { mode: 'nights', evening: 20, morning: 10 },
    });
    const store = await ReadingStore.load({ prefs, clock: () => new Date(2026, 8, 28, 9) });
    const result = store.import(phone);
    expect(result.ok).toBe(true);
    expect(store.markFor(john)!.note).toBe('kept');
    expect(store.progressFor('proverbs-31')!.done).toEqual(new Set([0, 1]));
    expect(store.memoryFor(psalm)!.stability).toBe(3);
    expect(store.streak.count).toBe(3);
    expect(store.streak.freezes).toBe(1);
    expect(store.progress.xp).toBe(120);
    expect(store.progress.badges.has('first_step')).toBe(true);
    // What goes back out carries the same keys, so the phone reads it.
    const out = JSON.parse(store.export()) as Record<string, unknown>;
    expect(Object.keys(out)).toEqual(['app', 'version', 'exported', 'position', 'marks', 'plans', 'memory', 'streak', 'progress', 'sleep']);
    expect(out['marks']).toEqual([{ b: 'JHN', c: 3, v: 16, t: 1000, m: true, k: 2, n: 'kept' }]);
    expect(out['streak']).toEqual({ count: 3, best: 5, last: '2026-09-27', freezes: 1 });
    expect(out['sleep']).toEqual({ mode: 'trial', evening: 19, morning: 11 });
  });

  it('import keeps the local copy when it is newer', async () => {
    const store = await ReadingStore.load({ prefs });
    store.setNote(john, 'older');
    const backup = store.export();

    store.setNote(john, 'newer');
    const result = store.import(backup);
    expect(result.ok).toBe(true);
    expect(result.total).toBe(0);
    expect(store.markFor(john)!.note).toBe('newer');
  });

  it('rubbish does not import', async () => {
    const store = await ReadingStore.load({ prefs });
    expect(store.import('not json at all').ok).toBe(false);
    expect(store.import('{}').ok).toBe(false);
    expect(store.import('{"marks": 7}').ok).toBe(false);
    expect(store.all).toEqual([]);
  });

  it('position and history are remembered', async () => {
    const store = await ReadingStore.load({ prefs });
    await store.savePosition(new Reference('MAT', 5, 3));
    await store.savePosition(new Reference('MAT', 5, 9));
    await store.savePosition(new Reference('ROM', 8, 1));

    const reopened = await ReadingStore.load({ prefs });
    expect(reopened.lastPosition!.equals(new Reference('ROM', 8, 1))).toBe(true);
    expect(reopened.history.map((reference) => reference.label)).toEqual(['Romans 8', 'Matthew 5']);

    reopened.clearHistory();
    expect(reopened.history).toEqual([]);
  });

  it('the listening place is kept and cleared', async () => {
    const store = await ReadingStore.load({ prefs });
    expect(store.listeningPlace).toBeNull();
    store.listeningPlace = 'JHN/3/16';
    expect((await ReadingStore.load({ prefs })).listeningPlace).toBe('JHN/3/16');
    store.listeningPlace = null;
    expect(store.listeningPlace).toBeNull();
  });

  it('tells its listeners when something changes', async () => {
    const store = await ReadingStore.load({ prefs });
    let told = 0;
    store.addListener(() => told++);
    store.toggleBookmark(john);
    store.remove(john);
    store.remove(john);
    expect(told).toBe(2);
  });
});

describe('settings', () => {
  let prefs: Prefs;
  beforeEach(() => {
    prefs = Prefs.memory();
  });

  it('persist and have sensible defaults', async () => {
    const settings = await Settings.load(prefs);
    expect(settings.useDynamicColor).toBe(true);
    expect(settings.paragraphLayout).toBe(true);
    expect(settings.showDeuterocanon).toBe(false);
    expect(settings.bookOrder).toBe(BookOrder.canonical);
    expect(settings.compareTranslationId).toBeNull();
    expect(settings.themeMode).toBe(ThemeMode.system);
    expect(settings.readingFont).toBe(ReadingFont.serif);
    expect(settings.seedColor).toBe(0xff6750a4);
    expect(settings.fontScale).toBe(1.0);
    expect(settings.lineHeight).toBe(1.6);
    expect(settings.translationId).toBe(Translations.fallback.id);
    expect(settings.speechRate).toBe(1.0);
    expect(settings.learnAutoSpeak).toBe(true);
    expect(settings.checkForUpdates).toBe(true);
    expect(settings.lastUpdateCheck).toBeNull();

    settings.fontScale = 1.4;
    settings.showDeuterocanon = true;
    settings.compareTranslationId = 'eng-bsb';
    settings.themeMode = ThemeMode.dark;
    settings.readingFont = ReadingFont.sans;
    settings.seedColor = 0xff1b6c4f;

    const reopened = await Settings.load(prefs);
    expect(reopened.fontScale).toBe(1.4);
    expect(reopened.showDeuterocanon).toBe(true);
    expect(reopened.compareTranslationId).toBe('eng-bsb');
    expect(reopened.themeMode).toBe(ThemeMode.dark);
    expect(reopened.readingFont).toBe(ReadingFont.sans);
    expect(reopened.seedColor).toBe(0xff1b6c4f);
    // The keys and shapes settings have always been stored under.
    expect(prefs.getInt('themeMode')).toBe(2);
    expect(prefs.getInt('readingFont')).toBe(1);
    expect(prefs.getDouble('fontScale')).toBe(1.4);

    reopened.compareTranslationId = null;
    expect(reopened.compareTranslationId).toBeNull();
  });

  it('comparing against the translation being read means not comparing', async () => {
    const settings = await Settings.load(prefs);
    settings.compareTranslationId = settings.translationId;
    expect(settings.compareTranslationId).toBeNull();
  });

  it('carries an old speech rate over as the nearest that sounds the same', async () => {
    prefs.setDouble('speechRate', 1.25);
    const settings = await Settings.load(prefs);
    expect(settings.speechRate).toBe(1.0);
    settings.speechRate = 1.5;
    expect((await Settings.load(prefs)).speechRate).toBe(1.5);
    expect(Settings.speechRates).toEqual([0.75, 1.0, 1.25, 1.5, 2.0]);
  });

  it('offers the verse-keyed layers by numbering, or when asked anyway', async () => {
    const settings = await Settings.load(prefs);
    const other = new TranslationInfo({
      id: 'x',
      name: 'X',
      abbreviation: 'X',
      license: '',
      sourceUrl: '',
      versification: Versification.other,
    });
    expect(settings.offersVerseKeyedLayers(Translations.web)).toBe(true);
    expect(settings.offersVerseKeyedLayers(other)).toBe(false);
    let told = 0;
    settings.addListener(() => told++);
    settings.setAnchoredAnyway('x', true);
    settings.setAnchoredAnyway('x', true);
    expect(told).toBe(1);
    expect(settings.offersVerseKeyedLayers(other)).toBe(true);
    expect(settings.anchoredAnyway).toEqual(new Set(['x']));
    settings.setAnchoredAnyway('x', false);
    expect(settings.offersVerseKeyedLayers(other)).toBe(false);
  });
});
