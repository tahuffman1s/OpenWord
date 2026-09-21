# Changelog

## 1.8.2

### Fixed
- **The book's name no longer opens every chapter.** Editions that repeat it
  as a running head inside the first paragraph — "GENESISThus the heavens and
  the earth were finished" — were reading that label as Scripture. Text
  sitting before a chapter's first verse is a label, not a verse, and is left
  out.
- **Section headings head the chapter they open.** A heading printed before
  the next chapter begins — "The Flood Subsides", which appears while the
  page is still in Genesis 7 — was stranded at the foot of the chapter
  before. Headings now wait for the Scripture they introduce and go in above
  it, in whatever chapter that turns out to be.
- **Section headings marked only by a class are set as headings**, not as
  ordinary paragraphs: `section-heading`, `subhead` and the rest, not only
  USFM's `s1`.
- **Poetry keeps its indent level.** `q2`, `line2` and `indent-2` were all
  being flattened to a single depth, so the couplets of a psalm stopped
  reading as couplets.

## 1.8.1

### Fixed
- **A whole book arriving as one chapter.** Editions that print the chapter
  number *inside* the paragraph rather than above it — the ESV among them,
  which opens each chapter with
  `<b class="chapter-num" id="v43001001-1">1:1</b>` — had no chapter
  recognised at all, so every verse in the book piled into chapter 1. Chapter
  markers are now read inline as well as at the head of a block, and a marker
  holding "1:1" opens the chapter and its first verse together.
- **A safety net that does not depend on the markup**: when verse numbers run
  backwards — verse 25, then verse 1 — a chapter began, whatever the edition
  did or did not say. An edition this app has never seen now breaks into
  chapters correctly even if nothing marks them.
- A chapter marker that prints nothing has its number read from its `id`,
  including the `v43001001` scheme that packs book, chapter and verse.

## 1.8.0

### Added
- **Import a Bible of your own.** Settings → *Add a translation* takes an EPUB
  of a Bible and converts it, on the device, into a `.bib` file the app then
  reads like any translation that ships with it — search, compare, highlight,
  bookmark, map, book introductions and all. Nothing is uploaded; the file is
  read where it sits.
- **The `.bib` format**: one translation, whole, in one file — the compact
  binary encoding the bundled text already used, behind a header that says
  what the file holds. A shelf of translations can therefore be listed by
  reading a few dozen bytes of each. The format is documented in the README
  and MIT-licensed like the rest of the app, so anything else may read or
  write one.
- `.bib` files import directly, and any imported translation can be saved back
  out as one, from the menu beside it in Settings.

### Changed
- **The three bundled translations are now `.bib` files too**, in place of the
  old `.owb.gz` assets. There is one way to read Scripture in the app rather
  than two, and the format that ships is the format anyone can write. The text
  is unchanged — same verse counts, same layout — and the files are within a
  couple of hundred bytes of the size they were. `tool/build_assets.dart`
  writes `.bib` from USFX and checks that what it wrote reads back.

### Fixed
- **EPUBs from eBible.org — around 1,500 translations, and most of the freely
  available ones — now import.** They label every chapter `psalmlabel`,
  Psalms or not, which nothing recognised, so the whole file came back as
  "no books of the Bible could be found". Their footnotes, which are written
  inline as `<span class="note">`, were also being spliced into the middle of
  the verses they annotate.
- **One-chapter books are no longer lost.** Obadiah, Philemon, 2 and 3 John
  and Jude are usually published with no chapter heading at all, and their
  verses were being dropped without a word. A numbered verse under a book
  heading now opens chapter 1.
- **Project Gutenberg's Bibles read correctly.** They number verses from the
  book up — `41:001:001` is Mark 1:1 — which was being read as chapter 41.
- Chapters numbered with Roman numerals (`CHAPTER XXIII`) are recognised.
- Verse markers that print nothing and carry the number in an `id` are
  recognised, as are bridges like `2-3`.
- A book named nowhere in its own markup is now named from its file name or
  from the table of contents.
- A chapter that came through as one long verse, or whose number had to shift
  because the chapter before it was missing, is now reported in the import
  summary instead of passing silently.

### Notes
- The converter reads the shapes a Bible EPUB comes in — verse numbers
  as marker elements, at the head of a paragraph, or as `chapter:verse` — and
  keeps poetry lines, section headings and italics. It refuses rather than
  guesses: a paragraph opening "40 days later" does not become verse 40, a
  heading that is not a book of the canon is passed over, and a book whose
  verses are not numbered is left out and named in the summary the import
  sheet shows.
- An imported translation's licence is taken from the EPUB's own `dc:rights`.
  Where the file states none, the app says so rather than inventing one.
- Importing the same EPUB twice replaces the copy on the shelf instead of
  stacking up duplicates: the conversion is deterministic.
- The web build has no filesystem to keep translations on, so it reads only
  what it ships with; the import UI is not shown there.

## 1.7.0

### Fixed
- **Updates could not install.** Every release was signed with Flutter's
  debug key, which GitHub's runners generate afresh for each build, so each
  release carried a different signing identity — and Android will not replace
  an app with one signed by another key. The installer gave no reason beyond
  "App not installed". Release builds now take a signing key from a
  repository secret (or `android/key.properties` locally), the workflow
  prints the certificate it signed with, and a release built without the
  secret says in its notes that it cannot update in place. See "Releases and
  signing" in the README.
- **Granting permission to install no longer throws.** Asking Android for
  permission to install apps means leaving for a settings screen; the app
  used to report a failure at that point and lose the install. It now waits,
  and goes ahead by itself when the reader comes back with the permission
  granted.
- Where a release really is signed with a different key than the installed
  copy, the app compares the two certificates before handing anything to the
  installer, explains what is wrong, and offers to open the release page or
  remove the old copy — with a reminder to copy a backup first.

## 1.6.0

### Changed
- **The map moves.** Drag to pan, pinch or scroll to zoom, double-tap to zoom
  in, with buttons for zoom and back-to-the-passage and a scale bar in the
  corner. It goes from the whole biblical world down to half a metre to the
  pixel, and the lettering stays the same size all the way: the map is drawn
  at each zoom rather than scaled like a photograph.
- **Ten times the detail when you zoom in.** The 1:10m Natural Earth
  coastlines, lakes and rivers now come in past a country or two, along with
  built-up areas and the towns that are there now, so a close-up of an inland
  site has some country around it. All bundled; still no tiles, still no
  connection.
- The list of places under the map scrolls sideways in a single row. Wrapped
  rows of long names were being cut off at the bottom of the sheet.

### Added
- What the open data knows about each place: its kind, the modern site it is
  identified with, what other translations call it, the source's own note, its
  coordinates and how many verses name it in all.
- **The verses of the chapter that name it**, as links. Tapping one closes the
  map and scrolls the chapter to that verse.
- Choosing a place from the list brings it to the middle of the map.

## 1.5.0

### Added
- **Updates from GitHub.** OpenWord asks GitHub once a day whether a newer
  release is out and mentions it in a snack bar you can ignore, with the
  release notes a tap away. On Android it downloads the APK, with progress,
  and hands it to the system installer, which asks you to confirm — nothing
  installs silently. Everywhere else it offers the release page.
- Settings → Updates: the switch that turns the check off, the version you are
  running, when it last looked, and a "Check now" button. A version can also
  be skipped, which quiets the launch announcement without hiding it in
  Settings.

### Changed
- This is the first release that uses the network at all. The Android build
  now asks for `INTERNET` and `REQUEST_INSTALL_PACKAGES`, and the macOS build
  carries the outgoing-network entitlement. Turning the check off in Settings
  leaves the app entirely offline again; the Scripture, the introductions and
  the maps are still bundled and are never fetched.

## 1.4.0

### Added
- **Maps.** A chapter that names somewhere on the ground says so above its
  number — *8 places* — and opens a map of them: coastline, lakes and rivers,
  a marker for each place, pinch to zoom, and a tap on a marker or a name for
  its type and coordinates. A hollow marker is a location scholars have not
  settled. The places are
  [OpenBible.info Bible Geocoding](https://github.com/openbibleinfo/Bible-Geocoding-Data)
  (CC BY 4.0) and the base map is [Natural Earth](https://www.naturalearthdata.com/)
  (public domain); both are bundled, so the maps work with no connection like
  everything else here.

### Changed
- Book introductions are laid out as an outline: the opening paragraphs, then
  the book's own sections — Setting, Summary, Author, Meaning and Message —
  each folded away until it is wanted, instead of several screens of unbroken
  prose.

### Fixed
- Pressing a book in the navigator while the list was still moving left the
  highlight behind, hanging over the header after the book itself had scrolled
  away. The highlight now belongs to its row and is clipped to the list, in
  the navigator and in the library and search lists as well.
- The reader no longer draws a scrollbar down the margin of the text.
- A heading inside a book introduction was rendered as body text: the style
  reached the paragraph but not the span inside it.

## 1.3.0

### Added
- A proper introduction to every book of the Protestant canon, opened from the
  book's name above the chapter number: a few hundred words on its setting,
  authorship, structure and themes, with sub-headings, in place of the
  four-line editorial note that was there before. These are the
  [Aquifer Open Study Notes book introductions](https://github.com/BibleAquifer/AquiferOpenStudyNotesBookIntros)
  — an adaptation by Mission Mutual of Tyndale Open Study Notes © 2023 Tyndale
  House Publishers, both CC BY-SA 4.0. They ship with the app as one 200 kB
  asset, read only when a book sheet is opened, so nothing here needs a
  network connection either.
- The attribution the licence requires, in the book sheet and under Settings →
  About.

### Changed
- The app's own book notes are now only for the deuterocanonical books, which
  the introductions do not cover.

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
