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
- **Maps of the places a chapter names**, drawn from open data and bundled
  with the app: markers over coastline, lakes and rivers, with the ones
  scholars dispute marked as such.
- **Context where the translation offers it.** Citations in footnotes and in
  parallel-passage lines are links — tap `Ezekiel 34:11` under the heading of
  Psalm 23 and you are there. Every book also opens an introduction from its
  name above the chapter number — canon division, length, and a full essay on
  the book's setting, authorship, structure and themes.
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
— into a compact binary the app reads directly. Adding another freely licensed
USFX translation takes two steps:

```bash
# 1. add an entry to lib/src/data/translations.dart, then
dart run tool/build_assets.dart <directory-with-usfx-files>
```

`tool/build_assets.dart` expects `<translation id>.usfx.xml` in that directory
and writes `assets/bible/<id>.owb.gz`, checking that what it wrote decodes
back to the same verse count.

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

A chapter that names somewhere on the ground says so above its number — *8
places* — and opens a map of them: coastline, lakes and rivers, a marker per
place, pinch to zoom, and a tap on a marker or a name for what is known about
it. A hollow marker is a location scholars have not settled.

- Places: [OpenBible.info Bible Geocoding](https://github.com/openbibleinfo/Bible-Geocoding-Data),
  CC BY 4.0 — every place named in the Protestant canon, the verses naming it,
  and how confident the identification is. 1,276 of them resolve to a point
  and reach the app.
- Base map: [Natural Earth](https://www.naturalearthdata.com/) 1:50m land,
  lakes and river centrelines, public domain, by way of
  [natural-earth-geojson](https://github.com/martynafford/natural-earth-geojson).

Both are clipped to the world the Bible names, simplified, and written as one
70 kB asset, read the first time a reader opens a chapter. As with everything
else here, no tiles are fetched and nothing needs a connection.

```bash
git clone --depth 1 https://github.com/openbibleinfo/Bible-Geocoding-Data
git clone --depth 1 https://github.com/martynafford/natural-earth-geojson
dart run tool/build_maps.dart Bible-Geocoding-Data natural-earth-geojson
```

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
      bible_codec.dart          the binary format the bundled text is read from
    data/
      translations.dart         the bundled translations
      book_notes.dart           the per-book background notes
      usfx_parser.dart          streaming USFX → the model above (build time)
      library.dart              loads a translation from the app's assets
      reference_search.dart     book matching and "jn 3:16" parsing
      settings.dart             preferences
      marks.dart                bookmarks, highlights, notes, position, backup
    ui/
      reader_screen.dart        one swipeable page per chapter, compare view
      navigator_sheet.dart      go-to field, book list, chapter and verse grids
      widgets/scripture_text.dart   block and inline-markup rendering
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

The bundled format is a small binary rather than JSON: decoding JSON of this
size built enough short-lived objects to peak around 230 MB of heap, where the
binary reads in one pass into the model in about 75 ms and holds roughly 28 MB
once loaded. A whole translation stays in memory, which is what makes search
and navigation instant.

## Licences

- Application code: [MIT](LICENSE).
- Scripture text: public domain (see the table above).
- Place locations: [OpenBible.info Bible Geocoding](https://www.openbible.info/geo/),
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Base map:
  [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/), public
  domain.
- Book introductions: Aquifer Open Study Notes (Book Intros) © Mission Mutual,
  an adaptation of Tyndale Open Study Notes © 2023 Tyndale House Publishers,
  both [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Shared
  alike: any redistribution of these introductions, adapted or not, must carry
  the same licence and this attribution.
- Bundled typeface: [Literata](https://fonts.google.com/specimen/Literata),
  SIL Open Font License 1.1 — see `assets/fonts/Literata-OFL.txt`. It is
  subset to Latin, Greek and the punctuation the text uses.
