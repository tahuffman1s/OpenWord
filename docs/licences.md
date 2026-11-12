# Licences and credits

[← Back to the README](../README.md)


- Application code: [MIT](../LICENSE) — including the `.bib` format and its
  implementation, so anything else may read or write one.
- Scripture text: public domain (see [Translations](translations.md)). An imported translation
  carries whatever licence its own file states; OpenWord shows it and does not
  guess at one.
- Hebrew text, its Strong's numbers, parsing and versification map:
  [Open Scriptures Hebrew Bible](https://github.com/openscriptures/morphhb),
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- Greek text, with Strong's numbers and parsing: the
  [Byzantine Majority Text](https://github.com/byztxt/byzantine-majority-text)
  of Robinson and Pierpont, public domain.
- Strong's dictionaries of Hebrew and Greek:
  [Open Scriptures](https://github.com/openscriptures/strongs), CC BY-SA —
  the 1890 and 1894 works are themselves public domain. Shared alike: any
  redistribution of this edition of them must carry the same licence.
- Cross-references: [CrossReferences.org](https://crossreferences.org), after
  the Treasury of Scripture Knowledge,
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — attribution is
  shown on the cross-reference sheet itself.
- Place locations: [OpenBible.info Bible Geocoding](https://www.openbible.info/geo/),
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — attribution is
  shown on the map itself and in Settings. Base map, built-up areas and modern
  towns: [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/),
  public domain.
- Book introductions: Aquifer Open Study Notes (Book Intros) © Mission Mutual,
  an adaptation of Tyndale Open Study Notes © 2023 Tyndale House Publishers,
  both [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Shared
  alike: any redistribution of these introductions, adapted or not, must carry
  the same licence and this attribution.
- Scripture typeface: [Noto Serif Hebrew](https://github.com/notofonts/hebrew)
  and [Noto Serif](https://fonts.google.com/noto/specimen/Noto+Serif), SIL
  Open Font License 1.1 — see `assets/fonts/NotoSerif-OFL.txt`. Merged and
  subset to the two gaps Literata leaves: the Hebrew block and the thirteen
  modifier letters Strong's transliterates with, 16 kB in all. It is bundled
  because no platform can be relied on for a face carrying the vowel points
  and cantillation marks the Hebrew text uses; the web has none at all.
- Speech: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) and
  [ONNX Runtime](https://github.com/microsoft/onnxruntime), Apache-2.0 and
  MIT. sherpa-onnx's native library has
  [eSpeak NG](https://github.com/espeak-ng/espeak-ng) compiled in, to turn
  text into the sounds the voices speak, and eSpeak NG is GPL-3.0: a build
  of OpenWord carries that library, so its binaries are distributed under
  the GPL's terms as well as the MIT licence of the code here. The voice is
  [KittenTTS](https://github.com/KittenML/KittenTTS) nano 0.8, Apache-2.0,
  bundled with eSpeak NG's English pronunciation data (GPL-3.0). Settings
  credits all of these, links the source of the eSpeak NG built in, and
  shows every licence in full under *Licences*; the texts are in
  `assets/licences/`.
- Bundled typeface: [Literata](https://fonts.google.com/specimen/Literata),
  SIL Open Font License 1.1 — see `assets/fonts/Literata-OFL.txt`. It is
  subset to Latin, Greek and the punctuation the text uses.
