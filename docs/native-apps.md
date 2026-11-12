# The native apps (Flutter)

[← Back to the README](../README.md)

The same reader as native builds for Android, iOS, Linux, macOS and Windows, made with Flutter from `lib/`. They have no accounts or friends, and they are where Android Auto lives.

## Building the native apps

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

The voice is not kept in git — it is fifty-odd megabytes — so fetch it
before building or testing anything but the web:

```bash
dart run tool/fetch_voice.dart    # writes assets/voice/kitten.tar.gz
```

It downloads KittenTTS as sherpa-onnx packages it, checks its SHA-256, and
keeps only what English needs. CI does the same.

The Linux build needs GTK and GStreamer's development packages — on Debian
and Ubuntu, `libgtk-3-dev libgstreamer1.0-dev
libgstreamer-plugins-base1.0-dev` — for the audio player the voice plays
through.

Tagged builds for Android, Linux, Windows and the web are attached to each
[release](https://github.com/tahuffman1s/OpenWord/releases); see
[CHANGELOG.md](../CHANGELOG.md).

### Checks

```bash
flutter analyze
flutter test
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
introductions, the maps and the voice are all bundled, and importing a
translation reads the file the system picker hands over without sending it
anywhere.

## How the native app is put together

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
