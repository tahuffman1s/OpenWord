import { ApiError, NetworkError } from '../../data/api';

/**
 * What went wrong, in words for the reader: the server's own message for
 * most things, and something kinder than "Failed to fetch" for the rest.
 */
export function messageOf(error: unknown): string {
  if (error instanceof NetworkError) return 'Can’t reach the server. Check your connection and try again.';
  if (error instanceof ApiError) {
    switch (error.code) {
      case 'unauthorized':
        return 'You’ve been signed out. Sign in again to carry on.';
      case 'bad_credentials':
        return 'That username or password isn’t right.';
      case 'username_taken':
        return 'That username is taken. Try another.';
      case 'email_taken':
        return 'That email is already used by another account.';
      case 'invite_required':
        return 'This server needs an invite code to join.';
      case 'already_friends':
        return 'You’re already friends.';
      case 'already_requested':
        return 'You’ve already asked. They haven’t answered yet.';
      case 'rate_limited':
        return 'Too many tries. Wait a minute, then try again.';
      case 'too_large':
        return 'That’s too big to send.';
      case 'not_found':
        return 'That isn’t there any more.';
      case 'validation':
        return tidyValidation(error.message);
      default:
        return error.status >= 500 ? 'The server had a problem. Try again in a moment.' : error.message || 'That didn’t work.';
    }
  }
  return 'Something went wrong. Try again.';
}

/** The field a `validation` error names, if it names one: `"username: 3–24 …"` → `username`. */
export function fieldOf(error: unknown): string | null {
  if (!(error instanceof ApiError)) return null;
  switch (error.code) {
    case 'username_taken':
      return 'username';
    case 'email_taken':
      return 'email';
    case 'invite_required':
      return 'inviteCode';
    case 'bad_credentials':
      return 'password';
    case 'validation': {
      const m = /^\s*"?([A-Za-z]+)"?\s*[:\s]/.exec(error.message);
      return m ? m[1] : null;
    }
    default:
      return null;
  }
}

/** A validation message without the field name it leads with, capitalised. */
function tidyValidation(message: string): string {
  const rest = message.replace(/^\s*"?[A-Za-z]+"?\s*:\s*/, '').trim();
  const text = rest.length > 0 ? rest : message.trim();
  if (text.length === 0) return 'That isn’t quite right. Check it and try again.';
  return text[0].toUpperCase() + text.substring(1);
}
