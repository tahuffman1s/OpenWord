# Changelog

## 1.2.0

### Fixed
- Paragraphs are indented the way the translation asks. A translation that
  sets every paragraph flush to the margin (`\m`, which the Berean Standard
  Bible uses throughout) was being given a first-line indent as though it were
  `\p`, and `\pi` paragraphs were not indented as blocks at all. A paragraph
  that opens a passage — the first in a chapter, or the one after a heading —
  is now set flush, as printed Bibles do.
- The chapter and verse grids open at what you are reading. Reaching for the
  chapter list in Psalm 119 used to start at chapter 1, with the highlighted
  chapter far below the fold.

### Added
- Citations are tappable. Where a translation cites another passage — in a
  footnote, or in the parallel-passage line under a heading — the reference
  becomes a link that takes you there. Matching is built from the books
  actually loaded and needs a book name followed by a number, so ordinary
  prose is left alone.
- A background note for every book, opened from the book's name above the
  chapter number: where it sits in the canon, how long it is, its genre, who
  it is ascribed to and by whom, the period it is set in, and a short summary.
  It says plainly that it is an editorial summary and that traditional
  authorship is tradition.
- Speaker labels (`\sp`), as in Job's dialogue, are set as titles rather than
  run in as prose.

## 1.1.0

### Completely offline
- Three public-domain translations now ship inside the app — the World English
  Bible, the Berean Standard Bible and the World English Bible, British
  Edition — so there is no first-launch download and no network code at all.
  The Android build no longer requests the internet permission and the macOS
  build no longer carries the network entitlement.
- The bundled text is a compact binary rather than JSON: about 75 ms to load
  instead of 1.5 s, and a peak heap of tens of megabytes instead of hundreds.

### Navigation
- The alphabet rail is gone. In its place is a single field that both filters
  the book list and parses references: `jn 3:16`, `1 co 13`, `ps 23`, `gen1:1`
  and `Genesis 1 2` all resolve, with out-of-range chapters and verses clamped
  to what the book has. Choosing a book leads to chapter and verse grids, and
  a one-chapter book opens straight away.
- Books are grouped by division (Law, History, Gospels …) or sorted A–Z, with
  numbered books under their name.

### Added
- Compare two translations verse by verse, in columns on a wide window and
  stacked on a phone.
- Highlights in five colours alongside bookmarks and notes, any combination on
  one verse; highlights tint the text where it flows.
- A library screen with bookmarks, highlights, notes and recently read
  chapters.
- Search scoped to the whole Bible, a testament or the current book, with an
  optional whole-word match and results grouped by book.
- Backup and restore: copy everything as JSON to the clipboard and paste it
  back anywhere; restoring merges by recency instead of overwriting.
- A display sheet in the reader for size, spacing, typeface and comparison
  without leaving the page.
- Parallel-passage references (`\r`) are kept and set apart from headings.

### Fixed
- Jumping to a verse in another chapter landed at the top of that chapter: the
  page change discarded the verse before the chapter could scroll to it.
- Jumping to a verse inside a paragraph did nothing, because only verses that
  begin a paragraph carry a scroll anchor; it now scrolls to the paragraph
  holding the verse.
- Section headings were being absorbed into the text of whichever verse
  preceded them, which showed up in the compare view, in search results and
  when copying a verse.

## 1.0.0

First release.

### Reading
- Downloads the **World English Bible** (public domain) on first launch and
  reads entirely offline afterwards. Mirrors are tried in order; the British
  edition (WEBBE) is offered as an alternative.
- Keeps the translation's own typesetting, parsed from USFX: prose paragraphs
  that verses flow through, poetry indented by level, psalm titles, section
  headings, stanza breaks, words of Jesus in red, translator additions in
  italics and tappable footnotes.
- Verse numbers set as superscripts, and hanging in the margin on poetry lines
  so a wrapped line returns to its own indent.
- Literata bundled (SIL OFL, subset) so the reading face is the same on every
  platform.
- Full-text search; chapter-to-chapter swiping, with arrow and page keys on
  desktop.

### Navigation
- A Niagara-launcher-style index rail on the trailing edge, text to its left:
  nearby labels swell and slide toward the touch point, the entries under the
  focused label fan out beside it, sliding left hovers one and lifting picks
  it. Lifting on the rail leaves the group open to tap.
- Books A–Z, with numbered books sorted under their name (1 Samuel under S),
  plus a canonical-order mode. Chapters and verses indexed by tens over a
  number grid.

### Bookmarks and resume
- Tap a verse to bookmark, annotate or copy it. Bookmarked verses are tinted
  in the text and flagged in the pickers.
- The book, chapter and the verse nearest the top of the screen are saved as
  you read and restored on the next launch, alongside a recently-read list.

### Theming
- Material You: dynamic colour from the system palette where the platform
  provides one, a seed-colour picker everywhere else, light/dark/system.
- Adjustable text size, line spacing and typeface; red-letter, footnote,
  verse-number and paragraph-layout switches; optional deuterocanonical books.

### Platforms
Android, iOS, Linux, macOS, Windows and the web from one codebase. The web
build re-fetches the text each session (no durable multi-megabyte store) and
relies on the browser's HTTP cache; every other platform caches to disk.
