import { gunzipIfNeeded } from '../infra/gunzip';
import { type AssetBundle, rootBundle } from '../infra/assets';
import { utf8 } from '../model/byteIo';

/**
 * The book introductions bundled with the app.
 *
 * These are the Aquifer Open Study Notes book introductions — an adaptation
 * by Mission Mutual of Tyndale Open Study Notes, both under CC BY-SA 4.0.
 * They are loaded on demand rather than at start-up: they are only wanted
 * when someone opens a book's background sheet, and there is no reason to
 * spend the memory before that.
 */
export class BookIntros {
  constructor(bundle?: AssetBundle) {
    this.bundle = bundle ?? rootBundle;
  }

  static readonly assetName = 'book-intros-eng.json.gz';
  static readonly assetPath = `assets/notes/${BookIntros.assetName}`;

  /** Shown wherever the introductions are, as the licence requires. */
  static readonly attribution =
    'Aquifer Open Study Notes (Book Intros) © Mission Mutual, an adaptation ' +
    'of Tyndale Open Study Notes © 2023 Tyndale House Publishers. Both are ' +
    'licensed CC BY-SA 4.0.';

  static readonly licenceUrl = 'https://creativecommons.org/licenses/by-sa/4.0/';

  private readonly bundle: AssetBundle;
  private intros: Map<string, string> | null = null;
  private loading: Promise<Map<string, string>> | null = null;

  /**
   * The introduction for a book, or null where there is none — the
   * deuterocanonical books are not covered by this resource.
   */
  async forBook(bookCode: string): Promise<string | null> {
    const intros = this.intros ?? (await this.load());
    return intros.get(bookCode.toUpperCase()) ?? null;
  }

  /** Already-loaded introductions, for a synchronous check. */
  loaded(bookCode: string): string | null {
    return this.intros?.get(bookCode.toUpperCase()) ?? null;
  }

  private load(): Promise<Map<string, string>> {
    return (this.loading ??= this.read().then((intros) => {
      this.intros = intros;
      return intros;
    }));
  }

  private async read(): Promise<Map<string, string>> {
    try {
      const bytes = await this.bundle.load(BookIntros.assetPath);
      const raw = gunzipIfNeeded(bytes);
      const decoded: unknown = JSON.parse(utf8.decode(raw));
      if (typeof decoded !== 'object' || decoded === null || Array.isArray(decoded)) return new Map();
      return new Map(Object.entries(decoded).map(([key, value]) => [`${key}`, `${value}`]));
    } catch (error) {
      console.warn(`OpenWord: could not read book introductions: ${error}`);
      return new Map();
    }
  }
}

/**
 * A book introduction, split into its sections.
 *
 * The source is consistent about its shape: a paragraph or two of lead, then
 * top-level sections — Setting, Summary, Author, Date, Meaning and Message —
 * some with sub-headings of their own. Splitting on those headings lets the
 * sheet show the outline at a glance rather than several screens of prose.
 */
export class BookIntro {
  /** What comes before the first section heading. */
  readonly lead: string;

  readonly sections: readonly IntroSection[];

  constructor(init: { lead: string; sections: readonly IntroSection[] }) {
    this.lead = init.lead;
    this.sections = init.sections;
  }

  get isEmpty(): boolean {
    return this.lead.length === 0 && this.sections.length === 0;
  }

  static parse(markdown: string): BookIntro {
    const lines = markdown.replace(/\r\n/g, '\n').split('\n');
    const lead: string[] = [];
    const sections: IntroSection[] = [];
    let title: string | null = null;
    const body: string[] = [];

    const close = (): void => {
      const heading = title;
      if (heading === null) return;
      sections.push(new IntroSection({ title: heading, body: body.join('\n').trim() }));
      body.length = 0;
    };

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();

      // A line of `=` underneath text makes it a top-level heading; the
      // source uses `-` for the level below, which stays inside its section.
      const next = i + 1 < lines.length ? lines[i + 1].trim() : '';
      const underlined = trimmed.length > 0 && /^=+$/.test(next);
      const hashed = /^#\s+(.*)$/.exec(trimmed);

      if (underlined || hashed !== null) {
        close();
        title = hashed?.[1]?.trim() ?? trimmed;
        if (underlined) i++;
        continue;
      }

      if (title === null) {
        lead.push(line);
      } else {
        body.push(line);
      }
    }
    close();

    return new BookIntro({ lead: lead.join('\n').trim(), sections });
  }
}

export class IntroSection {
  readonly title: string;
  readonly body: string;

  constructor(init: { title: string; body: string }) {
    this.title = init.title;
    this.body = init.body;
  }
}
