# The study layers: introductions, Hebrew and Greek, cross-references, maps

[← Back to the README](../README.md)

Each layer is a file under `assets/` — `notes/`, `strongs/`, `refs/`,
`maps/` and `fonts/` — and each is built data, committed as it ships. The
tools that built them from the sources named below lived in the former
native app's source tree and are no longer in this repository; commit
`51e8e36` has them. What follows says where each layer's data comes from,
under what licence, and how the app reads it.

## Book introductions

Each of the sixty-six books of the Protestant canon opens with an
introduction of a few hundred words. These are the
[Aquifer Open Study Notes book introductions](https://github.com/BibleAquifer/AquiferOpenStudyNotesBookIntros)
— an adaptation by Mission Mutual of Tyndale Open Study Notes © 2023 Tyndale
House Publishers, both licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). They ship as
one gzipped JSON asset (about 200 kB) and are read only when a book sheet is
opened. The deuterocanonical books are not covered by that resource, so they
fall back to the short notes in `pwa/src/data/bookNotes.ts`.

The asset is `assets/notes/book-intros-eng.json.gz`, read by
`pwa/src/data/bookIntros.ts`. It was built from the sixty-six Markdown files
of that repository (`eng/md/01.content.md` to `66.content.md`), with each
file's licence preamble and title line dropped — the licence is shown by the
app from its own copy, in the book sheet and in Settings, as CC BY-SA
requires.

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
applied it, so Malachi 4:1 finds the words that Hebrew calls Malachi 3:19.

**What it does not cover**: the deuterocanonical books, which are in neither
the Hebrew Bible nor the Greek New Testament as this app carries them. Those
verses simply do not offer the option.

446,925 words and 14,197 dictionary entries come to 3.9 MB. The file is
gunzipped once into a byte array that stays put, and a verse's words are
decoded only when that verse is looked at — holding them all as objects
would cost more memory than the Scripture itself.

The asset is `assets/strongs/originals.ows.gz`, read by
`pwa/src/data/originals.ts`; its encoding is specified in
`pwa/src/model/strongsCodec.ts`. It was built from three sources:
[openscriptures/morphhb](https://github.com/openscriptures/morphhb) for the
Hebrew, [byztxt/byzantine-majority-text](https://github.com/byztxt/byzantine-majority-text)
for the Greek, and [openscriptures/strongs](https://github.com/openscriptures/strongs)
for the dictionaries. The Greek arrives as two files that align word for
word — one accented, one carrying the numbers and parsing — and the build
checked that alignment for every verse rather than assuming it.

**The typeface this needs.** Literata, the reading face, has Latin and Greek
and stops there. The Hebrew needs a face with the vowel points and all
thirty-one cantillation marks, and the transliterations need thirteen
modifier letters no reading face carries — the turned comma for ayin, the
apostrophe for aleph, the superscript vowels. Without them the words fall
to whatever face the device happens to have, and where it has none that
carries them, to boxes. So the two gaps were cut out of
[Noto Serif Hebrew](https://github.com/notofonts/hebrew) and Noto Serif,
which share metrics, and merged into one 16 kB face,
`assets/fonts/ScriptureSerif-Subset.ttf`, which stands behind the reading
face wherever Scripture is set.

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
"the LORD", "God") and LEB128 varints for the rest. It is read in the
background as the reader opens, so opening a chapter never waits on it.

The asset is `assets/refs/xrefs.owx.gz`, read by
`pwa/src/data/crossReferences.ts`; its encoding is specified in
`pwa/src/model/xrefCodec.ts`. It was built from the JSON in
[CrossReferences-org/bible-cross-references](https://github.com/CrossReferences-org/bible-cross-references).

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
Ramer–Douglas–Peucker, and written as one 600 kB asset,
`assets/maps/atlas.json.gz`, read by `pwa/src/data/atlas.ts` in the
background as the reader opens. No tiles are fetched and nothing needs a
connection.
