# The `.bib` format

One translation of the Bible, whole, in one file: the text, how it is set on
a page, its footnotes, and what it is. Small enough to ship three of inside
a phone app, and arranged so that opening one costs the book being read
rather than the whole Bible.

This document is the specification. The reference implementation is
[`lib/src/model/bib_file.dart`](../lib/src/model/bib_file.dart) and
[`lib/src/model/bible_codec.dart`](../lib/src/model/bible_codec.dart), both
MIT, and [`test/corpus/`](../test/corpus/) holds files any other
implementation can test itself against.

All integers are unsigned. Fixed-width fields are big-endian. Everything
else is an LEB128 varint: seven bits per byte, low group first, the high bit
set on every byte but the last. A *string* is a varint byte length followed
by that many bytes of UTF-8.

## The file

```
offset  size  meaning
0       3     'BIB'
3       1     format version, 2
4       2     reserved, zero
6       …     chunks, one after another, to the end of the file
```

A reader that does not know the version in byte 3 must refuse the file.

### Chunks

```
size  meaning
4     tag, four ASCII letters
4     length of the payload
4     CRC-32 of the payload
…     payload
```

The CRC-32 is the ordinary one — the reflected polynomial `0xEDB88320`,
initial value `0xFFFFFFFF`, final complement — over the payload alone.

**The case of the first letter of a tag says what to do with a chunk you do
not recognise**, the rule PNG uses:

- **Upper case is critical.** A reader that meets an unknown critical chunk
  must refuse the file: the file is saying it cannot be read correctly
  without it.
- **Lower case is ancillary.** A reader must skip an unknown one and carry
  on.

That single rule is what lets the format grow. Anything added as an
ancillary chunk is invisible to every reader written before it.

Two chunks are defined, and both are critical:

| Tag | Contents |
|---|---|
| `META` | What the file is: UTF-8 JSON, described below |
| `TEXT` | The Scripture |

`META` must come first, so that a directory of translations can be listed by
reading a few hundred bytes of each rather than opening any of them.

These tags are reserved for what a `.bib` may come to carry. All are
ancillary, so a file using them stays readable by everything written before
them:

| Tag | Intended for |
|---|---|
| `xref` | Cross-references anchored to this translation's own versification |
| `strg` | A word-level Strong's alignment, making an interlinear exact rather than inferred |
| `srch` | A prebuilt search index |
| `sign` | A detached signature over the other chunks |

Where two chunks share a tag, the later one wins.

## `META`

UTF-8 JSON, one object. A reader must ignore keys it does not know.

| Key | | Meaning |
|---|---|---|
| `id` | required | Stable identifier, e.g. `eng-web` |
| `name` | required | `World English Bible` |
| `abbreviation` | required | `WEB` |
| `license` | | Licence name, e.g. `Public Domain`, `CC BY 4.0` |
| `source` | | Where the text came from |
| `language` | | BCP 47: `en`, `en-GB`, `arb` |
| `script` | | ISO 15924: `Latn`, `Hebr`, `Arab` |
| `direction` | | `ltr` or `rtl`; absent means `ltr` |
| `versification` | | See below; absent means unknown |
| `attribution` | | Wording the licence obliges a reader to display |
| `books` | | How many books the `TEXT` chunk holds |
| `verses` | | How many verses |
| `contentHash` | | `sha256:` and the hex digest of the whole `TEXT` payload |
| `generator` | | What wrote the file |
| `created` | | When, as RFC 3339. Optional on purpose: a writer that leaves it out encodes the same Bible to the same bytes, which is what a build wants |

### `versification`

Everything anchored to a verse — a cross-reference set, an interlinear, a
lectionary — is anchored to one numbering, and Bibles do not share one. The
Hebrew Bible counts a psalm's superscription as verse 1; Joel and Malachi
divide their chapters differently; the Septuagint numbers differently again.
A file that does not say which numbering it follows can be mis-anchored
without anything appearing to go wrong, which is the worst way for it to go
wrong.

`eng` is the numbering of the English Protestant Bible. Anything else
round-trips as written. A reader must not assume that a file which says
nothing matches anything.

## `TEXT`

An outline of every book, and then the books themselves.

```
1       text encoding version, 1
1       compression: 0 stored, 1 gzip
varint  book count
        per book, in canonical order:
          string  USFM book code, e.g. GEN
          varint  chapter count
                  per chapter:
                    varint  chapter number as printed
                    varint  verse count
          varint  length of this book's payload
…       the book payloads, in the same order, back to back
```

The outline is the point of the arrangement. It carries everything
navigation needs — which books, how many chapters, how long each chapter is
— so a reader can draw a book list, a chapter grid and a verse grid without
unpacking any Scripture at all. A book's payload begins at the end of the
outline plus the lengths of the books before it, so any one of them can be
found and unpacked on its own.

Each payload is one book's chapters, compressed by the method in the header.
With gzip, each is a complete gzip member, so it can be unpacked by anything
— and its own CRC-32 and length check it as it goes.

Per-book compression costs about 4% against compressing the whole Bible as
one stream, and buys unpacking 25 kB to open Genesis instead of 5 MB. Going
finer does not pay: per *chapter* costs 37%, and a shared preset dictionary
does not win it back.

A reader must skip a book whose code it does not know rather than refuse the
file.

### A book's chapters

```
varint  chapter count
        per chapter:
          varint  chapter number
          varint  block count
                  per block:
                    1       style
                    1       indent level
                    1       flags; bit 0: indent the first line
                    varint  segment count
                            per segment:
                              varint  verse number, 0 for text outside any verse
                              1       1 if the verse number is printed here
                              string  the text
          varint  note count
                  per note: string
```

Styles: 0 paragraph, 1 poetry, 2 psalm title, 3 heading, 4 stanza break,
5 parallel-passage reference. A reader must treat an unknown style as a
paragraph.

A verse is split across segments wherever the layout interrupts it, which is
how a verse can begin mid-paragraph and carry on past a line of poetry.
Text belonging to no verse — a heading, a psalm's title — takes verse 0.

Four control characters carry inline formatting inside a segment's text:

| | |
|---|---|
| `U+0011` … `U+0012` | words of Jesus |
| `U+0013` … `U+0014` | words supplied by the translator, printed italic |
| `U+0015` *digits* `U+0016` | a footnote marker; the digits index the chapter's notes |
| `U+0017` … `U+0018` | `Selah` and other poetry directions |

Control characters are used because Scripture text never contains them, so
nothing has to be escaped and a search over the raw text needs no parsing.

## Version 1

The first version of the format, still read and no longer written:

```
offset  size  meaning
0       3     'BIB'
3       1     1
4       1     flags; bit 0 set means the payload is gzipped
5       2     metadata length
7       …     metadata: UTF-8 JSON — id, name, abbreviation, license, source
…       …     payload
```

The payload is `OWB`, a version byte, the five metadata strings again, and
then a book count followed by each book's code and chapters, in the layout
above. It is one stream: there is no outline and no way to read one book
without unpacking all of them.

A version 1 file says nothing about language, direction or versification. A
reader must fall back rather than invent: `en`, `ltr`, unknown.

`dart run tool/upgrade_bib.dart <file.bib>` rewrites one as version 2, and
compares the result with the original verse by verse before replacing it.

## Checking a file

```bash
dart run tool/bib_lint.dart <file.bib>
```

It reports the version, the chunks, whether every checksum matches, whether
the outline agrees with the text it stands for, and whether the metadata's
counts and `contentHash` describe what is actually in the file.

## The corpus

[`test/corpus/`](../test/corpus/) holds small files — the same two books in
every one — named for what a reader is supposed to do with them: the three
that must read alike, the unknown ancillary chunk that must be skipped, the
unknown critical chunk that must not be, and the damaged, truncated,
too-new and not-a-`.bib` files that must be refused. Regenerate with
`dart run tool/build_bib_corpus.dart`.

## What this format is not

It is a **reading** format, not an archival or interchange one. It keeps
what a reader displays — blocks, indents, segments, notes — and not the full
semantics of the USFM it was built from. Keep the USFM or USFX; this is what
gets shipped.
