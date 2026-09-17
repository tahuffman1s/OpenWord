import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:openword/src/data/atlas.dart';
import 'package:openword/src/data/book_intros.dart';
import 'package:openword/src/data/update_backend.dart';
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
            BookIntros.assetPath: packIntros(fixtureIntros),
            Atlas.assetPath: packJson(fixtureAtlas),
          };

  final Map<String, Uint8List> assets;
  final List<String> loaded = [];

  static Uint8List _pack(Bible bible) =>
      Uint8List.fromList(gzip.encode(BibleCodec.encode(bible)));

  /// The book introductions in the shape the asset uses: gzipped JSON.
  static Uint8List packIntros(Map<String, String> intros) => packJson(intros);

  static Uint8List packJson(Object? value) =>
      Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(value))));

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

/// Stand-ins for the bundled introductions, in the shape the real ones take:
/// a lead paragraph, then underlined top-level sections, one of them with a
/// sub-heading below it.
const Map<String, String> fixtureIntros = {
  'GEN':
      'Genesis is a book of **beginnings**.\n'
      '\n'
      'Setting\n'
      '=======\n'
      '\n'
      'It opens in Ur of the Chaldees.\n'
      '\n'
      'Author\n'
      '======\n'
      '\n'
      'Traditionally Moses.\n'
      '\n'
      'Genres\n'
      '------\n'
      '\n'
      'Narrative, with genealogies.\n',
  'PSA': 'A collection of prayers and songs.\n',
};

/// A stand-in atlas: two places in the fixture's first book, a scrap of
/// coastline and a river, in the same shape the real asset takes.
const Map<String, Object?> fixtureAtlas = {
  'version': 1,
  'bounds': [34000, 31000, 36000, 33000],
  'places': [
    ['Bethel', 'settlement', 35220, 31930, 1000],
    ['Ai', 'settlement', 35270, 31917, 300],
  ],
  'chapters': {
    'GEN 1': [0],
    'GEN 2': [0, 1],
  },
  'land': [
    [34000, 31000, 36000, 31000, 36000, 33000, 34000, 33000],
  ],
  'lakes': <Object?>[],
  'rivers': [
    [35000, 31000, 35100, 32000, 35200, 33000],
  ],
};

/// A stand-in for the platform: no sockets, no installer, and a record of
/// what the service asked it to do.
class FakeUpdateBackend implements UpdateBackend {
  FakeUpdateBackend({
    this.body = '{}',
    this.target = TargetKind.android,
    this.isSupported = true,
    this.canInstall = true,
    this.failWith,
  });

  String body;
  @override
  TargetKind target;
  @override
  bool isSupported;
  @override
  bool canInstall;

  /// Thrown by every call when set, standing in for a dead network.
  Object? failWith;

  int reads = 0;
  final List<Uri> downloads = [];
  final List<String> installs = [];
  final List<Uri> opened = [];

  /// Fed to the progress callback, as (received, total) pairs.
  List<List<int>> progress = const [
    [50, 100],
    [100, 100],
  ];

  @override
  Future<String> readString(Uri url) async {
    reads++;
    final failure = failWith;
    if (failure != null) throw failure;
    return body;
  }

  @override
  Future<String> download(
    Uri url, {
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    downloads.add(url);
    final failure = failWith;
    if (failure != null) throw failure;
    for (final step in progress) {
      onProgress?.call(step[0], step[1]);
    }
    return '/tmp/$fileName';
  }

  @override
  Future<void> install(String path) async {
    installs.add(path);
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<void> openExternal(Uri url) async {
    opened.add(url);
    final failure = failWith;
    if (failure != null) throw failure;
  }
}

/// The shape of GitHub's `releases/latest`, trimmed to what is read.
String releaseJson({
  String tag = 'v9.9.9',
  String? name,
  String notes = '### Added\n- Something new.\n',
  bool draft = false,
  bool prerelease = false,
  List<String>? assets,
}) {
  final files = assets ?? ['OpenWord-$tag-android.apk'];
  return jsonEncode({
    'tag_name': tag,
    'name': name ?? 'OpenWord $tag',
    'body': notes,
    'draft': draft,
    'prerelease': prerelease,
    'html_url': 'https://github.com/tahuffman1s/OpenWord/releases/tag/$tag',
    'assets': [
      for (final file in files)
        {
          'name': file,
          'browser_download_url':
              'https://github.com/tahuffman1s/OpenWord/releases/download/'
              '$tag/$file',
          'size': 57957565,
        },
    ],
  });
}
