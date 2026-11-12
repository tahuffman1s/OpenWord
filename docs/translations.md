# Translations: what ships, and bringing your own

[← Back to the README](../README.md)

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
The full specification is [`docs/bib-format.md`](bib-format.md); what
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
[`test/corpus/`](../test/corpus/) holds small files named for what a reader is
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
