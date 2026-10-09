import 'bible.dart';

/// Verses worth knowing by heart, for a reader with nothing on the ladder
/// yet, or one wondering what to add next.
///
/// The well-worn ones: the verses people reach for in comfort and in
/// trouble, the ones a child learns first. A translation that lacks one
/// simply does not offer it.
class SuggestedVerse {
  const SuggestedVerse(this.reference, this.theme);

  final Reference reference;

  /// What the verse is for, in a word: what a list groups it under.
  final String theme;

  static const List<SuggestedVerse> all = [
    SuggestedVerse(Reference('JHN', 3, 16), 'Love'),
    SuggestedVerse(Reference('PSA', 23, 1), 'Comfort'),
    SuggestedVerse(Reference('ROM', 8, 28), 'Trust'),
    SuggestedVerse(Reference('PHP', 4, 13), 'Strength'),
    SuggestedVerse(Reference('PRO', 3, 5), 'Trust'),
    SuggestedVerse(Reference('JER', 29, 11), 'Promise'),
    SuggestedVerse(Reference('ISA', 41, 10), 'Comfort'),
    SuggestedVerse(Reference('MAT', 11, 28), 'Comfort'),
    SuggestedVerse(Reference('PSA', 119, 105), 'Guidance'),
    SuggestedVerse(Reference('JOS', 1, 9), 'Strength'),
    SuggestedVerse(Reference('PHP', 4, 6), 'Peace'),
    SuggestedVerse(Reference('1CO', 13, 4), 'Love'),
    SuggestedVerse(Reference('GAL', 5, 22), 'Character'),
    SuggestedVerse(Reference('HEB', 11, 1), 'Faith'),
    SuggestedVerse(Reference('2TI', 3, 16), 'Scripture'),
    SuggestedVerse(Reference('EPH', 2, 8), 'Grace'),
    SuggestedVerse(Reference('ROM', 12, 2), 'Character'),
    SuggestedVerse(Reference('PSA', 46, 1), 'Comfort'),
    SuggestedVerse(Reference('MAT', 6, 33), 'Trust'),
    SuggestedVerse(Reference('JHN', 14, 6), 'Jesus'),
    SuggestedVerse(Reference('1JN', 1, 9), 'Grace'),
    SuggestedVerse(Reference('PSA', 27, 1), 'Strength'),
    SuggestedVerse(Reference('ISA', 40, 31), 'Strength'),
    SuggestedVerse(Reference('2CO', 5, 17), 'Grace'),
    SuggestedVerse(Reference('JHN', 1, 1), 'Jesus'),
    SuggestedVerse(Reference('GEN', 1, 1), 'Beginnings'),
    SuggestedVerse(Reference('PSA', 1, 1), 'Guidance'),
    SuggestedVerse(Reference('MAT', 28, 19), 'Mission'),
  ];

  /// The suggestions [bible] has the text for, in the order above, with
  /// the ones already being learnt left out.
  static List<SuggestedVerse> available(
    Bible bible, {
    bool Function(Reference)? alreadyLearning,
  }) => [
    for (final suggestion in all)
      if (!(alreadyLearning?.call(suggestion.reference) ?? false))
        if (bible
                .bookByCode(suggestion.reference.bookCode)
                ?.chapter(suggestion.reference.chapter)
                ?.verseText(suggestion.reference.verse!)
                .isNotEmpty ??
            false)
          suggestion,
  ];
}
