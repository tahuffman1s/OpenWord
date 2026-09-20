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

`tool/build_assets.dart` expects `<translation id>.usfx.xml` in that directory
and writes `assets/bible/<id>.bib`, checking that what it wrote reads back —
both the header and the same verse count behind it.

## Importing a translation: EPUB and `.bib`

Settings → *Add a translation* takes a file from the device. Nothing is
uploaded: the file is read where it sits, converted on the device, and kept in
the app's own documents directory. An imported translation is then a
translation like any other — it appears in the translation list and the
compare chips, and search, maps, highlights, bookmarks and notes all work
against it.

### The `.bib` format

A `.bib` file is one translation, whole, in one file: a compact binary
encoding of the text behind a small header that says what the file holds, so a
file can be listed without being decoded. It is what the app ships its own
three translations as, as well as what an import is converted to.

| Offset | Size | Meaning |
|---|---|---|
| 0 | 3 | `BIB` |
| 3 | 1 | Format version, currently 1 |
| 4 | 1 | Flags; bit 0 set means the payload is gzipped |
| 5 | 2 | Length of the metadata, big-endian |
| 7 | … | Metadata: UTF-8 JSON — `id`, `name`, `abbreviation`, `license`, `source` |
| … | … | Payload: the whole Bible, `BibleCodec`-encoded |

The metadata is in the clear so that listing a shelf of translations means
reading a few dozen bytes of each file. It repeats what the payload says;
where the two disagree the payload wins, since that is what is read. The
format is implemented in `lib/src/model/bib_file.dart` and the encoding it
wraps in `lib/src/model/bible_codec.dart` — both MIT, like the rest of the
app, so anything else may read or write `.bib` files.

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
and `Psaume 23` work as well as `Chapter 3`. A book whose verses start with
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

Poetry lines, section headings and italics are kept. Footnotes are dropped,
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
    data/
      translations.dart         the bundled translations
      book_notes.dart           the per-book background notes
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
- Bundled typeface: [Literata](https://fonts.google.com/specimen/Literata),
  SIL Open Font License 1.1 — see `assets/fonts/Literata-OFL.txt`. It is
  subset to Latin, Greek and the punctuation the text uses.
