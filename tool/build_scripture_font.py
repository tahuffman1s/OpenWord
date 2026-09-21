#!/usr/bin/env python3
"""Builds the typeface bundled for what the reading face cannot show.

    python3 tool/build_scripture_font.py <noto-serif-hebrew.ttf> <noto-serif.ttf>

Literata, the reading face, carries Latin and Greek and stops there. Two
things in the original-language layer fall outside it: the Hebrew Bible,
which needs not only the letters but the vowel points and all thirty-one
cantillation marks, and the modifier letters Strong's transliterates with —
the turned comma for ayin, the apostrophe for aleph, the superscript vowels.
No platform can be relied on for either, and the web has neither.

So both are cut out of Noto Serif Hebrew and Noto Serif, which share metrics,
and merged into one face of about 16 kB. Both are under the SIL Open Font
License 1.1; the licence travels with the asset as
assets/fonts/NotoSerif-OFL.txt.

Needs fontTools: pip install fonttools brotli
"""

import sys

from fontTools import subset
from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = 'assets/fonts/ScriptureSerif-Subset.ttf'

# U+0591–U+05F4: the Hebrew block entire — letters, finals, points, accents,
# and the ligatures and punctuation the text uses.
HEBREW = list(range(0x0591, 0x05F5))

# What Strong's transliterations reach for and Literata has not got. The
# grapheme joiner is in the data too, and is invisible, but a face that knows
# it keeps it from being drawn as a box.
MARKS = [
    0x02BB,  # ʻ  modifier letter turned comma — ayin
    0x02BC,  # ʼ  modifier letter apostrophe — aleph
    0x02E2,  # ˢ  modifier letter small s
    0x034F,  #    combining grapheme joiner
    0x1D49,  # ᵉ  modifier letter small e
    0x1E15,  # ḕ  e with macron and grave
    0x1E16,  # Ḗ  E with macron and acute
    0x1E17,  # ḗ  e with macron and acute
    0x1E2F,  # ḯ  i with diaeresis and acute
    0x1E51,  # ṑ  o with macron and grave
    0x1E53,  # ṓ  o with macron and acute
    0x1E6C,  # Ṭ  T with dot below
    0x1E6D,  # ṭ  t with dot below
]


def cut(path: str, codepoints: list[int], out: str) -> None:
    """Pins a variable font to the regular weight and keeps only these."""
    font = TTFont(path)
    if 'fvar' in font:
        font = instancer.instantiateVariableFont(
            font, {'wght': 400, 'wdth': 100}, inplace=True
        )
    options = subset.Options()
    options.layout_features = ['*']  # the marks are positioned by GPOS
    options.name_IDs = ['*']
    options.notdef_outline = True
    options.drop_tables += ['DSIG']
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)
    font.save(out)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip())
        return 2
    hebrew_src, latin_src = argv
    cut(hebrew_src, HEBREW, '/tmp/_scripture-hebrew.ttf')
    cut(latin_src, MARKS, '/tmp/_scripture-marks.ttf')

    merged = Merger().merge(
        ['/tmp/_scripture-hebrew.ttf', '/tmp/_scripture-marks.ttf']
    )
    name = merged['name']
    name.setName('OpenWord Scripture Fallback', 1, 3, 1, 0x409)
    name.setName('Regular', 2, 3, 1, 0x409)
    name.setName('OpenWord Scripture Fallback', 4, 3, 1, 0x409)
    name.setName('OpenWordScriptureFallback-Regular', 6, 3, 1, 0x409)
    merged.save(OUT)

    cmap = TTFont(OUT).getBestCmap()
    letters = sum(1 for c in cmap if 0x05D0 <= c <= 0x05EA)
    points = sum(1 for c in cmap if 0x05B0 <= c <= 0x05C7)
    accents = sum(1 for c in cmap if 0x0591 <= c <= 0x05AF)
    marks = sum(1 for c in MARKS if c in cmap)
    print(f'{OUT}: {letters} letters, {points} points, {accents} accents, '
          f'{marks}/{len(MARKS)} modifier letters')
    if letters < 27 or accents < 31 or marks < len(MARKS):
        print('coverage is short — not usable', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
