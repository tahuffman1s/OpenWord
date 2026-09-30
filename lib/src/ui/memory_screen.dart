import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/marks.dart';
import '../model/bible.dart';
import '../model/memory_verse.dart';
import 'widgets/scripture_text.dart';

/// Practising the verses being learnt by heart: the ones due today, one
/// after another, each shown as much as the reader wants — the whole
/// verse, its first letters, or the reference alone — and then checked.
///
/// Pops with a reference when the reader asks to open a verse in the
/// reader, and with nothing otherwise.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, this.first});

  /// A verse to begin with, whether or not it is due; the due ones follow.
  final Reference? first;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late final List<Reference> _queue;
  late final int _total;

  /// A prompt the reader chose, kept for the rest of the session; until
  /// they choose one each verse is shown as its rung suggests.
  MemoryPrompt? _chosenPrompt;
  bool _revealed = false;
  int _done = 0;

  ReadingStore get _reading => AppScope.of(context).reading;

  @override
  void initState() {
    super.initState();
    // The queue is fixed when the screen opens: a verse rated inside the
    // session must not be asked again because it is still due, and one
    // not recalled is put back by hand.
    final reading = context.getInheritedWidgetOfExactType<AppScope>()!.reading;
    final first = widget.first;
    _queue = [
      if (first != null && reading.isMemorising(first)) first,
      for (final verse in reading.memoryDue)
        if (verse.reference != first) verse.reference,
    ];
    _total = _queue.length;
  }

  Reference? get _current => _queue.isEmpty ? null : _queue.first;

  MemoryPrompt _promptFor(MemoryVerse verse) =>
      _chosenPrompt ?? MemoryPrompt.forRung(verse.rung);

  String _textOf(Reference reference) {
    final bible = AppScope.of(context).library.bible;
    if (bible == null || reference.verse == null) return '';
    return bible
            .bookByCode(reference.bookCode)
            ?.chapter(reference.chapter)
            ?.verseText(reference.verse!) ??
        '';
  }

  void _rate({required bool remembered}) {
    final reference = _current;
    if (reference == null) return;
    _reading.reviewMemory(reference, remembered: remembered);
    setState(() {
      _queue.removeAt(0);
      // A verse not recalled is asked again before the session ends.
      if (!remembered) _queue.add(reference);
      if (remembered) _done++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = _current;
    final verse = reference == null ? null : _reading.memoryFor(reference);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practise'),
        actions: [
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
          : _Practice(
              key: ValueKey('${reference.encode()}/$_done/${_queue.length}'),
              verse: verse,
              text: _textOf(reference),
              prompt: _promptFor(verse),
              revealed: _revealed,
              remaining: _queue.length,
              onPrompt: (prompt) => setState(() {
                _chosenPrompt = prompt;
                _revealed = false;
              }),
              onReveal: () => setState(() => _revealed = true),
              onRate: _rate,
            ),
    );
  }
}

class _Practice extends StatelessWidget {
  const _Practice({
    required this.verse,
    required this.text,
    required this.prompt,
    required this.revealed,
    required this.remaining,
    required this.onPrompt,
    required this.onReveal,
    required this.onRate,
    super.key,
  });

  final MemoryVerse verse;
  final String text;
  final MemoryPrompt prompt;
  final bool revealed;
  final int remaining;
  final ValueChanged<MemoryPrompt> onPrompt;
  final VoidCallback onReveal;
  final void Function({required bool remembered}) onRate;

  /// Reading the verse over shows all of it, so there is nothing to reveal
  /// and the question can be asked straight away.
  bool get _showingAll => revealed || prompt == MemoryPrompt.read;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppScope.of(context).settings;
    final style = ScriptureStyle.of(context, settings).body;
    final missing = text.isEmpty;
    final shown = _showingAll ? text : prompt.apply(text);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Text(verse.reference.label, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          _standing(verse, remaining),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<MemoryPrompt>(
          segments: [
            for (final option in MemoryPrompt.values)
              ButtonSegment(value: option, label: Text(option.label)),
          ],
          selected: {prompt},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onPrompt(selection.first),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: missing
              ? Text(
                  'This translation has no text for this verse.',
                  style: style.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : shown.isEmpty
              ? Text(
                  'Say it to yourself, then show the verse to check.',
                  style: style.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Text(shown, style: style),
        ),
        const SizedBox(height: 24),
        if (!_showingAll && !missing)
          FilledButton.tonalIcon(
            onPressed: onReveal,
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Show the verse'),
          )
        else ...[
          Text(
            'Did you have it?',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onRate(remembered: false),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Not yet'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onRate(remembered: true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Got it'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _nextWait(verse),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
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

  static String _nextWait(MemoryVerse verse) {
    final wait = MemoryVerse
        .intervals[verse.rung.clamp(0, MemoryVerse.intervals.length - 1)];
    final when = wait == 1 ? 'tomorrow' : 'in $wait days';
    return 'Got it asks again $when; Not yet, later today.';
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

/// How a verse's due date reads in a list, today being [today].
String memoryDueLabel(MemoryVerse verse, DateTime today) {
  final days = verse.daysUntilDueOn(today);
  if (days <= 0) return 'Due today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}
