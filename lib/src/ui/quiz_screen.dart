import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/learn_voice.dart';
import '../data/read_aloud.dart';
import '../model/achievements.dart';
import '../model/learn_progress.dart';
import '../model/quiz.dart';
import 'learn_progress_card.dart' show AchievementIcon;
import 'memory_screen.dart'
    show AutoSpeakButton, GoodNews, SpeakButtons, StatTile, StreakBadge, XpChip;
import 'widgets/confetti.dart';
import 'widgets/scripture_text.dart';

/// A round of questions drawn from the translation being read. Pops with
/// a reference when the reader asks to open a passage, and with nothing
/// otherwise.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.kind,
    this.seed,
    this.count = questionsPerRound,
    this.questions,
    this.title,
    this.onFinished,
  });

  final QuizKind kind;

  /// Questions in the round.
  final int count;

  /// Questions to ask instead of drawing any: a chapter's own, before
  /// and after it is read.
  final List<QuizQuestion>? questions;

  /// What the screen is called, where not the kind.
  final String? title;

  /// Told the score when the round ends.
  final void Function(int right, int total)? onFinished;

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

  // The round's tally.
  int _xp = 0;
  int _combo = 0;
  int _lastXp = 0;
  int _lastBonus = 0;
  bool _perfectBonus = false;
  final List<Achievement> _won = [];
  bool _goalMetBefore = false;
  int _levelBefore = 1;

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
    _questions = widget.questions != null
        ? widget.questions!
        : bible == null
        ? const []
        : QuizMaker(
            bible,
            books: quizBooks(
              bible,
              deuterocanon: scope.settings.showDeuterocanon,
            ),
            random: widget.seed == null ? null : Random(widget.seed),
          ).make(widget.kind, count: widget.count);
    _index = 0;
    _chosen = null;
    _missed.clear();
    _right = 0;
    _xp = 0;
    _combo = 0;
    _lastXp = 0;
    _lastBonus = 0;
    _perfectBonus = false;
    _won.clear();
    _goalMetBefore = scope.reading.progress.goalMetOn(scope.reading.today);
    _levelBefore = scope.reading.progress.level;
  }

  void _choose(int option) {
    if (_chosen != null) return;
    final question = _questions[_index];
    final reading = AppScope.of(context).reading;
    final right = option == question.answer;
    if (right) {
      _right++;
      _combo++;
      _lastBonus = Xp.comboBonus(_combo);
      _lastXp = Xp.quizRight + _lastBonus;
      HapticFeedback.mediumImpact();
    } else {
      _missed.add(question);
      _combo = 0;
      _lastBonus = 0;
      _lastXp = 0;
      HapticFeedback.heavyImpact();
    }
    _xp += _lastXp;
    _won.addAll(reading.recordLearning(xp: _lastXp, right: right));
    setState(() => _chosen = option);
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
    // A round finished is a day's learning done, and a perfect one earns
    // a bonus on top.
    if (_index >= _questions.length) {
      _voice?.stop();
      final reading = AppScope.of(context).reading;
      if (_right == _questions.length) {
        _perfectBonus = true;
        _xp += Xp.perfectRound;
        _won.addAll(
          reading.recordLearning(xp: Xp.perfectRound, perfectRound: true),
        );
      } else {
        reading.recordPractice();
      }
      widget.onFinished?.call(_right, _questions.length);
      setState(() {});
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
        title: Text(widget.title ?? widget.kind.label),
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
              xp: _xp,
              perfectBonus: _perfectBonus,
              won: _won,
              goalMetNow:
                  !_goalMetBefore &&
                  AppScope.of(context).reading.progress
                      .goalMetOn(AppScope.of(context).reading.today),
              levelledUp:
                  AppScope.of(context).reading.progress.level > _levelBefore,
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
              xp: _lastXp,
              bonus: _lastBonus,
              combo: _combo,
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
    required this.xp,
    required this.bonus,
    required this.combo,
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

  /// What the answer earned, the combo bonus within it, and the run.
  final int xp;
  final int bonus;
  final int combo;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  right ? 'Right.' : 'Not that one.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: right ? scheme.primary : scheme.error,
                  ),
                ),
              ),
              if (right) XpChip(xp: xp),
            ],
          ),
          if (right && bonus > 0)
            Text(
              '$combo in a row! +$bonus XP',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
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
    required this.xp,
    required this.perfectBonus,
    required this.won,
    required this.goalMetNow,
    required this.levelledUp,
    required this.onAgain,
  });

  final int right;
  final int total;
  final List<QuizQuestion> missed;

  /// Days in a row with learning done, this round counted.
  final int streak;

  /// What the round earned, and whether the perfect bonus is in it.
  final int xp;
  final bool perfectBonus;
  final List<Achievement> won;
  final bool goalMetNow;
  final bool levelledUp;
  final VoidCallback onAgain;

  bool get _celebrate =>
      perfectBonus || goalMetNow || levelledUp || won.isNotEmpty;

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
    final scheme = theme.colorScheme;
    final progress = AppScope.of(context).reading.progress;
    return Confetti(
      play: _celebrate,
      child: ListView(
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  key: const Key('stat/xp'),
                  label: perfectBonus ? 'Earned, with bonus' : 'Earned',
                  value: '+$xp XP',
                  icon: Icons.bolt_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: 'Right',
                  value: '${(100 * right / total).round()}%',
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
            ],
          ),
          if (perfectBonus) ...[
            const SizedBox(height: 12),
            GoodNews(
              icon: Icons.workspace_premium_rounded,
              text: 'Perfect round: +${Xp.perfectRound} XP on top.',
            ),
          ],
          if (goalMetNow) ...[
            const SizedBox(height: 10),
            GoodNews(
              icon: Icons.emoji_events_rounded,
              text: 'Today’s goal met: ${progress.goal.xp} XP.',
            ),
          ],
          if (levelledUp) ...[
            const SizedBox(height: 10),
            GoodNews(
              icon: Icons.star_rounded,
              text: 'Level ${progress.level}!',
            ),
          ],
          for (final badge in won) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                AchievementIcon(achievement: badge, won: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Badge won: ${badge.title}',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        badge.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
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
      ),
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
