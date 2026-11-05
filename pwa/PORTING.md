# Porting OpenWord from Flutter to the PWA

The PWA in this directory is a one-for-one port of the Flutter app in
`../lib`. Read the Dart file you are porting in full before writing a line:
the behaviour, the names, the doc comments and the edge cases all carry
over. Where the Dart does something odd on purpose, the comment usually
says why — keep the comment.

## Layout

| Dart                              | TypeScript                               |
|-----------------------------------|------------------------------------------|
| `lib/src/model/foo_bar.dart`      | `src/model/fooBar.ts`                    |
| `lib/src/data/foo_bar.dart`       | `src/data/fooBar.ts`                     |
| `lib/src/ui/foo_bar.dart`         | `src/ui/fooBar.tsx`                      |
| `lib/src/ui/widgets/foo.dart`     | `src/ui/widgets/foo.tsx`                 |
| `test/foo_test.dart`              | `test/foo.test.ts(x)`                    |

Model code has no DOM and no `fetch`. Data code may use IndexedDB / fetch
behind small interfaces so tests can run under Node (vitest, `test/` dir).
Tests that need the bundled assets read them through `test/fsAssets.ts`
(`new FsAssetBundle()`), which reads `../assets/...` from the repository.

## Already ported — build on these, do not redo them

- `src/model/bible.ts` — `Markup`, `BlockStyle` (numeric enum, index is
  persisted), `BlockAlign`, `VerseSegment`, `Block`, `Chapter`,
  `ChapterOutline`, `Book` (`Book.of(meta, chapters)`,
  `Book.deferred(meta, outline, load)`), `ReadingDirection`,
  `Versification`, `TranslationInfo`, `Bible`, `Reference`
  (`ref.equals(other)`, `ref.key` for Maps/Sets — JS has no operator==),
  `parseIntStrict` (Dart's `int.tryParse`).
- `src/model/bookMeta.ts` — `BookMeta`, `BookSection`, `BookDivision`
  (+ label maps). `meta.division` is a getter.
- `src/model/byteIo.ts` — `ByteWriter`, `ByteReader`, `FormatException`,
  `utf8`.
- `src/model/bibleCodec.ts`, `src/model/bibFile.ts` (`BibFile.encode /
  decode / readInfo / chunk / tags / looksLikeBib`, `BibFormatException`),
  `src/model/searchIndex.ts`, `src/model/textNormal.ts` (`ScriptureText`),
  `src/model/crc32.ts`, `src/model/sha256.ts`.
- `src/infra/changeNotifier.ts` — `ChangeNotifier`, `ValueNotifier`, and
  the `useNotifier(...notifiers)` hook (Flutter's AnimatedBuilder).
- `src/infra/prefs.ts` — `Prefs` mirrors SharedPreferences
  (`getInt/getDouble/getBool/getString/getStringList`, `setX`, `remove`,
  `containsKey`); `Prefs.open()` for the browser, `Prefs.memory()` for tests.
- `src/infra/assets.ts` — `AssetBundle` (`load(path)`, `loadString(path)`),
  `rootBundle`, `setRootBundle`. Asset paths are the same strings as in
  Dart: `assets/bible/eng-web.bib`, `assets/refs/xrefs.owx.gz`, …
- `src/data/translations.ts` — `Translations`.

## Idioms

- Dart class → TS class with the same name and members. Named
  constructors → static factories (`Foo.deferred(...)`). `const`
  constructors → ordinary ones. `@immutable` → `readonly` fields.
- Dart enums whose `.index` is persisted (settings, codecs) → numeric TS
  enums with the same order. Enums that only carry labels → string enums
  plus a `Record<Enum, string>` of labels.
- `DateTime` → `Date`. `millisecondsSinceEpoch` → `getTime()`. Local
  dates (`local_date.dart`) are the exception: port them as the Dart does.
- `Random` → an injectable `() => number` in `[0, 1)`, defaulting to
  `Math.random`.
- `Map`/`Set` → `Map`/`Set`. Dart's `List.unmodifiable` → return a copy or
  a `readonly` array.
- `int.tryParse` → `parseIntStrict` from `src/model/bible.ts`.
  `double.tryParse` → a strict helper, not `Number()`, which accepts `''`.
- `String.compareTo` sorts by UTF-16 code unit: use `compareCodeUnits`
  from `src/model/searchIndex.ts`, not `localeCompare`.
- `jsonEncode`/`jsonDecode` → `JSON.stringify`/`JSON.parse`. Dart's
  `int` vs `double` distinction does not exist; check `Number.isInteger`
  where the Dart checks `is int`.
- Gzip: `fflate` (`gunzipSync`, `gzipSync`). CRC: `crc32`. SHA-256:
  `sha256Hex`.
- `compute(...)` / `Isolate.run` → do the work inline in the function, and
  let the caller decide to put it on a worker. Keep heavy pure functions
  top-level and free of DOM so a worker can import them.
- `debugPrint` → `console.warn` prefixed `OpenWord:`.
- `ChangeNotifier` subclasses stay `ChangeNotifier` subclasses; getters
  stay getters; setters that persist stay setters.
- Throw `Error` subclasses with the Dart exception's name and message.
- Regular expressions: Dart `RegExp(r'…', unicode: true)` → `/…/u`; Dart
  `allMatches` → `matchAll` with the `g` flag. `\p{L}` etc. need `u`.
- `String.fromCharCodes`, `codeUnitAt`, `substring`, `indexOf`, `length`
  are all UTF-16 in both languages — port them directly. Dart `runes` →
  iterate `for (const ch of s)` (code points).
- Dart `~/` → `Math.trunc(a / b)`; `%` on negatives differs (Dart's is
  Euclidean for `%`? no: Dart `%` is always non-negative for positive
  divisor) — use a `mod(a, b)` helper when a negative operand is possible.
- `num.clamp` → `Math.min(Math.max(...))`. `round()` → `Math.round` is
  fine for positives; Dart rounds half away from zero.
- Keep the doc comments (as `/** … */`) and the file-level comment.

## Tests

Port the corresponding `test/*_test.dart` where it tests the model or
data layer (no widgets). Use vitest: `describe`/`it`/`expect`. Run
`npx vitest run test/<file>.test.ts` from `pwa/`. `npx tsc --noEmit -p
tsconfig.json` must stay clean (strict mode) — run it before finishing.

## UI (for the screen ports, later)

Preact function components in `src/ui/`, styled with the Material 3 kit in
`src/ui/m3/` (see `src/ui/m3/README.md` once it exists). Bottom sheets are
`showSheet(<X/>)`, dialogs `showDialog(<X/>)`, screens `nav.push(<X/>)`.
