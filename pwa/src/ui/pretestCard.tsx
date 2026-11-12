import { Card, Icon, TonalButton } from './m3';
import './pretestCard.css';

/**
 * Before a plan chapter is read: a nudge to guess at two of its verses
 * first. Guessing before studying makes the guessed-at material stick,
 * even when the guess is wrong.
 */
export function PretestCard({
  questions,
  guessed,
  onGuess,
}: {
  questions: number;

  /** Right out of `questions` on the guess, or null before guessing. */
  guessed: number | null;
  onGuess: () => void;
}) {
  return (
    <Card variant="tertiary" class="ow-pretest ow-pretest--before">
      <Icon name="psychology_alt" />
      <div class="ow-pretest__text">
        <div class="m3-title-small">{guessed === null ? 'Guess before you read' : `You guessed ${guessed} of ${questions}`}</div>
        <div class="m3-body-small">
          {guessed === null
            ? `${questions} of this chapter’s verses to finish. A wrong guess still helps the right one stick.`
            : 'Read on; the same questions wait at the end.'}
        </div>
      </div>
      {guessed === null && <TonalButton onClick={onGuess}>Guess</TonalButton>}
    </Card>
  );
}

/** After the chapter: the same questions again, and how the two went. */
export function PosttestCard({
  questions,
  guessed,
  answered,
  onAnswer,
}: {
  questions: number;
  guessed: number;

  /** Right out of `questions` after reading, or null until answered. */
  answered: number | null;
  onAnswer: () => void;
}) {
  return (
    <Card variant="tertiary" class="ow-pretest ow-pretest--after">
      <Icon name={answered === null ? 'quiz' : 'check_circle'} />
      <div class="ow-pretest__text m3-body-medium">
        {answered === null
          ? `You guessed ${guessed} of ${questions} before reading. Answer again now?`
          : `Before reading, ${guessed} of ${questions}; after, ${answered} of ${questions}.`}
      </div>
      {answered === null && <TonalButton onClick={onAnswer}>Answer</TonalButton>}
    </Card>
  );
}
