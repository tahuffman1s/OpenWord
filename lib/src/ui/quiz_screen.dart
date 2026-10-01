import 'dart:math';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/learn_voice.dart';
import '../data/read_aloud.dart';
import '../model/quiz.dart';
import 'memory_screen.dart' show AutoSpeakButton, SpeakButtons, StreakBadge;
import 'widgets/scripture_text.dart';

/// A round of questions drawn from the translation being read. Pops with
/// a reference when the reader asks to open a passage, and with nothing
/// otherwise.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.kind, this.seed});

  final QuizKind kind;

  /// Fixes the draw, for a test; the app leaves it to chance.
  final int? seed;

  static const int questionsPerRound = 10;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<QuizQuestion> _questions = const [];
  int _index = 0;
  int? _chosen;
  final List<QuizQuestion> _missed = [];
  int _right = 0;

  /// The voice, where there is one.
  LearnVoice? _voice;
  bool get _canListen => _voice?.isAvailable ?? false;

  @override
  void initState() {
    super.initState();
    final scope = context.getInheritedWidgetOfExactType<AppScope>()!;
    final bible = scope.library.bible;
    if (bible != null) {
      _voice =
          LearnVoice(
            engine: createSpeechEngine(),
            language: bible.translation.language,
            rate: scope.settings.speechRate,
            voice: scope.settings.speechVoice,
          )..addListener(() {
            if (mounted) setState(() {});
          });
    }
    _draw();
    _speakPrompt();
  }

  @override
  void dispose() {
    _voice?.dispose();
    super.dispose();
  }

  /// What the question has to be heard: its Scripture, where it shows
  /// any.
  String get _promptText {
    if (_index >= _questions.length) return '';
    final question = _questions[_index];
    return question.kind == QuizKind.finishVerse
        ? question.prompt.substring(0, question.prompt.length - 2)
        : question.prompt;
  }

  /// The whole verse, once a Finish the verse question is answered.
  String get _answerText {
    final question = _questions[_index];
    return question.kind == QuizKind.finishVerse
        ? '$_promptText ${question.correct}'
        : _promptText;
  }

  bool get _autoSpeak =>
      _canListen && AppScope.of(context).settings.learnAutoSpeak;

  /// Reads the question's Scripture as it appears, where that is wanted.
  void _speakPrompt() {
    final scope = context.getInheritedWidgetOfExactType<AppScope>()!;
    if (!_canListen || !scope.settings.learnAutoSpeak) return;
    final text = _promptText;
    if (text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _voice?.say(text);
    });
  }

  void _speak({bool slow = false}) {
    final voice = _voice;
    if (voice == null || !_canListen) return;
    if (voice.isSpeaking && !slow) {
      voice.stop();
      return;
    }
    final text = _chosen == null ? _promptText : _answerText;
    if (text.isNotEmpty) voice.say(text, slow: slow);
  }

  void _draw() {
    final scope = context.getInheritedWidgetOfExactType<AppScope>()!;
    final bible = scope.library.bible;
    _questions = bible == null
        ? const []
        : QuizMaker(
            bible,
            books: quizBooks(
              bible,
              deuterocanon: scope.settings.showDeuterocanon,
            ),
            random: widget.seed == null ? null : Random(widget.seed),
          ).make(widget.kind, count: QuizScreen.questionsPerRound);
    _index = 0;
    _chosen = null;
    _missed.clear();
    _right = 0;
  }

  void _choose(int option) {
    if (_chosen != null) return;
    final question = _questions[_index];
    setState(() {
      _chosen = option;
      if (option == question.answer) {
        _right++;
      } else {
        _missed.add(question);
      }
    });
    // Finishing a verse ends with the whole of it heard.
    if (_autoSpeak && question.kind == QuizKind.finishVerse) {
      _voice?.say(_answerText);
    }
  }

  static int _streakNow(BuildContext context) {
    final reading = AppScope.of(context).reading;
    return reading.streak.currentOn(reading.today);
  }

  void _next() {
    setState(() {
      _index++;
      _chosen = null;
    });
    // A round finished is a day's learning done.
    if (_index >= _questions.length) {
      _voice?.stop();
      AppScope.of(context).reading.recordPractice();
    } else {
      _speakPrompt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = _index >= _questions.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind.label),
        actions: [if (_canListen) const AutoSpeakButton()],
        bottom: _questions.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value:
                      (finished ? _questions.length : _index) /
                      _questions.length,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
      ),
      body: _questions.isEmpty
          ? _Empty()
          : finished
          ? _Result(
              right: _right,
              total: _questions.length,
              missed: _missed,
              streak: _streakNow(context),
              onAgain: () => setState(() {
                _draw();
                _speakPrompt();
              }),
            )
          : _Question(
              key: ValueKey(_index),
              question: _questions[_index],
              number: _index + 1,
              total: _questions.length,
              chosen: _chosen,
              onChoose: _choose,
              onNext: _next,
              isLast: _index == _questions.length - 1,
              speaking: _voice?.isSpeaking ?? false,
              onSpeak: _canListen && _promptText.isNotEmpty ? _speak : null,
              onSpeakSlowly: _canListen && _promptText.isNotEmpty
                  ? () => _speak(slow: true)
                  : null,
            ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.question,
    required this.number,
    required this.total,
    required this.chosen,
    required this.onChoose,
    required this.onNext,
    required this.isLast,
    required this.speaking,
    required this.onSpeak,
    required this.onSpeakSlowly,
    super.key,
  });

  final QuizQuestion question;
  final int number;
  final int total;
  final int? chosen;
  final ValueChanged<int> onChoose;
  final VoidCallback onNext;
  final bool isLast;
  final bool speaking;
  final VoidCallback? onSpeak;
  final VoidCallback? onSpeakSlowly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = AppScope.of(context).settings;
    final scripture = ScriptureStyle.of(context, settings).body;
    final answered = chosen != null;
    final right = chosen == question.answer;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Text(
          'Question $number of $total',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(question.stem, style: theme.textTheme.titleLarge),
            ),
            if (onSpeak != null)
              SpeakButtons(
                speaking: speaking,
                onSpeak: onSpeak!,
                onSpeakSlowly: onSpeakSlowly!,
              ),
          ],
        ),
        if (question.prompt.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(question.prompt, style: scripture),
          ),
        ],
        const SizedBox(height: 20),
        for (var i = 0; i < question.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              text: question.options[i],
              scripture: question.kind == QuizKind.finishVerse
                  ? scripture
                  : null,
              state: !answered
                  ? _OptionState.open
                  : i == question.answer
                  ? _OptionState.right
                  : i == chosen
                  ? _OptionState.wrong
                  : _OptionState.dimmed,
              onTap: answered ? null : () => onChoose(i),
            ),
          ),
        if (answered) ...[
          const SizedBox(height: 8),
          Text(
            right ? 'Right.' : 'Not that one.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: right ? scheme.primary : scheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(question.reference),
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(
                    question.reference.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNext,
                  icon: Icon(
                    isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded,
                  ),
                  label: Text(isLast ? 'Finish' : 'Next'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

enum _OptionState { open, right, wrong, dimmed }

class _Option extends StatelessWidget {
  const _Option({
    required this.text,
    required this.state,
    required this.onTap,
    this.scripture,
  });

  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  /// Set when the option is Scripture and should read in its face.
  final TextStyle? scripture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Color fill, Color edge, Color ink, IconData? icon) = switch (state) {
      _OptionState.open => (
        scheme.surface,
        scheme.outline,
        scheme.onSurface,
        null,
      ),
      _OptionState.right => (
        scheme.primaryContainer,
        scheme.primary,
        scheme.onPrimaryContainer,
        Icons.check_rounded,
      ),
      _OptionState.wrong => (
        scheme.errorContainer,
        scheme.error,
        scheme.onErrorContainer,
        Icons.close_rounded,
      ),
      _OptionState.dimmed => (
        scheme.surface,
        scheme.outlineVariant,
        scheme.onSurfaceVariant,
        null,
      ),
    };
    final style = (scripture ?? theme.textTheme.bodyLarge)?.copyWith(
      color: ink,
      height: 1.4,
    );
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: edge,
          width: state == _OptionState.open ? 1 : 2,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(child: Text(text, style: style)),
              if (icon != null) ...[
                const SizedBox(width: 12),
                Icon(icon, color: edge),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.right,
    required this.total,
    required this.missed,
    required this.streak,
    required this.onAgain,
  });

  final int right;
  final int total;
  final List<QuizQuestion> missed;

  /// Days in a row with learning done, this round counted.
  final int streak;
  final VoidCallback onAgain;

  String get _remark => right == total
      ? 'Every one.'
      : right >= total * 0.7
      ? 'Well done.'
      : right >= total * 0.4
      ? 'Getting there.'
      : 'Worth another go.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          '$right of $total',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _remark,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (streak > 0) ...[
          const SizedBox(height: 16),
          Center(child: StreakBadge(days: streak, large: true)),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onAgain,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Again'),
              ),
            ),
          ],
        ),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('To read again', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The ones that got away, each a tap from the passage.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final question in missed)
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_rounded),
                title: Text(question.reference.label),
                subtitle: Text(
                  question.prompt.isEmpty
                      ? question.stem
                      : '${question.stem} ${question.correct}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).pop(question.reference),
              ),
            ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'This translation has too little text to ask about.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
