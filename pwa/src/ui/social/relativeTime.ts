/**
 * When something happened, the way a person would say it: "just now",
 * "5 min ago", "2 h ago", "yesterday", and after that the date.
 */
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function shortDate(date: Date, now: Date): string {
  const base = `${date.getDate()} ${months[date.getMonth()]}`;
  return date.getFullYear() === now.getFullYear() ? base : `${base} ${date.getFullYear()}`;
}

/** Whole calendar days from `date` to `now`, by the reader's own calendar. */
function calendarDaysAgo(date: Date, now: Date): number {
  const a = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
  const b = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((b - a) / 86_400_000);
}

export function relativeTime(when: string | Date | null | undefined, now: Date = new Date()): string {
  if (when == null) return '';
  const date = typeof when === 'string' ? new Date(when) : when;
  if (Number.isNaN(date.getTime())) return '';
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000);
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  const daysAgo = calendarDaysAgo(date, now);
  if (daysAgo <= 0 || (daysAgo === 1 && minutes < 6 * 60)) return `${Math.floor(minutes / 60)} h ago`;
  if (daysAgo === 1) return 'yesterday';
  return shortDate(date, now);
}

/** A calendar day (`YYYY-MM-DD`) as "today", "yesterday" or the date. */
export function relativeDay(day: string | null | undefined, now: Date = new Date()): string {
  if (!day) return '';
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
  if (!m) return '';
  const date = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  const daysAgo = calendarDaysAgo(date, now);
  if (daysAgo <= 0) return 'today';
  if (daysAgo === 1) return 'yesterday';
  if (daysAgo < 7) return `${daysAgo} days ago`;
  return shortDate(date, now);
}
