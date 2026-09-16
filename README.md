# OpenWord

A free and open source Bible reader, built with Flutter and themed with
Material You. One codebase runs on Android, iOS, Linux, macOS, Windows and the
web.

The Scripture text is not bundled with the app: on first launch OpenWord
downloads the **World English Bible** — a modern English translation in the
**public domain** — and keeps it on the device for offline reading.

## Features

- **Printed-Bible layout.** The text is parsed from USFX, so the translation's
  own structure survives: prose paragraphs that verses flow through, poetry
  indented by level, psalm titles, section headings, stanza breaks, the words
  of Jesus in red, translator additions in italics and tappable footnotes.
- **A Niagara-style index rail.** The alphabet sits on the trailing edge with
  the text to its left. Sliding a finger up and down swells the nearby letters
  and pulls them toward the touch point, and the books under the focused letter
  fan out beside it. Slide left onto one to pick it, or lift and tap. The same
  rail indexes chapters and verses by tens.
- **Bookmarks and notes.** Tap any verse to bookmark it, attach a note or copy
  it. Bookmarked verses are tinted in the text and flagged in the pickers.
- **Resume where you left off.** The book, chapter and the verse nearest the
  top of the screen are saved as you read, and restored on the next launch.
  Recently read chapters are one tap away.
- **Material You.** The palette follows the system wallpaper where the platform
  provides one (Android 12+), with a seed-colour picker everywhere else. Light,
  dark and system themes; adjustable text size, line spacing and typeface.
- **Search** across the whole text, and an option to show the
  deuterocanonical books that the edition includes.
- Works offline after the first download. No accounts, no tracking, no ads.

## Scripture text

| | |
|---|---|
| Translation | World English Bible (WEB) and World English Bible, British Edition (WEBBE) |
| Licence | Public domain |
| Format | [USFX](https://ebible.org/usfx/) (the XML form of USFM) |
| Home | <https://ebible.org/web/> |
| Download mirrors | `raw.githubusercontent.com/seven1m/open-bibles`, `ebible.org` |

Mirrors are tried in order, so one host going away does not break a fresh
install. Adding another freely licensed USFX translation is a matter of adding
an entry to `lib/src/data/bible_source.dart` — the parser is not
WEB-specific.

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

### Checks

```bash
flutter analyze
flutter test
```

`dart run tool/parse_check.dart <file.usfx.xml>` parses a USFX file outside the
app and prints a structural summary — useful when adding a translation.

## How it works

```
lib/
  main.dart                     app entry, Material You theming, first-run gate
  src/
    app_scope.dart              settings / library / reading stores in the tree
    model/
      book_meta.dart            canonical book table, sort names, divisions
      bible.dart                Bible → Book → Chapter → Block → VerseSegment
    data/
      bible_source.dart         downloadable translations and their mirrors
      usfx_parser.dart          streaming USFX → the model above
      library.dart              download, parse (off the UI isolate), cache
      bible_cache_io.dart       gzipped JSON in the app support directory
      bible_cache_web.dart      web: re-fetch, backed by the browser's cache
      settings.dart             preferences
      bookmarks.dart            bookmarks, notes, reading position, history
    ui/
      reader_screen.dart        one swipeable page per chapter
      widgets/niagara_picker.dart   the animated index rail
      widgets/scripture_text.dart   block and inline-markup rendering
      pickers.dart              book / chapter / verse pickers
      search_screen.dart, bookmarks_screen.dart, settings_screen.dart
```

A chapter is stored as an ordered list of **blocks** (paragraph, poetry line,
heading, psalm title, stanza break), each holding **verse segments**. A single
verse can span several poetry lines, and a paragraph can hold many verses, so
the reader can reproduce the translation's layout instead of a list of
numbered lines. Inline character styles — words of Jesus, translator
additions, Selah, footnote markers — travel inside the segment text as control
characters, which never occur in Scripture and so need no escaping.

After the download the whole Bible (about 4 MB of text) is held in memory and
cached as gzipped JSON, which keeps navigation and search instant without a
database. Parsing runs on a background isolate so the first-run progress bar
stays smooth.

The web build cannot store several megabytes durably through these
dependencies, so it fetches the text each session and relies on the browser's
HTTP cache; everything else behaves identically.

## Licences

- Application code: [MIT](LICENSE).
- Scripture text: public domain (World English Bible).
- Bundled typeface: [Literata](https://fonts.google.com/specimen/Literata),
  SIL Open Font License 1.1 — see `assets/fonts/Literata-OFL.txt`. It is
  subset to Latin, Greek and the punctuation the text uses.
