import { type Bible, type Book, Reference } from '../model/bible';
import { BookSection } from '../model/bookMeta';
import { ScriptureText } from '../model/textNormal';

/**
 * The pure half of searching: the scan, its scope and what a hit is. The
 * screen — the field, the chips, the list — is `src/ui/searchScreen.tsx`.
 * Everything here is top-level and free of the DOM so a worker can import
 * it.
 */

/** Where a search looks. */
export enum SearchScope {
  all = 'all',
  oldTestament = 'oldTestament',
  newTestament = 'newTestament',
  currentBook = 'currentBook',
}

export const searchScopeLabel: Record<SearchScope, string> = {
  [SearchScope.all]: 'Whole Bible',
  [SearchScope.oldTestament]: 'Old Testament',
  [SearchScope.newTestament]: 'New Testament',
  [SearchScope.currentBook]: 'This book',
};

/** In the order the chips are shown. */
export const searchScopes: readonly SearchScope[] = [
  SearchScope.all,
  SearchScope.oldTestament,
  SearchScope.newTestament,
  SearchScope.currentBook,
];

/** One hit from a full-text scan. */
export class SearchHit {
  readonly reference: Reference;
  readonly text: string;
  readonly matchStart: number;
  readonly matchEnd: number;

  constructor(init: { reference: Reference; text: string; matchStart: number; matchEnd: number }) {
    this.reference = init.reference;
    this.text = init.text;
    this.matchStart = init.matchStart;
    this.matchEnd = init.matchEnd;
  }
}

export interface SearchOptions {
  scope?: SearchScope;
  currentBookCode?: string | null;
  wholeWord?: boolean;
  limit?: number;
}

/** How many hits a search stops at unless told otherwise. */
export const searchLimit = 400;

/** Escapes `text` to match literally in a RegExp, safe under the `u` flag as well. */
function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Plain text search over the translation being read.
 *
 * The pattern decides every hit, as it always has. Where the file carries a
 * word index, it is used first to rule out the books that cannot contain
 * the query — most words are in a handful of books — so those are never
 * unpacked or read. The results are the same either way; without an index
 * every book is read, which is what used to happen always.
 */
export function searchBible(bible: Bible, query: string, options: SearchOptions = {}): SearchHit[] {
  const scope = options.scope ?? SearchScope.all;
  const currentBookCode = options.currentBookCode ?? null;
  const wholeWord = options.wholeWord ?? false;
  const limit = options.limit ?? searchLimit;

  // Composed the same way the text was, so that what a reader types finds
  // what is on the page even where the two were spelled differently.
  const needle = ScriptureText.normalise(query.trim());
  if (needle.length < 2) return [];

  const pattern = wholeWord
    ? new RegExp(`(?<![\\p{L}\\p{N}])${escapeRegExp(needle)}(?![\\p{L}\\p{N}])`, 'iu')
    : new RegExp(escapeRegExp(needle), 'i');

  // Null where the index cannot say; empty where it says nowhere at all.
  const possible = bible.searchIndex?.booksFor(needle) ?? null;
  if (possible !== null && possible.size === 0) return [];

  const hits: SearchHit[] = [];
  for (let b = 0; b < bible.books.length; b++) {
    const book = bible.books[b];
    if (possible !== null && !possible.has(b)) continue;
    if (!inScope(book, scope, currentBookCode)) continue;
    for (const chapter of book.chapters) {
      for (let verse = 1; verse <= chapter.verseCount; verse++) {
        const text = chapter.verseText(verse);
        if (text.length === 0) continue;
        const match = pattern.exec(text);
        if (match === null) continue;
        hits.push(
          new SearchHit({
            reference: new Reference(book.code, chapter.number, verse),
            text,
            matchStart: match.index,
            matchEnd: match.index + match[0].length,
          }),
        );
        if (hits.length >= limit) return hits;
      }
    }
  }
  return hits;
}

function inScope(book: Book, scope: SearchScope, currentBookCode: string | null): boolean {
  switch (scope) {
    case SearchScope.all:
      return true;
    case SearchScope.oldTestament:
      return book.section === BookSection.oldTestament;
    case SearchScope.newTestament:
      return book.section === BookSection.newTestament;
    case SearchScope.currentBook:
      return book.code === currentBookCode;
  }
}

/**
 * Hits grouped by book, keeping canonical order — which is the order the
 * scan produced them in, so insertion order is enough.
 */
export function groupHitsByBook(hits: readonly SearchHit[]): Map<string, SearchHit[]> {
  const grouped = new Map<string, SearchHit[]>();
  for (const hit of hits) {
    let list = grouped.get(hit.reference.bookCode);
    if (!list) grouped.set(hit.reference.bookCode, (list = []));
    list.push(hit);
  }
  return grouped;
}

/**
 * The match in context with the query emphasised: what the result row
 * prints, cut so the match is in view when the verse runs long.
 */
export function snippetOf(hit: SearchHit): { prefix: string; match: string; suffix: string } {
  const start = hit.matchStart > 48 ? hit.matchStart - 42 : 0;
  const prefix = (start > 0 ? '…' : '') + hit.text.substring(start, hit.matchStart);
  return {
    prefix,
    match: hit.text.substring(hit.matchStart, hit.matchEnd),
    suffix: hit.text.substring(hit.matchEnd),
  };
}
