import 'package:openword/src/data/usfx_parser.dart';
import 'package:openword/src/model/bible.dart';

const TranslationInfo testTranslation = TranslationInfo(
  id: 'test',
  name: 'Test Edition',
  abbreviation: 'TST',
  license: 'Public Domain',
  sourceUrl: 'https://example.invalid/',
);

/// A small USFX document exercising every structure the reader lays out:
/// front matter, book titles and introductions (all dropped), prose
/// paragraphs, poetry indent levels, psalm titles, section headings, stanza
/// breaks, footnotes, translator additions, Selah and words of Jesus.
const String usfxFixture = '''
<?xml version="1.0" encoding="UTF-8"?>
<usfx><languageCode>eng</languageCode>
<book id="FRT"><p sfm="ip">Front matter that is not Scripture.</p></book>
<book id="GEN"><id id="GEN">Test Edition</id><h>Genesis</h>
<toc level="1">The First Book of Moses</toc>
<p sfm="mt">Genesis</p><p sfm="ip">An introduction.</p>
<c id="1"/>
<p><v id="1"/>In the beginning, God<f caller="+"><fr>1:1</fr><ft>Elohim.</ft></f> created the heavens.
<ve/><v id="2"/>The earth was <add>formless</add> and empty.
<ve/></p>
<p><v id="3"/>God said, "Let there be light."
<ve/></p>
<c id="2"/>
<p><v id="1"/>The second chapter.
<ve/></p>
</book>
<book id="PSA"><h>Psalms</h>
<c id="1"/>
<p sfm="ms">BOOK 1</p>
<d>A Psalm by David.</d>
<q><v id="1"/>Blessed is the man
</q><q level="2">who does not walk in the counsel of the wicked.<qs>Selah.</qs>
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

Bible parseFixture() => UsfxParser.parse(usfxFixture, testTranslation);
