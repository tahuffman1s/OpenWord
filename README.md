# OpenWord

A free and open source Bible reader, built with Flutter and themed with
Material You. One codebase runs on Android, iOS, Linux, macOS, Windows and the
web.

**Everything is offline.** Three public-domain translations ship inside the
app, so there is no download step, no account, no telemetry — the Android
build does not even ask for the internet permission, and the macOS build has
no network entitlement.

## Features

- **Printed-Bible layout.** The text is built from USFX, so the translation's
  own structure survives: prose paragraphs that verses flow through, poetry
  indented by level, psalm titles, section headings and their parallel-passage
  references, stanza breaks, the words of Jesus in red, translator additions in
  italics and tappable footnotes. Verse numbers are superscripts, and hang in
  the margin on poetry lines so wrapped lines keep their indent.
- **Go to anything in one field.** Type `jn 3:16`, `1 co 13`, `ps 23` or just
  `mat` and the navigator offers the jump; the same field filters the book
  list, which is grouped by division or sorted A–Z, and leads on to chapter
  and verse grids.
- **Compare two translations** verse by verse, in columns on a wide window and
  stacked on a phone. The second translation is loaded only while you are
  comparing.
- **Highlights in five colours, bookmarks and notes**, any combination on the
  same verse. Highlights tint the text in place; bookmarked and annotated
  verses are flagged in the margin and in the pickers.
- **Updates from GitHub.** OpenWord asks GitHub once a day whether a newer
  release is out, shows what is in it, and on Android downloads and hands it
  to the system installer. It is the only thing here that uses the network,
  and Settings can turn it off.
- **Maps of the places a chapter names**, drawn from open data and bundled
  with the app. Drag, pinch, scroll or double-tap to move about; tap a place
  for what the data knows about it and for the verses of the chapter that name
  it. Locations scholars dispute are marked as such.
- **Context where the translation offers it.** Citations in footnotes and in
  parallel-passage lines are links — tap `Ezekiel 34:11` under the heading of
  Psalm 23 and you are there. Every book also opens an introduction from its
  name above the chapter number — canon division, length, and a full essay on
  the book's setting, authorship, structure and themes.
- **Bring your own translation.** Import an EPUB of a Bible and OpenWord
  converts it to a `.bib` file — its own single-file format — and reads it
  like the ones that ship with it: search, compare, highlight, bookmark, map
  and all. `.bib` files import directly, and any imported translation can be
  saved back out as one.
- **The Hebrew and Greek behind any verse.** Tap a verse and it offers the
  original: every word with its Strong's number, how it is said, and its
  parsing spelled out. Tap a word for Strong's own entry, and from there
  every other verse it occurs in. Tap an English word and the word it most
  likely came from lights up. It works under *any* translation — the three
  that ship and any you import — because it is keyed to the verse, not to
  one edition's wording.
- **Cross-references on every verse.** Tap a verse and it offers the places
  Scripture takes up what it says — three hundred thousand of them, from the
  Treasury of Scripture Knowledge, grouped under the phrase that prompted
  each one and carrying the words they point at, so the list reads without
  leaving it. Tap one to go there. Bundled, like everything else.
- **Reading plans that wait for you.** Six plans, from the Gospels in 30
  days to the whole Bible in a year, with the Old and New Testament side by
  side or Psalms and Proverbs by the month. Days are even in length rather
  than in chapters, and are numbered rather than dated, so a plan starts
  whenever you start it and a missed day is still there tomorrow instead of
  piling up. The end of each chapter in today's reading has one button:
  *Done — next: Matthew 2*. Fall two days behind and the plan says so once,
  kindly, with *Pick up from today*; it never marks anything read for you.
- **Your library** in one place: bookmarks, highlights, notes and the chapters
  you have been reading, each a tap away from the text.
- **Search** the whole Bible, one testament or the book you are in, with an
  optional whole-word match, results grouped by book and the match emphasised
  in context.
- **Resume where you left off.** The book, chapter and the verse nearest the
  top of the screen are saved as you read and restored on the next launch.
- **Backup without an account.** Copy everything you have saved as JSON to the
  clipboard and paste it back on another device; restoring merges rather than
  overwrites.
- **Material You.** The palette follows the system wallpaper where the platform
  provides one, with a seed-colour picker everywhere else. Light, dark and
  system themes; adjustable text size, line spacing and typeface, reachable
  from the reader itself.

## Scripture text

| | Abbreviation | Licence |
|---|---|---|
| [World English Bible](https://ebible.org/web/) (default) | WEB | Public domain |
| [Berean Standard Bible](https://berean.bible/) | BSB | Public domain |
| [World English Bible, British Edition](https://ebible.org/webbe/) | WEBBE | Public domain |

The WEB edition includes the deuterocanonical books, which are hidden by
default and can be switched on in Settings.

Each one is built from [USFX](https://ebible.org/usfx/) — the XML form of USFM
— into a [`.bib` file](#importing-a-translation-epub-and-bib), the same format
an imported translation takes. There is one way to read Scripture here, not
two: the three that ship are `.bib` files under `assets/bible/`, and one the
reader brings is a `.bib` file in the app's documents. Adding another freely
licensed USFX translation takes two steps:

```bash
# 1. add an entry to lib/src/data/translations.dart, then
dart run tool/build_assets.dart <directory-with-usfx-files>
```

`tool/build_assets.dart` writes `assets/bible/<id>.bib`, checking that what it
wrote reads back — both the header and the same verse count behind it. It
takes the USFX in whatever shape its publisher hands it over: eBible.org's
`eng-web_usfx.zip`, the `eng-web_usfx.xml` inside it, or a renamed
`eng-web.usfx.xml` all work, so there is nothing to unpack or rename first.

### Rebuilding the three that ship

The typography the reader can draw — heading levels, the divine name in
small capitals, tables, lists, acrostic letters, speakers, printed verse
labels, omitted verses — is read out of the USFX at build time, so a
translation only gains it when it is rebuilt. All three come from eBible.org,
under the names eBible gives them; the tool knows `eng-webbe` is
`eng-gb-webbe` and `engbsb` is `eng-bsb`, and finds the USFX among the other
files in each zip:

```bash
mkdir -p /tmp/usfx && cd /tmp/usfx
curl -O https://ebible.org/Scriptures/eng-web_usfx.zip
curl -O https://ebible.org/Scriptures/eng-webbe_usfx.zip
curl -O https://ebible.org/Scriptures/engbsb_usfx.zip
cd /path/to/OpenWord && dart run tool/build_assets.dart /tmp/usfx
```

Then `dart run tool/bib_lint.dart assets/bible/*.bib` before committing the
result.

## Importing a translation: EPUB and `.bib`

Settings → *Add a translation* takes a file from the device, and every
translation's menu offers *Save a copy…* — the three that ship as well as
anything imported, since a format only one app can write is that app's
cache rather than a format. *Save a copy with cross-references…* writes the
app's reference set into the file first, so the copy carries them wherever
it is opened rather than needing this app's assets. Nothing is
uploaded: the file is read where it sits, converted on the device, and kept in
the app's own documents directory. An imported translation is then a
translation like any other — it appears in the translation list and the
compare chips, and search, maps, highlights, bookmarks and notes all work
against it.

### The `.bib` format

A `.bib` file is one translation, whole, in one file. It is what the app
ships its own three translations as, and what an import is converted to.
The full specification is [`docs/bib-format.md`](docs/bib-format.md); what
follows is the shape of it.

A six-byte header and then a stream of chunks, each saying how long it is,
what it is, and what it should check out to:

| Size | Meaning |
|---|---|
| 4 | Tag, four ASCII letters |
| 4 | Payload length |
| 4 | CRC-32 of the payload |
| … | Payload |

**The case of a tag's first letter says what to do with a chunk you do not
recognise**, the rule PNG uses. Upper case is critical: a reader that meets
an unknown one must refuse the file. Lower case is ancillary: skip it and
carry on. That single rule is what lets the format grow — `xref` carries
cross-references, `strg` the Hebrew and Greek, `srch` a search index, and
`sign` is reserved for a signature; a file carrying any of them still
opens in a reader written before they existed.

Two chunks are defined, both critical. `META` is UTF-8 JSON and comes
first, so a shelf of translations is listed by reading a few hundred bytes
of each rather than opening any of them. It carries the identity and
licence, and three things worth saying out loud:

- **`language`, `script` and `direction`** — a Hebrew or Arabic Bible
  renders right to left because its file says so.
- **`versification`** — everything anchored to a verse, the
  cross-references and the interlinear included, is anchored to one
  numbering, and Bibles do not share one. A file that does not say can be
  mis-anchored with nothing appearing to go wrong, which is the worst way
  for it to go wrong. **An import is measured rather than trusted** — see
  below.
- **`contentHash`** — SHA-256 of the Scripture, so two copies can be told
  apart without comparing megabytes.

`TEXT` holds the Scripture as an outline of every book followed by one gzip
member per book. **The outline is the point.** It carries which books,
how many chapters, and how long each chapter is — so the book list, the
chapter grid and the verse grid are all drawn without unpacking a word, and
a book is found and unpacked on its own when it is actually read. Opening
the World English Bible touches none of its 80 books; reading John unpacks
John.

Per-book compression costs 4% against one stream over the whole Bible
(1.69 MB → 1.76 MB) and buys unpacking 25 kB to open Genesis instead of
5 MB. Finer does not pay: per chapter costs 37%, and a shared preset
dictionary does not win it back.

Version 1 — one gzip stream, a fixed header, no outline — is still read, so
a shelf full of them keeps working. `dart run tool/upgrade_bib.dart
<file.bib>` rewrites one as version 2, comparing the result with the
original verse by verse before replacing it.

```bash
dart run tool/bib_lint.dart <file.bib>     # check one
dart run tool/build_bib_corpus.dart        # rebuild test/corpus/
```

`bib_lint` reports the version, the chunks, whether every checksum matches,
whether the outline agrees with the text it stands for, and whether the
metadata describes what is actually in the file.
[`test/corpus/`](test/corpus/) holds small files named for what a reader is
supposed to do with each — the ones that must read alike, the unknown
ancillary chunk that must be skipped, the unknown critical chunk that must
not be, and the damaged, truncated, too-new and not-a-`.bib` files that
must be refused — so another implementation has a fixed point to test
against.

It is implemented in `lib/src/model/bib_file.dart` and
`lib/src/model/bible_codec.dart`, both MIT like the rest of the app. It is
a reading format, not an archival one: it keeps what a reader displays, not
the full semantics of the USFM behind it.

### Composing the text

All text in a `.bib` is Unicode NFC. Unicode can spell the same word more
than one way — `é` as one codepoint or as `e` plus a combining acute,
Hebrew with two points on a letter in either order — and the spellings look
identical on the page while being different bytes. A reader typing what
they see would get nothing back, with nothing anywhere to explain it. So
imported text is composed on the way in, and a search query is composed
the same way before it is used.

### Checking the verse numbering

The cross-references and the Hebrew and Greek are keyed to the verse, not
to an edition's wording, so they apply to an imported translation as much
as to the three that ship. That only holds while the numbering agrees.
Point them at a Bible that counts a psalm's superscription as its first
verse, or divides Joel the Hebrew way, and they do not fail — they land on
the wrong verse, confidently, which is worse.

A translation can also sidestep the whole question by **bringing both
layers itself** — cross-references in the `xref` chunk, the Hebrew and
Greek in `strg`, each keyed to its own numbering. The app prefers those
over the bundled ones, so a differently-numbered Bible gets what is right
for it rather than nothing at all, and a `.bib` needs none of this app's
assets to be read with its study layers intact.

```bash
dart run tool/attach_xrefs.dart     <file.bib> <xrefs.owx.gz>
dart run tool/attach_originals.dart <file.bib> <originals.ows.gz>
```

In the app, a translation's menu offers *Save a copy with the study
layers…*, which does both to a copy. **The layer is cut to the verses the
file has**: written into a New Testament it carries the Greek and not the
whole Hebrew Bible, which takes it from 3.94 MB to 1.08 MB — 0.15 MB for a
single gospel — and drops every dictionary entry and concordance line that
only the missing verses reached.

Otherwise an import is measured. Its per-chapter verse counts are compared with
the English scheme (`lib/src/model/versification_table.dart`, generated
from the Berean Standard Bible, since that is what the cross-references
were anchored to), and where it does not match, the translation is marked
`other` and those two layers are not offered for it. The import says so,
and so does Settings, rather than leaving a reader to notice that a
feature quietly went missing.

That is the app's default, not its verdict. Whether a reference that may be
out by a verse beats no reference is a judgement about a book the reader has
open in front of them, so they get to make it: the translation's menu offers
*Cross-references and originals anyway*, and Settings then says the layers
are on at their word and what to expect of them. Exporting a `.bib` with the
layers in it is refused until they have said so, since baking them into a
file they do not fit puts the mistake beyond the reach of whoever reads it
next.

The line sits at 2% of chapters, which is where the evidence puts it:

- Editions of the English Bible disagree with each other a little. The
  three bundled here differ over **2 of 1189 chapters — 0.17%** — which is
  Romans' floating doxology, and nothing else.
- A difference in *scheme* is nothing like that small. Counting psalm
  superscriptions moves something like a hundred chapters of the Psalms on
  its own, over 8%; Septuagint psalm numbering moves more.

Only the sixty-six books of the Protestant canon are compared. English
editions that agree about everything else disagree about the
deuterocanon — the three bundled here differ over Greek Esther, Sirach,
Baruch and 4 Maccabees — so counting those would raise a false alarm on an
ordinary import. A Bible too small to judge, under 100 comparable
chapters, is left as `unknown` and keeps both layers: saying nothing is
not the same as failing.

```bash
dart run tool/build_versification.dart   # regenerate the table
```

### What the EPUB converter does

`lib/src/data/epub_import.dart` unzips the EPUB, follows
`META-INF/container.xml` to the package document, and reads the spine in
order.

**Naming the books.** A heading names a book however it dresses it up —
`THE REVELATION OF ST. JOHN THE DIVINE`, `The First Epistle of Paul the
Apostle to the Corinthians`, `II Timothy`. Where a document names no book,
its file name is tried (`GEN.xhtml`, `01_Genesis.xhtml`), and then what the
table of contents — the EPUB 3 nav or `toc.ncx` — calls it.

**Finding the chapters.** A heading that numbers one, in digits or Roman
numerals (`CHAPTER XXIII`); or an element the markup itself calls a chapter
label, in which case the number is taken wherever it falls, so `Kapitel 3`
and `Psaume 23` work as well as `Chapter 3`. That label may sit inside the
paragraph rather than above it — the ESV opens each chapter with
`<b class="chapter-num" id="v43001001-1">1:1</b>`, which gives the chapter
and its first verse at once. Failing all of that, verse numbers that run
backwards mean a chapter began: it is the one signal that holds whatever an
edition does. A book whose verses start with
no chapter heading at all opens chapter 1 — which is how Obadiah, Philemon,
2 and 3 John and Jude are usually published.

**Finding the verses.** A marker element — `<sup>`, a span classed `verse`,
`v`, `vn` or `versenum`, or an `id` like `V3` — including one that prints
nothing and carries the number only in its `id`, which is how editions that
draw verse numbers with a stylesheet do it. A bridge like `2-3` opens at the
first of the two. Failing a marker: a number at the head of a paragraph
(only where it carries on from the verse before), `chapter:verse`, or
Project Gutenberg's `book:chapter:verse` — `41:001:001` is Mark 1:1, not
chapter 41.

Poetry lines keep the indent level their markup gives them (`q2`, `line2`,
`indent-2`), section headings are recognised by class as well as by tag and
wait for the Scripture they introduce — so a heading printed before the next
chapter starts heads that chapter rather than trailing the one before — and
italics are kept. Text sitting before a chapter's first verse is treated as a
label rather than Scripture, which is how a running head like `GENESIS` at
the top of a chapter is kept out of verse 1. Footnotes are dropped,
including the inline pop-up kind, so a note's text never lands in the middle
of the verse it annotates.

It refuses rather than guesses. A paragraph opening "40 days later" does not
become verse 40; a heading that is not a book of the canon is passed over; a
book whose verses are not numbered is left out and named in the summary the
import sheet shows. A file with no books of the Bible in it is rejected
outright, and the licence is taken from the EPUB's own `dc:rights` — where
there is none, the translation says its licence is not stated rather than
inventing one. Where it cannot do a clean job it says so in the summary: a
chapter that came through as one long verse, or one whose number had to
shift because the chapter before it was missing, is reported rather than
left for the reader to discover.

The conversion is deterministic: the same EPUB imports under the same id
twice, so importing it again replaces the copy on the shelf instead of
stacking up duplicates.

### Where to find EPUB Bibles

- [eBible.org](https://ebible.org/download.php) — around 1,500 translations,
  most of the freely licensed ones there are, each as an EPUB with no DRM.
  These are generated by [haiola](https://github.com/kahunapule/haiola), and
  the converter is tested against its exact output.
- [Project Gutenberg](https://www.gutenberg.org/ebooks/10) — the KJV, the
  Douay-Rheims and others, in the `book:chapter:verse` shape above.
- [ereaderbibles.com](https://ereaderbibles.com/) and
  [bmaupin/epub-bibles](https://github.com/bmaupin/epub-bibles) — EPUBs
  prepared for e-readers.
- [Wikisource](https://en.wikisource.org/wiki/Bible) — public-domain
  editions, exportable as EPUB.

Bibles bought from a bookshop (NIV, ESV and the like) carry DRM and cannot
be read by this or any other tool that did not sell them.

## Book introductions

Each of the sixty-six books of the Protestant canon opens with an
introduction of a few hundred words. These are the
[Aquifer Open Study Notes book introductions](https://github.com/BibleAquifer/AquiferOpenStudyNotesBookIntros)
— an adaptation by Mission Mutual of Tyndale Open Study Notes © 2023 Tyndale
House Publishers, both licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). They ship as
one gzipped JSON asset (about 200 kB) and are read only when a book sheet is
opened. The deuterocanonical books are not covered by that resource, so they
fall back to the short notes in `lib/src/data/book_notes.dart`.

To rebuild the asset from source:

```bash
mkdir -p intros && cd intros
for i in $(seq -w 1 66); do
  curl -sSLO "https://raw.githubusercontent.com/BibleAquifer/AquiferOpenStudyNotesBookIntros/main/eng/md/$i.content.md"
done
cd .. && dart run tool/build_notes.dart intros
```

It writes `assets/notes/book-intros-eng.json.gz`, dropping each file's licence
preamble and title line — the licence is shown by the app from its own copy,
in the book sheet and in Settings, as CC BY-SA requires.

## The original languages

Tapping a verse offers *Hebrew* or *Greek*. The sheet shows the verse's own
words — pointed Hebrew, accented Greek — each with its transliteration and
Strong's number, and lays the English above them: tap an English word and
the original it most likely came from lights up; tap an original word for
Strong's definition, derivation and King James renderings, and from there a
concordance of every verse it occurs in, shown in whatever translation is
open.

**Why it works under any translation.** Strong's numbers tag the original
words, so a per-word English mapping only exists for editions someone has
tagged — which is why other apps bolt their interlinear to one translation.
This layer is keyed by *verse* instead. The Hebrew of Genesis 1:1 is the
same whichever English sits on top of it, so the WEB, the BSB, the WEBBE and
anything imported all get the same original, with no tagging of their own.

**Tying an English word to an original one** is the part that cannot be
exact. Strong's lists the words the King James translators used for each
number, and a tapped word is looked for in those lists, with light stemming
so "created" finds "create". Where nothing matches it says so rather than
lighting a plausible wrong word. For a translation far from the KJV's
vocabulary it will match less often; it will not match wrongly more often.

**Versification.** Hebrew numbering differs from English — Psalm
superscriptions are counted, Joel and Malachi divide their chapters
differently, and some forty other places. The Open Scriptures Hebrew Bible
ships `VerseMap.xml`, an authoritative WLC-to-English map, and the build
applies it, so Malachi 4:1 finds the words that Hebrew calls Malachi 3:19.

**What it does not cover**: the deuterocanonical books, which are in neither
the Hebrew Bible nor the Greek New Testament as this app carries them. Those
verses simply do not offer the option.

446,925 words and 14,197 dictionary entries come to 3.9 MB. The file is
gunzipped once into a byte array that stays put, and a verse's words are
decoded only when that verse is looked at — holding them all as objects
would cost more memory than the Scripture itself.

To rebuild it:

```bash
git clone https://github.com/openscriptures/morphhb
git clone https://github.com/byztxt/byzantine-majority-text
git clone https://github.com/openscriptures/strongs
dart run tool/build_strongs.dart morphhb byzantine-majority-text strongs
```

It writes `assets/strongs/originals.ows.gz` and reads back what it wrote.
The Greek arrives as two files that align word for word — one accented, one
carrying the numbers and parsing — and the build checks that alignment for
every verse rather than assuming it.

**The typeface this needs.** Literata, the reading face, has Latin and Greek
and stops there. The Hebrew needs a face with the vowel points and all
thirty-one cantillation marks, and the transliterations need thirteen
modifier letters no reading face carries — the turned comma for ayin, the
apostrophe for aleph, the superscript vowels. Without them the app draws
boxes, and the web, which has no system fonts to fall back on, draws nothing
but boxes. So the two gaps are cut out of Noto Serif Hebrew and Noto Serif,
which share metrics, and merged into one 16 kB face:

```bash
pip install fonttools brotli
git clone https://github.com/notofonts/hebrew   # sources/, or a built TTF
python3 tool/build_scripture_font.py NotoSerifHebrew.ttf NotoSerif.ttf
```

It writes `assets/fonts/ScriptureSerif-Subset.ttf` and refuses to declare
success if the coverage came out short. `test/scripture_font_test.dart`
reads the shipped file's `cmap` and checks the same thing, so a bad rebuild
cannot reach a release unnoticed.

## Cross-references

Tapping a verse offers *N cross-references*, and the sheet sets them out the
way the Treasury of Scripture Knowledge does: grouped under the phrase of the
verse that prompted them, rather than as one flat list. Each carries the text
it points at, taken from the translation being read, so a list of twenty can
be read through without opening any of them; tapping one goes there.

The data is the [CrossReferences.org](https://crossreferences.org) export of
the TSK, re-anchored so that each translation has its own phrases and its own
versification — this app reads the Berean Standard Bible columns, since the
BSB is one of the three it ships. 305,935 references across 29,057 verses,
built into a 1.3 MB asset: a table of the phrases (which repeat endlessly —
"the LORD", "God") and LEB128 varints for the rest. It is read in a
background isolate the first time a verse is opened.

To rebuild it:

```bash
git clone https://github.com/CrossReferences-org/bible-cross-references
dart run tool/build_xrefs.dart bible-cross-references/json
```

It writes `assets/refs/xrefs.owx.gz` and reads back what it wrote before
declaring success.

## Maps

A chapter that names somewhere on the ground says so above its number — *5
places* — and opens a map of them. The map behaves as a map should: drag to
move, pinch or scroll to zoom, double-tap to zoom in, buttons for zoom and for
back-to-the-passage, and a scale bar. It zooms from the whole of the biblical
world down to half a metre to the pixel; the lettering stays the same size
however far in you go, because it is drawn rather than scaled.

Tap a marker, or a name in the row under the map, and you get what the open
data knows about the place — what kind of place it is, the modern site it is
identified with, what other translations call it, the source's own note, its
coordinates, how many verses name it in all — and the verses of *this* chapter
that name it, each one a link into the text.

- Places: [OpenBible.info Bible Geocoding](https://github.com/openbibleinfo/Bible-Geocoding-Data),
  CC BY 4.0 — every place named in the Protestant canon, the verses naming it,
  competing identifications and how confident each is. 1,276 of them resolve
  to a point and reach the app, over 852 chapters. A location scholars have
  not settled is drawn as a hollow marker and labelled as uncertain.
- Base map: [Natural Earth](https://www.naturalearthdata.com/), public domain,
  by way of [natural-earth-geojson](https://github.com/martynafford/natural-earth-geojson).
  The 1:50m land, lakes and rivers cover the whole region for the zoomed-out
  view; the 1:10m ones, plus built-up areas and the towns that are there now,
  are drawn once you zoom in past a country or two, so that a close-up of an
  inland site is not a blank page.

Everything is clipped to the world the Bible names, simplified with
Ramer–Douglas–Peucker, and written as one 600 kB asset — read in a background
isolate the first time a chapter is opened. No tiles are fetched and nothing
needs a connection.

```bash
git clone --depth 1 https://github.com/openbibleinfo/Bible-Geocoding-Data
git clone --depth 1 https://github.com/martynafford/natural-earth-geojson
dart run tool/build_maps.dart Bible-Geocoding-Data natural-earth-geojson
```

## Releases and signing

Android will only replace an installed app with one signed by **the same
key**. The Flutter debug keystore is generated afresh on every machine, so a
debug-signed release can never update the one before it — the installer just
says "App not installed". Releases therefore need one key that outlives the
machine that built them.

The key is never in the repository. `android/app/build.gradle.kts` looks for
it in `android/key.properties` (for a local release build) or in the
environment (for CI), and falls back to the debug key with a warning in the
build log.

Make one once:

```bash
keytool -genkeypair -v -keystore openword.jks -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias openword
base64 -w0 openword.jks   # paste this into the secret below
```

Keep `openword.jks` somewhere safe and backed up: lose it and the same thing
happens again. Then add four repository secrets (Settings → Secrets and
variables → Actions):

| Secret | What goes in it |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 of `openword.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `openword` |
| `ANDROID_KEY_PASSWORD` | the key password (the same one, unless you set two) |

Or from a terminal, which keeps them off the clipboard:

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < openword.jks.base64.txt
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS --body openword
gh secret set ANDROID_KEY_PASSWORD
```

For a local release build, write `android/key.properties` instead — it is
git-ignored:

```properties
storeFile=/absolute/path/to/openword.jks
storePassword=…
keyAlias=openword
keyPassword=…
```

The release workflow prints the certificate of the APK it built, so the key
in use can be checked against the last release. Where the secret is missing
it still builds, and the release notes say the APK cannot update in place.

**Moving from an unsigned release to a signed one** is a one-off: copy a
backup from Settings → Bookmarks, highlights and notes, remove the copy you
have, install the new APK, then restore the backup. The app now detects this
case itself — it compares the certificate of the download with the installed
one and explains it, rather than leaving you with "App not installed".

## Updates

Releases are published on GitHub, and the app can find them itself.

- Once a day, and on launch, it reads
  `api.github.com/repos/tahuffman1s/OpenWord/releases/latest` — one small JSON
  document — and mentions a newer version in a snack bar you can ignore. The
  version is compared numerically, so `1.10.0` is newer than `1.9.0`, and
  pre-releases and drafts are skipped.
- On **Android** it downloads the APK from the release, with progress, into
  its own cache and hands it to the system package installer, which asks you
  to confirm. Nothing is installed silently — a sideloaded app cannot do that,
  and this one does not try. The first time, Android asks for permission to
  install apps; granting it returns to the app and the install carries on by
  itself. If the release turns out to be signed with a different key than the
  copy on the device, the app says so and offers the way through, rather than
  letting the installer fail with "App not installed" (see above).
- Everywhere else it offers the release page, since desktop archives are
  unpacked wherever you keep them and the Apple builds need a signing identity
  the project does not have.
- **Settings → Updates** turns the whole thing off, after which the app makes
  no network calls at all. The version it reports lives in
  `lib/src/app_version.dart`, and a test fails if it drifts from
  `pubspec.yaml`.

This is why the Android build now asks for `INTERNET` and
`REQUEST_INSTALL_PACKAGES`, and the macOS build carries the outgoing-network
entitlement. Nothing else here touches a network: the Scripture, the
introductions and the maps are all bundled, and importing a translation reads
the file the system picker hands over without sending it anywhere.

## Building

Requires the Flutter SDK (3.47 or newer; Dart 3.13+).

```bash
flutter pub get

flutter run                       # whatever device is attached
flutter build apk --release       # Android
flutter build ipa                 # iOS
flutter build linux --release     # Linux
flutter build macos --release     # macOS
flutter build windows --release   # Windows
flutter build web --release       # web
```

Tagged builds for Android, Linux, Windows and the web are attached to each
[release](https://github.com/tahuffman1s/OpenWord/releases); see
[CHANGELOG.md](CHANGELOG.md).

### Checks

```bash
flutter analyze
flutter test
```

## Self-hosting the web build

`deploy/` holds an nginx image and a Cloudflare Tunnel, which between them
put the app on your own domain from a Raspberry Pi with no port forwarded
and no inbound firewall hole — cloudflared only ever dials out.

```bash
cd deploy
cp .env.example .env        # put your tunnel token in it
docker compose up -d
```

The token comes from the Cloudflare dashboard, under Zero Trust → Networks →
Tunnels → Create a tunnel → Cloudflared: copy the value after `--token` in
the install command it offers. Point the tunnel's public hostname at
`http://web:80`; the containers share a network, and the web container
publishes no port at all.

**The build serves everything itself.** `flutter build web` normally fetches
CanvasKit — some 7 MB — from `gstatic.com` on every cold load, and takes its
default UI font from `fonts.gstatic.com` with it. On a network that cannot
reach Google the app renders no text whatsoever. Both builds here pass
`--no-web-resources-cdn`, which puts CanvasKit in the bundle and the fonts
with it; a browser loading the result makes no request to anything but your
own origin. That is worth keeping true of a Bible app whose whole claim is
that it needs no connection.

Two ways to build the image:

| | what it does | when |
|---|---|---|
| `deploy/Dockerfile` | unpacks a published release zip | **the default.** No Flutter, no cross-build, works on the Pi itself |
| `deploy/Dockerfile.source` | builds this working tree | for changes not yet released |

The default is the right one for a Pi because a web bundle is static files
and so architecture-free; only nginx has to match, and that is multi-arch.
The source build cannot be: Flutter publishes **no arm64 Linux SDK**, so its
build stage is pinned to `linux/amd64` and would crawl under emulation on a
Pi. Build that one on an x86 machine and push the result:

```bash
docker buildx build --platform linux/arm64 \
  -f deploy/Dockerfile.source -t you/openword:dev --push .
```

### What the nginx config is doing

Two details of a Flutter bundle drive it, and both are easy to get wrong:

- **Nothing is content-hashed.** `main.dart.js` is called `main.dart.js` in
  every build, so no file may be cached immutably or a redeploy would serve
  the old app for as long as a browser kept it. Everything is `no-cache`
  with an ETag instead, which makes a warm load a handful of 304s and no
  bodies; the service worker and `version.json` are `no-store`.
- **Several assets are gzip *content*** — the `.bib` translations,
  `originals.ows.gz`, `xrefs.owx.gz` — which the app unpacks itself. They
  must go out as opaque bytes. A server that set `Content-Encoding` on them
  would have the browser unpack them early and the app's own gunzip would
  then fail on what was left.

Everything else *is* pre-compressed, at build time rather than per request,
so the Pi spends no CPU on it: `main.dart.js` goes out at 926 kB instead of
3.1 MB, `canvaskit.wasm` at 2.9 MB instead of 7.0 MB.

One nginx trap worth knowing if you edit the config: a `types { … }` block
inside `server` **replaces** the inherited MIME map rather than extending
it. Adding `font/ttf` that way silently costs `index.html` its `text/html`
and `canvaskit.wasm` its `application/wasm`, and the page stops working.
The Dockerfile appends to `mime.types` instead.

## How it works

```
lib/
  main.dart                     app entry, Material You theming, splash
  src/
    app_scope.dart              settings / library / reading stores in the tree
    model/
      book_meta.dart            canonical book table, sort names, divisions
      bible.dart                Bible → Book → Chapter → Block → VerseSegment
      bible_codec.dart          the binary encoding a Bible is read from
      bib_file.dart             the .bib file: that encoding behind a header
      xref_codec.dart           the binary the cross-references ship in
      strongs_codec.dart        the original-language binary, read by offset
    data/
      translations.dart         the bundled translations
      book_notes.dart           the per-book background notes
      cross_references.dart     the Treasury of Scripture Knowledge, indexed
      originals.dart            the Hebrew and Greek, keyed by English verse
      usfx_parser.dart          streaming USFX → the model above (build time)
      epub_import.dart          EPUB → the model above, on the device
      shelf.dart                the imported translations, as .bib files
      library.dart              loads a .bib, bundled or imported
      reference_search.dart     book matching and "jn 3:16" parsing
      settings.dart             preferences
      marks.dart                bookmarks, highlights, notes, position, backup
    ui/
      reader_screen.dart        one swipeable page per chapter, compare view
      navigator_sheet.dart      go-to field, book list, chapter and verse grids
      widgets/scripture_text.dart   block and inline-markup rendering
      import_sheet.dart        picks a file and reports what came of it
      library_screen.dart, search_screen.dart, display_sheet.dart,
      book_sheet.dart, settings_screen.dart
```

A chapter is stored as an ordered list of **blocks** (paragraph, poetry line,
heading, parallel reference, psalm title, stanza break), each holding **verse
segments**. A single verse can span several poetry lines, and a paragraph can
hold many verses, so the reader reproduces the translation's layout instead of
a list of numbered lines. Inline character styles — words of Jesus, translator
additions, Selah, footnote markers — travel inside the segment text as control
characters, which never occur in Scripture and so need no escaping.

The `.bib` payload is a small binary rather than JSON: decoding JSON of this
size built enough short-lived objects to peak around 230 MB of heap, where the
binary reads in one pass into the model in about 75 ms and holds roughly 28 MB
once loaded. A whole translation stays in memory, which is what makes search
and navigation instant.

## Licences

- Application code: [MIT](LICENSE) — including the `.bib` format and its
  implementation, so anything else may read or write one.
- Scripture text: public domain (see the table above). An imported translation
  carries whatever licence its own file states; OpenWord shows it and does not
  guess at one.
- Hebrew text, its Strong's numbers, parsing and versification map:
  [Open Scriptures Hebrew Bible](https://github.com/openscriptures/morphhb),
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- Greek text, with Strong's numbers and parsing: the
  [Byzantine Majority Text](https://github.com/byztxt/byzantine-majority-text)
  of Robinson and Pierpont, public domain.
- Strong's dictionaries of Hebrew and Greek:
  [Open Scriptures](https://github.com/openscriptures/strongs), CC BY-SA —
  the 1890 and 1894 works are themselves public domain. Shared alike: any
  redistribution of this edition of them must carry the same licence.
- Cross-references: [CrossReferences.org](https://crossreferences.org), after
  the Treasury of Scripture Knowledge,
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — attribution is
  shown on the cross-reference sheet itself.
- Place locations: [OpenBible.info Bible Geocoding](https://www.openbible.info/geo/),
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — attribution is
  shown on the map itself and in Settings. Base map, built-up areas and modern
  towns: [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/),
  public domain.
- Book introductions: Aquifer Open Study Notes (Book Intros) © Mission Mutual,
  an adaptation of Tyndale Open Study Notes © 2023 Tyndale House Publishers,
  both [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Shared
  alike: any redistribution of these introductions, adapted or not, must carry
  the same licence and this attribution.
- Scripture typeface: [Noto Serif Hebrew](https://github.com/notofonts/hebrew)
  and [Noto Serif](https://fonts.google.com/noto/specimen/Noto+Serif), SIL
  Open Font License 1.1 — see `assets/fonts/NotoSerif-OFL.txt`. Merged and
  subset to the two gaps Literata leaves: the Hebrew block and the thirteen
  modifier letters Strong's transliterates with, 16 kB in all. It is bundled
  because no platform can be relied on for a face carrying the vowel points
  and cantillation marks the Hebrew text uses; the web has none at all.
- Bundled typeface: [Literata](https://fonts.google.com/specimen/Literata),
  SIL Open Font License 1.1 — see `assets/fonts/Literata-OFL.txt`. It is
  subset to Latin, Greek and the punctuation the text uses.
