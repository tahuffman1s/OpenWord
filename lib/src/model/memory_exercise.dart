import 'dart:math';

import 'package:flutter/foundation.dart';

/// How a verse on the ladder is tested: the exercise a practice sets.
///
/// The ladder is climbed by answering, not by saying one had it. A new
/// verse is copied out from tiles with the text in view, then the blanks
/// in it filled, then put together from its tiles unseen — from hearing
/// it, where the device can speak — and then written out in full.
enum MemoryExercise {
  /// The verse shown; put its tiles in order beneath it.
  arrangeShown(
    'Put it together',
    'Tap the tiles in order. The verse is above.',
  ),

  /// The verse with words missing; fill them from the bank.
  fillBlanks('Fill the blanks', 'Tap a word for each gap, in order.'),

  /// The verse heard, not seen; put its tiles in order.
  listenArrange('Tap what you hear', 'Listen, then tap the tiles in order.'),

  /// The reference alone; put the tiles in order.
  arrange('From memory', 'Tap the tiles in the verse’s order.'),

  /// The reference alone; write the verse.
  typeOut('Write it out', 'Type the verse. Spelling slips are forgiven.');

  const MemoryExercise(this.label, this.instruction);

  final String label;
  final String instruction;

  /// Whether the exercise lets the verse be seen before it is answered.
  bool get showsText => this == arrangeShown || this == fillBlanks;

  /// Whether the exercise is answered from tiles rather than typed.
  bool get usesTiles =>
      this == arrangeShown || this == listenArrange || this == arrange;

  /// The exercise a verse on [rung] is ready for. Hearing it is asked
  /// only where there is a voice to hear.
  static MemoryExercise forRung(int rung, {required bool canListen}) =>
      switch (rung) {
        0 => arrangeShown,
        1 => fillBlanks,
        2 => canListen ? listenArrange : arrange,
        3 => arrange,
        _ => rung.isOdd ? (canListen ? listenArrange : arrange) : typeOut,
      };
}

/// The pieces a verse is put together from: its words, or runs of them
/// when there are too many words to lay out as tiles.
///
/// Up to [maxTiles] tiles. A long verse is cut into runs of two or more
/// words, ending at a clause break where one comes along, so that the
/// tiles read as phrases rather than as a scatter of "the" and "and".
abstract final class VerseTiles {
  static const int maxTiles = 12;

  static List<String> of(String text) {
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length <= maxTiles) return words;
    final size = (words.length / maxTiles).ceil();
    final tiles = <String>[];
    final run = <String>[];
    for (final word in words) {
      run.add(word);
      final breaks = _endsClause.hasMatch(word);
      if (run.length >= size || (breaks && run.length >= max(2, size ~/ 2))) {
        tiles.add(run.join(' '));
        run.clear();
      }
    }
    if (run.isNotEmpty) {
      // A short tail joins the tile before it rather than standing alone.
      if (run.length < max(2, size ~/ 2) && tiles.isNotEmpty) {
        tiles[tiles.length - 1] = '${tiles.last} ${run.join(' ')}';
      } else {
        tiles.add(run.join(' '));
      }
    }
    return tiles;
  }

  /// Whether [chosen], in that order, is the verse.
  static bool inOrder(List<String> chosen, String text) =>
      chosen.join(' ') == text.split(' ').where((w) => w.isNotEmpty).join(' ');

  static final RegExp _endsClause = RegExp(r'[,;:.!?]["”’]?$');
}

/// One word of a verse, with the punctuation around it kept apart, so
/// that a blank can stand for the word and keep its comma.
@immutable
class VerseWord {
  const VerseWord(this.lead, this.core, this.trail);

  final String lead;
  final String core;
  final String trail;

  static VerseWord parse(String word) {
    final match = _shape.firstMatch(word)!;
    return VerseWord(match.group(1)!, match.group(2)!, match.group(3)!);
  }

  static final RegExp _shape = RegExp(
    r'^([^\p{L}\p{N}]*)(.*?)([^\p{L}\p{N}]*)$',
    unicode: true,
  );
}

/// A verse with some of its words taken out, and a bank to fill them
/// from: the right words and as many wrong ones from the same verse.
@immutable
class Cloze {
  const Cloze({required this.words, required this.blanks, required this.bank});

  final List<VerseWord> words;

  /// Indices into [words] of the blanks, in order.
  final List<int> blanks;

  /// Words to fill the blanks from, shuffled.
  final List<String> bank;

  /// One word in [every] blanked, at least one and at most [most].
  static Cloze make(String text, Random random, {int every = 5, int most = 6}) {
    final words = text
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map(VerseWord.parse)
        .toList();
    final candidates = [
      for (var i = 0; i < words.length; i++)
        if (words[i].core.length >= 3) i,
    ]..shuffle(random);
    final count = (words.length / every).round().clamp(1, most);
    final blanks = candidates.take(count).toList()..sort();
    final blanked = {for (final i in blanks) words[i].core};
    final others = <String>{
      for (var i = 0; i < words.length; i++)
        if (!blanks.contains(i) &&
            words[i].core.length >= 3 &&
            !blanked.contains(words[i].core))
          words[i].core,
    }.toList()..shuffle(random);
    final bank = [
      for (final i in blanks) words[i].core,
      ...others.take(blanks.length),
    ]..shuffle(random);
    return Cloze(words: words, blanks: blanks, bank: bank);
  }

  /// The right word for the nth blank.
  String answer(int blank) => words[blanks[blank]].core;

  /// Whether [filled], one word per blank in order, is right throughout.
  bool check(List<String?> filled) {
    if (filled.length != blanks.length) return false;
    for (var i = 0; i < blanks.length; i++) {
      if (filled[i] != answer(i)) return false;
    }
    return true;
  }
}

/// Whether a verse written out is the verse: word for word once case and
/// punctuation are set aside, with one slip forgiven in any word of five
/// letters or more — a letter wrong, missing, added, or two swapped.
abstract final class TypedVerse {
  static bool matches(String typed, String text) {
    final given = words(typed);
    final wanted = words(text);
    if (given.length != wanted.length) return false;
    for (var i = 0; i < wanted.length; i++) {
      if (given[i] == wanted[i]) continue;
      if (wanted[i].length < 5 || editDistance(given[i], wanted[i]) > 1) {
        return false;
      }
    }
    return true;
  }

  /// The words of [text], lower case, with everything but letters,
  /// digits and apostrophes taken out.
  static List<String> words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[’‘]'), "'")
      .replaceAll(RegExp(r"[^\p{L}\p{N}']+", unicode: true), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  /// Edits to turn [a] into [b], a swap of two neighbouring letters
  /// counting as one.
  static int editDistance(String a, String b) {
    List<int>? before;
    var previous = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final current = [i, ...List<int>.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = min(
          min(previous[j] + 1, current[j - 1] + 1),
          previous[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1] &&
            before![j - 2] + 1 < best) {
          best = before[j - 2] + 1;
        }
        current[j] = best;
      }
      before = previous;
      previous = current;
    }
    return previous[b.length];
  }
}
