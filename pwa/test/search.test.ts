import { describe, expect, it } from 'vitest';
import { groupHitsByBook, searchBible, SearchScope, searchScopeLabel, snippetOf } from '../src/data/search';
import { sampleBible } from './fixtures';

describe('searchBible', () => {
  const bible = sampleBible();

  it('finds verses regardless of case', () => {
    const hits = searchBible(bible, 'god');
    expect(hits.map((hit) => hit.reference.label)).toEqual(['Genesis 1:1', 'Genesis 1:3']);
    expect(hits[0].text.startsWith('In the beginning')).toBe(true);
  });

  it('ignores queries shorter than two letters', () => {
    expect(searchBible(bible, 'a')).toEqual([]);
    expect(searchBible(bible, ' ')).toEqual([]);
  });

  it('reports where the match is, for highlighting', () => {
    const hits = searchBible(bible, 'beginning');
    expect(hits).toHaveLength(1);
    const hit = hits[0];
    expect(hit.text.substring(hit.matchStart, hit.matchEnd)).toBe('beginning');
  });

  it('whole-word search does not match inside a word', () => {
    // "light" is also inside "delight" in Psalm 1:2.
    expect(searchBible(bible, 'light')).toHaveLength(2);
    const whole = searchBible(bible, 'light', { wholeWord: true });
    expect(whole).toHaveLength(1);
    expect(whole[0].reference.label).toBe('Genesis 1:3');
    expect(searchBible(bible, 'ligh')).toHaveLength(2);
    expect(searchBible(bible, 'ligh', { wholeWord: true })).toEqual([]);
  });

  it('scopes to a testament or a single book', () => {
    expect(searchBible(bible, 'he', { scope: SearchScope.all }).length).toBeGreaterThan(0);
    expect(searchBible(bible, 'follow', { scope: SearchScope.oldTestament })).toEqual([]);
    const nt = searchBible(bible, 'follow', { scope: SearchScope.newTestament });
    expect(nt).toHaveLength(1);
    expect(nt[0].reference.bookCode).toBe('MAT');
    expect(searchBible(bible, 'god', { scope: SearchScope.currentBook, currentBookCode: 'PSA' })).toEqual([]);
    expect(searchBible(bible, 'god', { scope: SearchScope.currentBook, currentBookCode: 'GEN' })).toHaveLength(2);
  });

  it('searches the plain text, not the inline markers', () => {
    // "Follow me." is wrapped in words-of-Jesus markers in the source.
    const follow = searchBible(bible, 'Follow me');
    expect(follow).toHaveLength(1);
    expect(follow[0].reference.label).toBe('Matthew 1:1');
    const formless = searchBible(bible, 'formless and empty');
    expect(formless).toHaveLength(1);
    expect(formless[0].reference.label).toBe('Genesis 1:2');
  });

  it('stops at the limit', () => {
    expect(searchBible(bible, 'the', { limit: 2 })).toHaveLength(2);
  });

  it('a query with regex characters is taken literally', () => {
    expect(searchBible(bible, '(Psalms')).toEqual([]);
    expect(searchBible(bible, 'light."')).toHaveLength(1);
    expect(searchBible(bible, 'man.', { wholeWord: true })).toEqual([]);
  });
});

describe('what the results screen builds on', () => {
  const bible = sampleBible();

  it('groups hits by book in canonical order', () => {
    const grouped = groupHitsByBook(searchBible(bible, 'the'));
    expect([...grouped.keys()]).toEqual(['GEN', 'PSA', 'MAT']);
    expect(grouped.get('GEN')!.length).toBeGreaterThan(1);
  });

  it('cuts a snippet so the match is in view', () => {
    const hits = searchBible(bible, 'beginning');
    expect(snippetOf(hits[0])).toEqual({ prefix: 'In the ', match: 'beginning', suffix: ', God created the heavens.' });

    const far = searchBible(bible, 'wicked');
    const snippet = snippetOf(far[0]);
    expect(snippet.match).toBe('wicked');
    expect(snippet.prefix.length).toBeLessThanOrEqual(far[0].matchStart);
  });

  it('labels every scope', () => {
    expect(searchScopeLabel[SearchScope.all]).toBe('Whole Bible');
    expect(searchScopeLabel[SearchScope.currentBook]).toBe('This book');
  });
});
