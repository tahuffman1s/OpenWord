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
  because no device can be relied on for a face carrying the vowel points
  and cantillation marks the Hebrew text uses.
- Speech: made in the browser by
  [ONNX Runtime Web](https://github.com/microsoft/onnxruntime), MIT,
  running [KittenTTS](https://github.com/KittenML/KittenTTS) nano 0.8,
  Apache-2.0. How each word is said comes from
  [eSpeak NG](https://github.com/espeak-ng/espeak-ng), compiled to
  WebAssembly, with its pronunciation data, inside the
  [`phonemizer`](https://github.com/xenova/phonemizer.js) package. The
  package is Apache-2.0; eSpeak NG itself is GPL-3.0, and the app as built
  and served carries it, so the built app is distributed under the GPL's
  terms as well as the MIT licence of the code here. Settings credits all
  of these and says where the source of the eSpeak NG built in can be had,
  and Settings → *Licences* shows these licences in full; the texts are in
  `assets/licences/`.
- Bundled typeface: [Literata](https://fonts.google.com/specimen/Literata),
  SIL Open Font License 1.1 — see `assets/fonts/Literata-OFL.txt`. It is
  subset to Latin, Greek and the punctuation the text uses.
- Libraries the app is built with: [Preact](https://preactjs.com/), MIT;
  [Material Color Utilities](https://github.com/material-foundation/material-color-utilities),
  Apache-2.0; [Material Design icons](https://github.com/google/material-design-icons),
  Apache-2.0; [fflate](https://github.com/101arrowz/fflate), MIT;
  [Workbox](https://github.com/GoogleChrome/workbox), MIT; and
  [htmlparser2](https://github.com/fb55/htmlparser2), MIT. The smaller ones
  — Preact Signals (MIT), domhandler and domutils (BSD-2-Clause), idb (ISC)
  — are named with these under Settings → *Licences*.
