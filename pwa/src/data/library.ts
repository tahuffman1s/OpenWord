import { type AssetBundle, rootBundle } from '../infra/assets';
import { ChangeNotifier } from '../infra/changeNotifier';
import { BibFile } from '../model/bibFile';
import { Bible, TranslationInfo } from '../model/bible';
import type { Shelf } from './shelf';
import { Translations } from './translations';

export enum LibraryStatus {
  loading = 'loading',
  ready = 'ready',
  failed = 'failed',
}

/**
 * Holds the Scripture the app is reading.
 *
 * Three translations ship inside the app; a reader can put more on the
 * `Shelf` by importing them. Either way the work is the same — read the
 * bytes, gunzip, decode — and nothing touches the network.
 */
export class LibraryController extends ChangeNotifier {
  constructor(init: { bundle?: AssetBundle | null; shelf?: Shelf | null } = {}) {
    super();
    this._bundle = init.bundle ?? rootBundle;
    this.shelf = init.shelf ?? null;
  }

  private readonly _bundle: AssetBundle;

  /**
   * The imported translations, where there are any. Null in a browser
   * with no IndexedDB, which has nowhere to keep them.
   */
  readonly shelf: Shelf | null;

  /**
   * The bundle the Scripture was read from. Anything else that ships as an
   * asset — the book introductions, for one — reads from the same place, so
   * a test can swap both at once.
   */
  get bundle(): AssetBundle {
    return this._bundle;
  }

  private _status: LibraryStatus = LibraryStatus.loading;
  private _errorMessage: string | null = null;
  private _bible: Bible | null = null;

  /** A second translation, loaded only while the reader is comparing. */
  private _comparison: Bible | null = null;
  private _loadingComparison = false;

  get status(): LibraryStatus {
    return this._status;
  }
  get errorMessage(): string | null {
    return this._errorMessage;
  }
  get bible(): Bible | null {
    return this._bible;
  }
  get comparison(): Bible | null {
    return this._comparison;
  }
  get loadingComparison(): boolean {
    return this._loadingComparison;
  }
  get isReady(): boolean {
    return this._status === LibraryStatus.ready && this._bible !== null;
  }

  get translation(): TranslationInfo {
    return this._bible?.translation ?? Translations.fallback;
  }

  /**
   * Loads `translationId` as the translation being read. Falls back to the
   * default translation if that asset cannot be read.
   */
  async load(translationId: string): Promise<void> {
    this._status = LibraryStatus.loading;
    this._errorMessage = null;
    this.notifyListeners();
    try {
      this._bible = await this.read(translationId);
      if (this._comparison?.translation.id === this._bible.translation.id) {
        this._comparison = null;
      }
      this._status = LibraryStatus.ready;
    } catch (error) {
      console.warn(`OpenWord: could not load ${translationId}: ${String(error)}`);
      if (translationId !== Translations.fallback.id) {
        await this.load(Translations.fallback.id);
        return;
      }
      this._errorMessage = 'The bundled Scripture could not be read.';
      this._status = LibraryStatus.failed;
    }
    this.notifyListeners();
  }

  /** Loads a second translation for side-by-side reading. */
  async loadComparison(translationId: string): Promise<void> {
    if (translationId === this._bible?.translation.id) {
      this.clearComparison();
      return;
    }
    if (this._comparison?.translation.id === translationId) return;
    this._loadingComparison = true;
    this.notifyListeners();
    try {
      this._comparison = await this.read(translationId);
    } catch (error) {
      console.warn(`OpenWord: could not load comparison ${translationId}: ${String(error)}`);
      this._comparison = null;
    }
    this._loadingComparison = false;
    this.notifyListeners();
  }

  /** Drops the second translation, freeing the memory it held. */
  clearComparison(): void {
    if (this._comparison === null && !this._loadingComparison) return;
    this._comparison = null;
    this._loadingComparison = false;
    this.notifyListeners();
  }

  /** True where this id names a translation that can actually be read. */
  knows(translationId: string): boolean {
    return Translations.all.some((t) => t.id === translationId) || (this.shelf?.has(translationId) ?? false);
  }

  /**
   * Everything that can be read: what ships with the app, then whatever the
   * reader has imported.
   */
  get available(): TranslationInfo[] {
    return [...Translations.all, ...(this.shelf === null ? [] : this.shelf.translations.map((shelved) => shelved.info))];
  }

  /** What a translation id is called, bundled or imported. */
  infoFor(id: string): TranslationInfo {
    return this.available.find((translation) => translation.id === id) ?? Translations.fallback;
  }

  /** True where the reader brought this one themselves. */
  isImported(id: string): boolean {
    return this.shelf?.has(id) ?? false;
  }

  private async read(translationId: string): Promise<Bible> {
    const imported = this.shelf;
    if (imported !== null && imported.has(translationId)) {
      return imported.read(translationId);
    }
    const data = await this._bundle.load(Translations.assetFor(translationId));
    return BibFile.decode(data);
  }
}
