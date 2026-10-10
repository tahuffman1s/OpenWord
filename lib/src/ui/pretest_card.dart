import 'package:flutter/material.dart';

/// Before a plan chapter is read: a nudge to guess at two of its verses
/// first. Guessing before studying makes the guessed-at material stick,
/// even when the guess is wrong.
class PretestCard extends StatelessWidget {
  const PretestCard({
    super.key,
    required this.questions,
    required this.guessed,
    required this.onGuess,
  });

  final int questions;

  /// Right out of [questions] on the guess, or null before guessing.
  final int? guessed;
  final VoidCallback onGuess;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.filled(
      margin: const EdgeInsets.only(bottom: 20),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              Icons.psychology_alt_rounded,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guessed == null
                        ? 'Guess before you read'
                        : 'You guessed $guessed of $questions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    guessed == null
                        ? '$questions of this chapter’s verses to finish. A '
                              'wrong guess still helps the right one stick.'
                        : 'Read on; the same questions wait at the end.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            if (guessed == null) ...[
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onGuess,
                child: const Text('Guess'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// After the chapter: the same questions again, and how the two went.
class PosttestCard extends StatelessWidget {
  const PosttestCard({
    super.key,
    required this.questions,
    required this.guessed,
    required this.answered,
    required this.onAnswer,
  });

  final int questions;
  final int guessed;

  /// Right out of [questions] after reading, or null until answered.
  final int? answered;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.filled(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              answered == null
                  ? Icons.quiz_rounded
                  : Icons.check_circle_rounded,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                answered == null
                    ? 'You guessed $guessed of $questions before reading. '
                          'Answer again now?'
                    : 'Before reading, $guessed of $questions; after, '
                          '$answered of $questions.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            if (answered == null) ...[
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onAnswer,
                child: const Text('Answer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
