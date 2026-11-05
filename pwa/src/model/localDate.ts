import { parseIntStrict } from './bible';

/** Milliseconds in a day, for the arithmetic on dates kept this way. */
export const millisPerDay = 86_400_000;

/**
 * Calendar dates, kept as midnight UTC of the local day.
 *
 * A date held that way is a whole number of days from any other, so the
 * days between two of them are never 23 or 25 hours across a change of
 * clocks, and one written down reads back as the same day anywhere.
 */
export const LocalDate = {
  /** Midnight UTC of `moment`'s local calendar date. */
  only(moment: Date): Date {
    return new Date(Date.UTC(moment.getFullYear(), moment.getMonth(), moment.getDate()));
  },

  format(date: Date): string {
    return (
      `${String(date.getUTCFullYear()).padStart(4, '0')}-` +
      `${String(date.getUTCMonth() + 1).padStart(2, '0')}-` +
      `${String(date.getUTCDate()).padStart(2, '0')}`
    );
  },

  parse(raw: unknown): Date | null {
    if (typeof raw !== 'string') return null;
    const parts = raw.split('-');
    if (parts.length !== 3) return null;
    const numbers = parts.map(parseIntStrict);
    if (numbers.some((n) => n === null)) return null;
    return new Date(Date.UTC(numbers[0]!, numbers[1]! - 1, numbers[2]!));
  },

  /**
   * Dart's `later.difference(earlier).inDays`: whole days, truncated
   * towards zero, so negative when `later` is the earlier of the two.
   */
  daysBetween(later: Date, earlier: Date): number {
    return Math.trunc((later.getTime() - earlier.getTime()) / millisPerDay);
  },

  /** `date.add(Duration(days: days))`; negative days subtract. */
  addDays(date: Date, days: number): Date {
    return new Date(date.getTime() + days * millisPerDay);
  },

  /** Whether two dates are the same instant; null equals only null. */
  same(a: Date | null | undefined, b: Date | null | undefined): boolean {
    return a == null || b == null ? a == b : a.getTime() === b.getTime();
  },
};
