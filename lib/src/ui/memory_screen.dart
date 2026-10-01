import 'dart:math';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/learn_voice.dart';
import '../data/marks.dart';
import '../data/read_aloud.dart';
import '../model/bible.dart';
import '../model/memory_exercise.dart';
import '../model/memory_verse.dart';
import 'widgets/scripture_text.dart';

/// Practising the verses being learnt by heart: the ones due today, one
/// after another, each set as an exercise the verse's rung calls for —
/// tiles to put in order, blanks to fill, the verse heard and put
/// together, or written out — and checked. A right answer climbs the
/// ladder; a wrong one drops to the bottom and is asked again before the
/// session ends. The verse can be heard at any point, where the device
/// has a voice.
///
/// Pops with a reference when the reader asks to open a verse in the
/// reader, and with nothing otherwise.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, this.first, this.seed});

  /// A verse to begin with, whether or not it is due; the due ones follow.
  final Reference? first;

  /// Fixes the shuffle, for a test; the app leaves it to chance.
  final int? seed;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

/// How an exercise ended.
enum _Outcome { right, wrong, shown }

class _MemoryScreenState extends State<MemoryScreen> {
  late final List<Reference> _queue;
  late final int _total;
  late final Random _random;
  int _done = 0;

  /// The voice, where there is one.
  LearnVoice? _voice;
  bool get _canListen => _voice?.isAvailable ?? false;

  /// Whether the voice speaks of its own accord: the verse as it appears,
  /// a tile as it is tapped, the verse again once checked.
  bool get _autoSpeak =>
      _canListen && AppScope.of(context).settings.learnAutoSpeak;

  // The exercise under way.
  Reference? _reference;
  String _text = '';
  MemoryExercise _exercise = MemoryExercise.arrangeShown;
  List<String> _tiles = const [];
  final List<int> _placed = [];
  Cloze? _cloze;
  List<String?> _filled = const [];
  final TextEditingController _typed = TextEditingController();
  bool _hinted = false;
  _Outcome? _outcome;

  /// Counts exercises begun, so each gets widgets of its own.
  int _round = 0;

  ReadingStore get _reading => AppScope.of(context).reading;

  @override
  void initState() {
    super.initState();
    _random = widget.seed == null ? Random() : Random(widget.seed);
    final scope = context.getInheritedWidgetOfExactType<AppScope>()!;
    final reading = scope.reading;
    // The queue is fixed when the screen opens: a verse answered inside
    // the session must not be asked again because it is still due, and
    // one not recalled is put back by hand.
    final first = widget.first;
    _queue = [
      if (first != null && reading.isMemorising(first)) first,
      for (final verse in reading.memoryDue)
        if (verse.reference != first) verse.reference,
    ];
    _total = _queue.length;

    final bible = scope.library.bible;
    if (bible != null) {
      _voice = LearnVoice(
        engine: createSpeechEngine(),
        language: bible.translation.language,
        rate: scope.settings.speechRate,
        voice: scope.settings.speechVoice,
      )..addListener(_voiceChanged);
    }
    _begin(reading, bible, autoSpeak: scope.settings.learnAutoSpeak);
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _voice?.removeListener(_voiceChanged);
    _voice?.dispose();
    _typed.dispose();
    super.dispose();
  }

  String _textOf(Bible? bible, Reference reference) {
    if (bible == null || reference.verse == null) return '';
    return bible
            .bookByCode(reference.bookCode)
            ?.chapter(reference.chapter)
            ?.verseText(reference.verse!) ??
        '';
  }

  /// Sets the exercise for the verse at the head of the queue, and has it
  /// spoken where it is shown or is to be heard.
  void _begin(ReadingStore reading, Bible? bible, {required bool autoSpeak}) {
    _round++;
    _outcome = null;
    _hinted = false;
    _placed.clear();
    _typed.clear();
    final reference = _queue.isEmpty ? null : _queue.first;
    _reference = reference;
    if (reference == null) return;
    _text = _textOf(bible, reference);
    final verse = reading.memoryFor(reference);
    _exercise = MemoryExercise.forRung(verse?.rung ?? 0, canListen: _canListen);
    final tiles = VerseTiles.of(_text);
    _tiles = _shuffled(tiles);
    _cloze = _text.isEmpty ? null : Cloze.make(_text, _random);
    _filled = List<String?>.filled(_cloze?.blanks.length ?? 0, null);
    final heard = _exercise == MemoryExercise.listenArrange;
    if (_text.isNotEmpty &&
        _canListen &&
        (heard || (autoSpeak && _exercise.showsText))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _voice?.say(_text);
      });
    }
  }

  /// The tiles in an order that is not the verse's, where there is one.
  List<String> _shuffled(List<String> tiles) {
    if (tiles.length < 2) return tiles;
    final out = [...tiles];
    for (var i = 0; i < 8; i++) {
      out.shuffle(_random);
      if (!VerseTiles.inOrder(out, _text)) return out;
    }
    return out.reversed.toList();
  }

  /// Says the verse, or stops it if it is being said; slowly when asked.
  void _speak({bool slow = false}) {
    final voice = _voice;
    if (voice == null || !_canListen || _text.isEmpty) return;
    if (voice.isSpeaking && !slow) {
      voice.stop();
      return;
    }
    voice.say(_text, slow: slow);
  }

  /// A tile tapped is heard, the way a word tile is in a language app.
  void _place(int i) {
    setState(() => _placed.add(i));
    if (_autoSpeak) _voice?.say(_tiles[i]);
  }

  void _fill(String word) {
    setState(() {
      final at = _filled.indexOf(null);
      if (at >= 0) _filled[at] = word;
    });
    if (_autoSpeak) _voice?.say(word);
  }

  bool get _answered => switch (_exercise) {
    MemoryExercise.fillBlanks => _filled.every((w) => w != null),
    MemoryExercise.typeOut => _typed.text.trim().isNotEmpty,
    _ => _placed.length == _tiles.length,
  };

  void _check() {
    final right = switch (_exercise) {
      MemoryExercise.fillBlanks => _cloze!.check(_filled),
      MemoryExercise.typeOut => TypedVerse.matches(_typed.text, _text),
      _ => VerseTiles.inOrder([for (final i in _placed) _tiles[i]], _text),
    };
    _settle(right ? _Outcome.right : _Outcome.wrong);
  }

  void _show() => _settle(_Outcome.shown);

  void _settle(_Outcome outcome) {
    final reference = _reference!;
    _reading.reviewMemory(reference, remembered: outcome == _Outcome.right);
    _reading.recordPractice();
    setState(() => _outcome = outcome);
    // The verse is heard whole once it is answered, right or not.
    if (_autoSpeak) _voice?.say(_text);
  }

  /// Goes on to the next verse; one not answered is asked again before
  /// the session ends.
  void _continue() {
    final reference = _queue.removeAt(0);
    if (_outcome == _Outcome.right) {
      _done++;
    } else {
      _queue.add(reference);
    }
    final scope = AppScope.of(context);
    setState(
      () => _begin(
        scope.reading,
        scope.library.bible,
        autoSpeak: scope.settings.learnAutoSpeak,
      ),
    );
  }

  /// Skips a verse this translation has no text for.
  void _skip() {
    _queue.removeAt(0);
    final scope = AppScope.of(context);
    setState(
      () => _begin(
        scope.reading,
        scope.library.bible,
        autoSpeak: scope.settings.learnAutoSpeak,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = _reference;
    final verse = reference == null ? null : _reading.memoryFor(reference);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practise'),
        actions: [
          if (_canListen) const AutoSpeakButton(),
          if (reference != null)
            IconButton(
              icon: const Icon(Icons.menu_book_rounded),
              tooltip: 'Open in the reader',
              onPressed: () => Navigator.of(context).pop(reference),
            ),
        ],
        bottom: _total == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _done / _total,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
      ),
      body: reference == null || verse == null
          ? _Finished(total: _total, reading: _reading)
          : _text.isEmpty
          ? _NoText(reference: reference, onSkip: _skip)
          : _Exercise(
              key: ValueKey(_round),
              verse: verse,
              text: _text,
              exercise: _exercise,
              tiles: _tiles,
              placed: _placed,
              cloze: _cloze!,
              filled: _filled,
              typed: _typed,
              hinted: _hinted,
              outcome: _outcome,
              remaining: _queue.length,
              answered: _answered,
              speaking: _voice?.isSpeaking ?? false,
              onSpeak: _canListen ? _speak : null,
              onSpeakSlowly: _canListen ? () => _speak(slow: true) : null,
              onPlace: _place,
              onUnplace: (at) => setState(() => _placed.removeAt(at)),
              onFill: _fill,
              onUnfill: (blank) => setState(() => _filled[blank] = null),
              onTyped: () => setState(() {}),
              onHint: () => setState(() => _hinted = true),
              onShow: _show,
              onCheck: _check,
              onContinue: _continue,
            ),
    );
  }
}

class _Exercise extends StatelessWidget {
  const _Exercise({
    required this.verse,
    required this.text,
    required this.exercise,
    required this.tiles,
    required this.placed,
    required this.cloze,
    required this.filled,
    required this.typed,
    required this.hinted,
    required this.outcome,
    required this.remaining,
    required this.answered,
    required this.speaking,
    required this.onSpeak,
    required this.onSpeakSlowly,
    required this.onPlace,
    required this.onUnplace,
    required this.onFill,
    required this.onUnfill,
    required this.onTyped,
    required this.onHint,
    required this.onShow,
    required this.onCheck,
    required this.onContinue,
    super.key,
  });

  final MemoryVerse verse;
  final String text;
  final MemoryExercise exercise;
  final List<String> tiles;
  final List<int> placed;
  final Cloze cloze;
  final List<String?> filled;
  final TextEditingController typed;
  final bool hinted;
  final _Outcome? outcome;
  final int remaining;
  final bool answered;
  final bool speaking;
  final VoidCallback? onSpeak;
  final VoidCallback? onSpeakSlowly;
  final ValueChanged<int> onPlace;
  final ValueChanged<int> onUnplace;
  final ValueChanged<String> onFill;
  final ValueChanged<int> onUnfill;
  final VoidCallback onTyped;
  final VoidCallback onHint;
  final VoidCallback onShow;
  final VoidCallback onCheck;
  final VoidCallback onContinue;

  bool get _over => outcome != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = AppScope.of(context).settings;
    final scripture = ScriptureStyle.of(context, settings).body;
    final tile = scripture.copyWith(fontSize: scripture.fontSize! * 0.9);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    verse.reference.label,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _standing(verse, remaining),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onSpeak != null)
              SpeakButtons(
                speaking: speaking,
                onSpeak: onSpeak!,
                onSpeakSlowly: onSpeakSlowly!,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(exercise.label, style: theme.textTheme.titleMedium),
        Text(
          exercise.instruction,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (hinted && !exercise.showsText) ...[
          const SizedBox(height: 8),
          Text(
            MemoryPrompt.hint(text),
            style: tile.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        if (exercise == MemoryExercise.arrangeShown)
          _Card(child: Text(text, style: scripture)),
        if (exercise == MemoryExercise.fillBlanks)
          _Card(
            child: _ClozeText(
              cloze: cloze,
              filled: filled,
              style: scripture,
              onUnfill: _over ? null : onUnfill,
            ),
          ),
        if (exercise.usesTiles) ...[
          if (exercise == MemoryExercise.arrangeShown)
            const SizedBox(height: 12),
          _Answer(
            key: const Key('answer'),
            empty: exercise == MemoryExercise.listenArrange
                ? 'Listen, then tap the tiles in order.'
                : 'Tap the tiles in order.',
            children: [
              for (var at = 0; at < placed.length; at++)
                _Tile(
                  text: tiles[placed[at]],
                  style: tile,
                  placed: true,
                  onTap: _over ? null : () => onUnplace(at),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            key: const Key('bank'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < tiles.length; i++)
                _Tile(
                  key: ValueKey('bank/$i'),
                  text: tiles[i],
                  style: tile,
                  used: placed.contains(i),
                  onTap: _over || placed.contains(i) ? null : () => onPlace(i),
                ),
            ],
          ),
        ],
        if (exercise == MemoryExercise.fillBlanks) ...[
          const SizedBox(height: 12),
          Wrap(
            key: const Key('bank'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < cloze.bank.length; i++)
                _Tile(
                  key: ValueKey('bank/$i'),
                  text: cloze.bank[i],
                  style: tile,
                  used: _bankUsed(i),
                  onTap: _over || _bankUsed(i) || !filled.contains(null)
                      ? null
                      : () => onFill(cloze.bank[i]),
                ),
            ],
          ),
        ],
        if (exercise == MemoryExercise.typeOut)
          TextField(
            key: const Key('typed'),
            controller: typed,
            enabled: !_over,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            style: scripture,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => onTyped(),
            decoration: const InputDecoration(
              hintText: 'The verse, as you remember it',
              border: OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 20),
        if (!_over)
          Row(
            children: [
              if (!exercise.showsText && !hinted)
                TextButton.icon(
                  onPressed: onHint,
                  icon: const Icon(Icons.lightbulb_outline_rounded),
                  label: const Text('Hint'),
                ),
              TextButton.icon(
                onPressed: onShow,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Show me'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: answered ? onCheck : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Check'),
              ),
            ],
          )
        else ...[
          _Verdict(
            outcome: outcome!,
            verse: verse,
            text: text,
            style: scripture,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Continue'),
          ),
        ],
      ],
    );
  }

  /// Whether the nth bank word is sitting in a blank. The same word can
  /// be in the bank twice only when it is wanted twice, so the first
  /// unused copy is the one counted as used.
  bool _bankUsed(int i) {
    final word = cloze.bank[i];
    final inBlanks = filled.where((w) => w == word).length;
    var earlier = 0;
    for (var j = 0; j < i; j++) {
      if (cloze.bank[j] == word) earlier++;
    }
    return earlier < inBlanks;
  }

  static String _standing(MemoryVerse verse, int remaining) {
    final where = verse.isLearnt
        ? 'Learnt'
        : verse.rung == 0
        ? 'New'
        : 'Rung ${verse.rung} of ${MemoryVerse.intervals.length}';
    final times = switch (verse.recalled) {
      0 => 'not yet recalled',
      1 => 'recalled once',
      final n => 'recalled $n times',
    };
    final left = remaining == 1 ? 'the last one today' : '$remaining to go';
    return '$where · $times · $left';
  }
}

/// A verse with its blanks, the filled ones tappable to empty again.
class _ClozeText extends StatelessWidget {
  const _ClozeText({
    required this.cloze,
    required this.filled,
    required this.style,
    required this.onUnfill,
  });

  final Cloze cloze;
  final List<String?> filled;
  final TextStyle style;
  final ValueChanged<int>? onUnfill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    for (var i = 0; i < cloze.words.length; i++) {
      final word = cloze.words[i];
      final blank = cloze.blanks.indexOf(i);
      if (blank < 0) {
        spans.add(TextSpan(text: '${word.lead}${word.core}${word.trail} '));
        continue;
      }
      final answer = filled[blank];
      spans
        ..add(TextSpan(text: word.lead))
        ..add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InkWell(
              key: ValueKey('blank/$i'),
              onTap: answer == null || onUnfill == null
                  ? null
                  : () => onUnfill!(blank),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                constraints: const BoxConstraints(minWidth: 56),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: answer == null
                      ? Colors.transparent
                      : scheme.primaryContainer,
                  border: Border(
                    bottom: BorderSide(color: scheme.primary, width: 2),
                  ),
                ),
                child: Text(
                  answer ?? '',
                  style: style.copyWith(
                    color: scheme.onPrimaryContainer,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        )
        ..add(TextSpan(text: '${word.trail} '));
    }
    return Text.rich(TextSpan(children: spans, style: style));
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

/// Where placed tiles go: a box that reads as the answer being built.
class _Answer extends StatelessWidget {
  const _Answer({required this.children, required this.empty, super.key});

  final List<Widget> children;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: children.isEmpty
          ? Center(
              child: Text(
                empty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : Wrap(spacing: 8, runSpacing: 8, children: children),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.text,
    required this.style,
    required this.onTap,
    this.placed = false,
    this.used = false,
    super.key,
  });

  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  /// In the answer rather than the bank.
  final bool placed;

  /// A bank tile already placed: its slot stays, emptied.
  final bool used;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: used ? 0.25 : 1,
      child: Material(
        color: placed ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: placed ? scheme.primary : scheme.outline,
            width: placed ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              text,
              style: style.copyWith(
                color: placed ? scheme.onPrimaryContainer : scheme.onSurface,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the check found, and the verse where it was not had.
class _Verdict extends StatelessWidget {
  const _Verdict({
    required this.outcome,
    required this.verse,
    required this.text,
    required this.style,
  });

  final _Outcome outcome;
  final MemoryVerse verse;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final right = outcome == _Outcome.right;
    final heading = switch (outcome) {
      _Outcome.right => 'Nicely done.',
      _Outcome.wrong => 'Not quite.',
      _Outcome.shown => 'Here it is.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: right ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                right ? Icons.check_circle_rounded : Icons.replay_rounded,
                color: right
                    ? scheme.onPrimaryContainer
                    : scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Text(
                heading,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: right
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!right)
            Text(text, style: style.copyWith(color: scheme.onErrorContainer)),
          if (!right) const SizedBox(height: 8),
          Text(
            right
                ? _nextWait(verse)
                : 'Back to the first rung; asked again today.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: right
                  ? scheme.onPrimaryContainer
                  : scheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  /// [verse] is as it stood before the answer: the wait is the one its
  /// rung set.
  static String _nextWait(MemoryVerse verse) {
    final rung = verse.rung - 1;
    final wait =
        MemoryVerse.intervals[rung.clamp(0, MemoryVerse.intervals.length - 1)];
    return wait == 1 ? 'Asked again tomorrow.' : 'Asked again in $wait days.';
  }
}

class _NoText extends StatelessWidget {
  const _NoText({required this.reference, required this.onSkip});

  final Reference reference;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reference.label, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'This translation has no text for this verse, so it is left '
              'for another.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onSkip, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}

/// The end of a session, or a session with nothing in it.
class _Finished extends StatelessWidget {
  const _Finished({required this.total, required this.reading});

  final int total;
  final ReadingStore reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verses = reading.memoryVerses;
    final today = reading.today;
    MemoryVerse? next;
    for (final verse in verses) {
      if (verse.isDueOn(today)) continue;
      if (next == null || verse.due.isBefore(next.due)) next = verse;
    }
    final String heading;
    final String detail;
    if (verses.isEmpty) {
      heading = 'Nothing to practise yet';
      detail = 'Tap a verse while reading and choose Memorise.';
    } else if (total == 0) {
      heading = 'Nothing due today';
      detail = next == null ? '' : _nextLine(next, today);
    } else {
      heading = total == 1
          ? 'That’s the verse for today'
          : 'That’s all $total for today';
      detail = next == null ? '' : _nextLine(next, today);
    }
    final streak = reading.streak.currentOn(today);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (streak > 0) ...[
              const SizedBox(height: 16),
              StreakBadge(days: streak, large: true),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  static String _nextLine(MemoryVerse next, DateTime today) {
    final days = next.daysUntilDueOn(today);
    final when = days <= 1 ? 'tomorrow' : 'in $days days';
    return 'Next up: ${next.reference.label}, $when.';
  }
}

/// A flame and a count: the days in a row with learning done.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.days, this.large = false});

  final int days;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = days == 1 ? '1-day streak' : '$days-day streak';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 10,
        vertical: large ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: large ? 24 : 18,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style:
                (large
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.labelLarge)
                    ?.copyWith(color: scheme.onTertiaryContainer),
          ),
        ],
      ),
    );
  }
}

/// The speaker and its slower twin, as a language app has them: hear
/// it, and hear it slowly.
class SpeakButtons extends StatelessWidget {
  const SpeakButtons({
    super.key,
    required this.speaking,
    required this.onSpeak,
    required this.onSpeakSlowly,
  });

  final bool speaking;
  final VoidCallback onSpeak;
  final VoidCallback onSpeakSlowly;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filledTonal(
        tooltip: speaking ? 'Stop' : 'Hear the verse',
        isSelected: speaking,
        icon: Icon(speaking ? Icons.stop_rounded : Icons.volume_up_rounded),
        onPressed: onSpeak,
      ),
      IconButton.outlined(
        tooltip: 'Hear it slowly',
        icon: const Icon(Icons.slow_motion_video_rounded),
        onPressed: onSpeakSlowly,
      ),
    ],
  );
}

/// Switches whether the learning screens speak of their own accord.
class AutoSpeakButton extends StatelessWidget {
  const AutoSpeakButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final on = settings.learnAutoSpeak;
        return IconButton(
          tooltip: on ? 'Reading aloud: on' : 'Reading aloud: off',
          icon: Icon(on ? Icons.volume_up_outlined : Icons.volume_off_outlined),
          onPressed: () => settings.learnAutoSpeak = !on,
        );
      },
    );
  }
}

/// How a verse's due date reads in a list, today being [today].
String memoryDueLabel(MemoryVerse verse, DateTime today) {
  final days = verse.daysUntilDueOn(today);
  if (days <= 0) return 'Due today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}
