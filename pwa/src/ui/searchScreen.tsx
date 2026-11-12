import { useEffect, useRef, useState } from 'preact/hooks';
import {
  groupHitsByBook,
  searchBible,
  searchLimit,
  SearchScope,
  searchScopeLabel,
  searchScopes,
  snippetOf,
  type SearchHit,
} from '../data/search';
import type { Bible, Reference } from '../model/bible';
import { BookMeta } from '../model/bookMeta';
import { AppBar, Chip, CircularProgress, Divider, IconButton, ListTile, Screen, nav, useOverlay } from './m3';
import './searchScreen.css';

/** Opens the search and resolves to the verse chosen, if one was. */
export function showSearch(options: { bible: Bible; from?: Reference | null }): Promise<Reference | undefined> {
  return nav.push<Reference>(<SearchScreen bible={options.bible} from={options.from ?? null} />, { name: 'search' });
}

export interface SearchScreenProps {
  bible: Bible;

  /** Where the reader was, so "this book" has something to scope to. */
  from?: Reference | null;
}

/** Plain text search over the translation being read. */
export function SearchScreen({ bible, from = null }: SearchScreenProps) {
  const overlay = useOverlay();
  const input = useRef<HTMLInputElement>(null);
  const debounce = useRef<ReturnType<typeof setTimeout> | 0>(0);

  const [text, setText] = useState('');
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState('');
  const [scope, setScope] = useState(SearchScope.all);
  const [wholeWord, setWholeWord] = useState(false);

  useEffect(() => {
    input.current?.focus();
    return () => {
      if (debounce.current !== 0) clearTimeout(debounce.current);
    };
  }, []);

  const run = (typed: string, where: SearchScope, whole: boolean) => {
    if (debounce.current !== 0) clearTimeout(debounce.current);
    debounce.current = 0;
    const trimmed = typed.trim();
    setQuery(trimmed);
    setHits(searchBible(bible, trimmed, { scope: where, currentBookCode: from?.bookCode ?? null, wholeWord: whole }));
    setSearching(false);
  };

  const schedule = (typed: string) => {
    if (debounce.current !== 0) clearTimeout(debounce.current);
    setSearching(typed.trim().length >= 2);
    debounce.current = setTimeout(() => run(typed, scope, wholeWord), 260);
  };

  return (
    <Screen
      class="ow-search"
      bodyClass="ow-search__body"
      appBar={
        <AppBar
          title={
            <input
              ref={input}
              class="ow-search__field"
              type="search"
              enterkeyhint="search"
              placeholder="Search the text"
              aria-label="Search the text"
              autocomplete="off"
              value={text}
              onInput={(event) => {
                const typed = (event.currentTarget as HTMLInputElement).value;
                setText(typed);
                schedule(typed);
              }}
              onKeyDown={(event) => {
                if (event.key === 'Enter') run(text, scope, wholeWord);
              }}
            />
          }
          actions={
            text.length > 0 && (
              <IconButton
                icon="close"
                label="Clear"
                onClick={() => {
                  setText('');
                  schedule('');
                  input.current?.focus();
                }}
              />
            )
          }
        />
      }
    >
      <div class="ow-search__filters">
        {searchScopes
          .filter((candidate) => candidate !== SearchScope.currentBook || from !== null)
          .map((candidate) => (
            <Chip
              variant="choice"
              label={candidate === SearchScope.currentBook && from !== null ? from.bookName : searchScopeLabel[candidate]}
              selected={scope === candidate}
              onClick={() => {
                setScope(candidate);
                run(text, candidate, wholeWord);
              }}
            />
          ))}
        <span style="width:4px;flex:none" />
        <Chip
          label="Whole word"
          selected={wholeWord}
          onClick={() => {
            setWholeWord(!wholeWord);
            run(text, scope, !wholeWord);
          }}
        />
      </div>
      <Divider />
      <div class="ow-search__results">
        <Results
          hits={hits}
          searching={searching}
          query={query}
          scope={scope}
          onOpen={(reference) => overlay.close(reference)}
        />
      </div>
    </Screen>
  );
}

function Results({
  hits,
  searching,
  query,
  scope,
  onOpen,
}: {
  hits: readonly SearchHit[];
  searching: boolean;
  query: string;
  scope: SearchScope;
  onOpen: (reference: Reference) => void;
}) {
  if (searching) {
    return (
      <div class="ow-search__empty">
        <CircularProgress />
      </div>
    );
  }
  if (hits.length === 0) {
    return (
      <div class="ow-search__empty m3-body-large m3-on-surface-variant">
        {query.length < 2
          ? 'Type at least two letters'
          : `Nothing found for “${query}”${scope === SearchScope.all ? '' : ` in ${searchScopeLabel[scope].toLowerCase()}`}`}
      </div>
    );
  }

  // Grouped by book, keeping canonical order.
  const grouped = groupHitsByBook(hits);
  return (
    <div class="ow-content">
      <div class="ow-search__count">
        {hits.length}
        {hits.length >= searchLimit ? '+' : ''} {hits.length === 1 ? 'verse' : 'verses'} in {grouped.size}{' '}
        {grouped.size === 1 ? 'book' : 'books'}
      </div>
      {[...grouped.entries()].map(([code, list]) => (
        <div key={code}>
          <div class="ow-search__book">
            <span class="ow-search__book-name">{BookMeta.lookup(code)?.name ?? code}</span>
            <span class="m3-label-medium m3-on-surface-variant">{list.length}</span>
          </div>
          {list.map((hit) => (
            <ListTile
              dense
              class="ow-search__hit"
              title={
                <span class="m3-label-large m3-on-surface-variant">
                  {hit.reference.chapter}:{hit.reference.verse}
                </span>
              }
              subtitle={<Snippet hit={hit} />}
              onClick={() => onOpen(hit.reference)}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

/** Shows the match in context with the query emphasised. */
function Snippet({ hit }: { hit: SearchHit }) {
  const { prefix, match, suffix } = snippetOf(hit);
  return (
    <span class="ow-search__snippet">
      {prefix}
      <mark class="ow-search__match">{match}</mark>
      {suffix}
    </span>
  );
}
