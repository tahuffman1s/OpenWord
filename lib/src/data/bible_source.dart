import '../model/bible.dart';

/// A downloadable translation: where to get it and what it may be used for.
///
/// Only freely licensed texts are listed. The World English Bible is in the
/// public domain, which is what makes it safe to ship in a FOSS app.
class BibleSource {
  const BibleSource({
    required this.info,
    required this.mirrors,
    required this.approximateBytes,
  });

  final TranslationInfo info;

  /// Download URLs tried in order, so a single host going away is survivable.
  final List<String> mirrors;

  /// Rough download size, used for the progress bar before the server reports
  /// a content length.
  final int approximateBytes;

  String get id => info.id;

  static const BibleSource worldEnglishBible = BibleSource(
    info: TranslationInfo(
      id: 'eng-web',
      name: 'World English Bible',
      abbreviation: 'WEB',
      license: 'Public Domain',
      sourceUrl: 'https://ebible.org/web/',
    ),
    mirrors: [
      'https://raw.githubusercontent.com/seven1m/open-bibles/master/eng-web.usfx.xml',
      'https://ebible.org/usfx/eng-web_usfx.xml',
    ],
    approximateBytes: 6300000,
  );

  static const BibleSource worldEnglishBibleBritish = BibleSource(
    info: TranslationInfo(
      id: 'engwebbe',
      name: 'World English Bible, British Edition',
      abbreviation: 'WEBBE',
      license: 'Public Domain',
      sourceUrl: 'https://ebible.org/webbe/',
    ),
    mirrors: [
      'https://raw.githubusercontent.com/seven1m/open-bibles/master/eng-webbe.usfx.xml',
      'https://ebible.org/usfx/engwebbe_usfx.xml',
    ],
    approximateBytes: 6300000,
  );

  static const List<BibleSource> all = [
    worldEnglishBible,
    worldEnglishBibleBritish,
  ];

  static BibleSource byId(String id) =>
      all.firstWhere((source) => source.id == id, orElse: () => all.first);
}
