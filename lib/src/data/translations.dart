import '../model/bible.dart';

/// The translations that ship inside the app.
///
/// Every one is in the public domain, which is what makes it possible to
/// bundle the text instead of downloading it — the app never needs a network
/// connection, not even on first launch.
///
/// Adding one is two steps: put `<id>.usfx.xml` next to the others, add an
/// entry here, then run `dart run tool/build_assets.dart <dir>`.
class Translations {
  const Translations._();

  static const TranslationInfo web = TranslationInfo(
    id: 'eng-web',
    name: 'World English Bible',
    abbreviation: 'WEB',
    license: 'Public Domain',
    sourceUrl: 'https://ebible.org/web/',
  );

  static const TranslationInfo webbe = TranslationInfo(
    id: 'eng-gb-webbe',
    name: 'World English Bible, British Edition',
    abbreviation: 'WEBBE',
    license: 'Public Domain',
    sourceUrl: 'https://ebible.org/webbe/',
  );

  static const TranslationInfo bsb = TranslationInfo(
    id: 'eng-bsb',
    name: 'Berean Standard Bible',
    abbreviation: 'BSB',
    license: 'Public Domain',
    sourceUrl: 'https://berean.bible/',
  );

  /// Bundled in this order; the first is the default.
  static const List<TranslationInfo> all = [web, bsb, webbe];

  static TranslationInfo get fallback => web;

  static TranslationInfo byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => fallback);

  /// The bundled translations are `.bib` files, the same format an imported
  /// one takes — there is one way to read Scripture here, not two.
  static const String assetExtension = '.bib';

  static String assetFor(String id) => 'assets/bible/$id$assetExtension';
}
