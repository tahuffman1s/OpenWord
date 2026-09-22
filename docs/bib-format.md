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

| Tag | For |
|---|---|
| `srch` | Which books each word is in; see below |
| `xref` | Cross-references anchored to this translation's own versification; see below |
| `strg` | *(reserved)* A word-level Strong's alignment, making an interlinear exact rather than inferred |
| `sign` | *(reserved)* A detached signature over the other chunks |

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

| Value | Means |
|---|---|
| `eng` | The numbering of the English Protestant Bible |
| `other` | Measured against `eng` and found not to match. Which scheme it *does* follow is not claimed |
| `unknown`, or absent | Not established. A version 1 file can say nothing else |

Anything else round-trips as written. A reader must not assume that a file
saying `unknown` matches anything — but it should not assume the opposite
either, since every file written before a producer started measuring says
exactly that.

OpenWord establishes this at import by comparing the incoming Bible's
per-chapter verse counts with the English scheme, over the sixty-six books
of the Protestant canon only — English editions disagree about the
deuterocanon while agreeing about everything else, so counting it would
raise a false alarm. Editions of the English Bible differ from each other
over about 0.2% of chapters; a difference in *scheme* is an order of
magnitude larger, so the line sits at 2%. See
`lib/src/model/versification_check.dart`.

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
                    1       flags; bit 0 indent the first line,
                            bit 1 continues the paragraph before it
                    1       heading level          (encoding 2)
                    1       alignment              (encoding 2)
                    varint  segment count
                            per segment:
                              varint  verse number, 0 for text outside any verse
                              1       1 if the verse number is printed here
                              string  the text
          varint  note count
                  per note: string
          string  what the chapter is called       (encoding 2)
          varint  printed verse labels             (encoding 2)
                  per label: varint verse, string label
          varint  omitted verses, then deltas      (encoding 2)
```

Styles: 0 paragraph, 1 poetry, 2 psalm title, 3 heading, 4 stanza break,
5 parallel-passage reference, 6 acrostic letter, 7 speaker, 8 list item,
9 table row. A reader must treat an unknown style as a paragraph, which is
what lets styles be added.

Alignment: 0 to the margin, 1 centred, 2 to the right. It says what the
source said; a reader may still centre what it knows should be centred,
as it does a book division.

**Heading level** says how major a heading is: 1 divides the book — "BOOK
1" of the Psalms — and 2 and 3 are the sections under it. 0 where the
translation does not say.

**The chapter's name** is what the translation calls it, where it says so
(`\cl`): "Psalm 1" rather than "Chapter 1".

**Printed verse labels** are for verses printed as something other than
their number (`\vp`) — a bridged verse set as "1-2", or a second
numbering shown beside the first.

**Omitted verses** are the ones the translation does not have: Matthew
17:21, Mark 9:44 and the dozen others the critical texts leave out. They
are numbered in the tradition and absent from the text, and recording
that is what lets a reader say so rather than show a number with nothing
after it, or look as though it failed to parse the verse.

### Encoding versions

Encoding 1 stopped after a block's flags and after a chapter's notes; it
had no heading level, alignment, chapter name, verse labels or omissions.
Encoding 2 has them all. A reader of 1 has no way to know it should skip
them, which is why the number went up rather than the fields being
squeezed in — a writer must emit 2 to use them, and a reader should
accept both.

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
| `U+0019` … `U+001A` | the divine name, set in small capitals |
| `U+001B` … `U+001C` | words quoted from elsewhere in Scripture |
| `U+001D` | between the cells of a table row |

Control characters are used because Scripture text never contains them, so
nothing has to be escaped and a search over the raw text needs no parsing.

**`U+0011` to `U+001F` are reserved for markers, and a reader must drop the
whole range** — not only the ones it knows. Otherwise a marker added after
it was written prints a control character into the middle of a verse. A
cell boundary should become a space rather than nothing, since it stands
between two words.

The divine name and a translator's addition are not the same thing, and
neither is a quotation from Scripture: `\add` marks words that are not in
the original and `\qt` marks words taken from somewhere else in it. Both
used to be stored as the first, which said the wrong thing about both.

### Text is NFC

All text in the file — Scripture, footnotes, headings, the metadata — is in
Unicode Normalization Form C. A writer must compose it; a reader may assume
it, and should compose anything it compares against the file.

This is not a formality. Unicode can spell the same word more than one way:
`é` is one codepoint or an `e` followed by a combining acute, and Hebrew
with two points on a letter can carry them in either order. The spellings
look identical on the page, are canonically equivalent, and are different
bytes — so a reader typing what they see gets nothing back, and no error is
raised anywhere. Fixing it at the boundary is the only place it stays
fixed.

## `srch`

Which books of the translation each of its words occurs in, so that a
search reads only the books that could match. Ancillary: a file without it
searches by reading everything, which is what all of them used to do.

```
1       index version, 1
4       CRC-32 of the TEXT chunk this was built from
varint  book count
varint  word count
        per word, in byte order:
          string  the word, lowercased
          varint  how many books it is in
          varint  the first book's index, then deltas
```

A word is a run of letters and marks — Unicode `\p{L}` and `\p{M}` —
lowercased. The payload is usually gzipped; a reader should accept it
either way, and can tell by the two-byte gzip magic.

**It is a filter, never an answer.** The index holds words; a query may be
any substring of one. A reader tokenises the query the same way the index
was built, finds every indexed word *containing* each token, and unions
their books; a book must appear for every token, since each word of the
query has to be somewhere in it. What finally decides a hit is the same
pattern match as before, over the books that survived. So results are
identical with the index or without it, and a reader may ignore it freely.

**A stale index would quietly lose results**, which is the worst way for
this to go wrong, so it carries the CRC-32 of the `TEXT` chunk it was built
from and must be ignored unless the two agree.

Measured on the World English Bible, with the translation already open:
searching for a word that is not there goes from 153 ms to 0.5 ms, and for
a rare one from 144 ms to 3 ms. A word in every book costs about 0.7 ms
more than not having the index at all. The chunk is 116 kB gzipped on a
1.76 MB file, and is not unpacked until something searches.

## `xref`

Cross-references anchored to *this translation's* verse numbering. The
payload is a gzipped `OWX` set — the same encoding the app's own bundled
references use, specified in
[`lib/src/model/xref_codec.dart`](../lib/src/model/xref_codec.dart).

A reader should prefer these over any set of its own. They are right by
construction: a reference set is anchored to one numbering, and the file
carrying both cannot disagree with itself. For a Bible numbered
differently from a reader's built-in set, this is the difference between
having cross-references and not — the alternative is to withhold them,
since pointing at the wrong verse is worse than pointing nowhere.

Attach a set with:

```bash
dart run tool/attach_xrefs.dart <file.bib> <xrefs.owx.gz>
```

It reads the set, rewrites the file, reads the result back and compares
before replacing anything. OpenWord itself does the same to a copy, from a
translation's menu in Settings, and refuses where the numbering it measured
says the set would not fit.

A writer must carry chunks it does not understand through a rewrite, or a
translation would silently lose its references the first time anything
touched the file.

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
