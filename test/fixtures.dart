import 'dart:io';

import 'package:flutter/services.dart';
import 'package:openword/src/data/usfx_parser.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/bible_codec.dart';

const TranslationInfo testTranslation = TranslationInfo(
  id: 'eng-web',
  name: 'Test Edition',
  abbreviation: 'TST',
  license: 'Public Domain',
  sourceUrl: 'https://example.invalid/',
);

const TranslationInfo otherTranslation = TranslationInfo(
  id: 'eng-bsb',
  name: 'Other Edition',
  abbreviation: 'OTH',
  license: 'Public Domain',
  sourceUrl: 'https://example.invalid/other',
);

/// A small USFX document exercising every structure the reader lays out:
/// front matter, book titles and introductions (all dropped), prose
/// paragraphs, poetry indent levels, psalm titles, section headings, parallel
/// passage references, stanza breaks, footnotes, translator additions, Selah
/// and words of Jesus.
const String usfxFixture = '''
<?xml version="1.0" encoding="UTF-8"?>
<usfx><languageCode>eng</languageCode>
<book id="FRT"><p sfm="ip">Front matter that is not Scripture.</p></book>
<book id="GEN"><id id="GEN">Test Edition</id><h>Genesis</h>
<toc level="1">The First Book of Moses</toc>
<p sfm="mt">Genesis</p><p sfm="ip">An introduction.</p>
<c id="1"/>
<p sfm="s">The Creation</p>
<p sfm="r">(Psalms 1:1; Matthew 1)</p>
<p><v id="1"/>In the beginning, God<f caller="+"><fr>1:1</fr><ft>Elohim.</ft></f> created the heavens.
<ve/><v id="2"/>The earth was <add>formless</add> and empty.
<ve/></p>
<p><v id="3"/>God said, "Let there be light."
<ve/></p>
<p sfm="m"><v id="4"/>A paragraph set flush to the margin.
<ve/></p>
<p sfm="pi"><v id="5"/>An indented paragraph.
<ve/></p>
<p sfm="sp">Eliphaz the Temanite
</p>
<c id="2"/>
<p><v id="1"/>The second chapter.
<ve/></p>
</book>
<book id="PSA"><h>Psalms</h>
<c id="1"/>
<p sfm="ms">BOOK 1</p>
<d>A Psalm by David.</d>
<q><v id="1"/>Blessed is the man
</q><q level="2">who does not walk in the counsel of the wicked. <qs>Selah.</qs>
<ve/></q>
<b/>
<q><v id="2"/>But his delight is in the law.
<ve/></q>
</book>
<book id="MAT"><h>Matthew</h>
<c id="1"/>
<p><v id="1"/>He said, <wj>Follow me.</wj> Then they followed.
<ve/></p>
</book>
</usfx>
''';

/// The same books in a second translation, for the compare view.
const String otherUsfxFixture = '''
<?xml version="1.0" encoding="UTF-8"?>
<usfx><languageCode>eng</languageCode>
<book id="GEN"><h>Genesis</h>
<c id="1"/>
<p><v id="1"/>At the first God made the heaven and the earth.
<ve/><v id="2"/>And the earth was waste and without form.
<ve/><v id="3"/>And God said, Let there be light.
<ve/></p>
<c id="2"/>
<p><v id="1"/>Chapter two, differently worded.
<ve/></p>
</book>
<book id="PSA"><h>Psalms</h>
<c id="1"/>
<p><v id="1"/>Happy is the man who does not go in the company of sinners.
<ve/><v id="2"/>But his delight is in the law of the Lord.
<ve/></p>
</book>
<book id="MAT"><h>Matthew</h>
<c id="1"/>
<p><v id="1"/>He said, Come after me. And they went with him.
<ve/></p>
</book>
</usfx>
''';

Bible parseFixture() => UsfxParser.parse(usfxFixture, testTranslation);

/// One book with a chapter long enough to need scrolling, for testing jumps
/// to a verse far down the page.
String longUsfxFixture({
  int verses = 80,
  int chapters = 1,
  int versesPerParagraph = 1,
}) {
  final buffer = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>\n<usfx><book id="GEN">'
    '<h>Genesis</h>',
  );
  for (var chapter = 1; chapter <= chapters; chapter++) {
    buffer.write('<c id="$chapter"/>');
    for (var verse = 1; verse <= verses; verse++) {
      // Verses flow together inside a paragraph, as prose does, so only the
      // first verse of each paragraph is an anchor.
      if (verse % versesPerParagraph == 1 || versesPerParagraph == 1) {
        if (verse > 1) buffer.write('</p>');
        buffer.write('<p>');
      }
      buffer.write(
        '<v id="$verse"/>Chapter $chapter verse $verse of a passage '
        'written to be tall enough that reaching its end takes some '
        'scrolling.<ve/>',
      );
    }
    buffer.write('</p>');
  }
  buffer.write('</book></usfx>');
  return buffer.toString();
}

Bible parseLongFixture({
  int verses = 80,
  int chapters = 1,
  int versesPerParagraph = 1,
}) => UsfxParser.parse(
  longUsfxFixture(
    verses: verses,
    chapters: chapters,
    versesPerParagraph: versesPerParagraph,
  ),
  testTranslation,
);

Bible parseOtherFixture() =>
    UsfxParser.parse(otherUsfxFixture, otherTranslation);

/// An [AssetBundle] serving the fixtures the way the real bundle serves the
/// shipped translations: gzipped [BibleCodec] data.
class FixtureBundle extends CachingAssetBundle {
  FixtureBundle({Map<String, Uint8List>? assets, Bible? bible})
    : assets =
          assets ??
          {
            'assets/bible/${testTranslation.id}.owb.gz': _pack(
              bible ?? parseFixture(),
            ),
            'assets/bible/${otherTranslation.id}.owb.gz': _pack(
              parseOtherFixture(),
            ),
          };

  final Map<String, Uint8List> assets;
  final List<String> loaded = [];

  static Uint8List _pack(Bible bible) =>
      Uint8List.fromList(gzip.encode(BibleCodec.encode(bible)));

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final data = assets[key];
    if (data == null) {
      throw StateError('Fixture bundle has no asset "$key"');
    }
    return ByteData.sublistView(data);
  }
}
