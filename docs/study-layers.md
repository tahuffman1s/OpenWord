# The study layers: introductions, Hebrew and Greek, cross-references, maps

[← Back to the README](../README.md)

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
