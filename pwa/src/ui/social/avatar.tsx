import { useState } from 'preact/hooks';
import { avatarUrl, type PublicUser } from '../../data/api';
import './social.css';

export type AvatarUser = Pick<PublicUser, 'id' | 'username' | 'displayName' | 'avatarVersion' | 'avatarUrl'>;

/** Up to two letters to stand for someone with no photo. */
export function initialsOf(user: Pick<PublicUser, 'username' | 'displayName'> | null | undefined): string {
  const name = (user?.displayName || user?.username || '').trim();
  if (name.length === 0) return '?';
  const words = name.split(/[\s_.-]+/u).filter((w) => w.length > 0);
  const first = [...(words[0] ?? name)][0] ?? '?';
  const second = words.length > 1 ? ([...words[words.length - 1]][0] ?? '') : '';
  return (first + second).toUpperCase();
}

/**
 * Someone's photo in a circle, or their initials on a tinted circle where
 * they have none (or it will not load). The photo's URL carries its
 * version, so a new one shows at once and an old one is cached for good.
 */
export function Avatar({ user, size = 40, class: cls }: { user: AvatarUser | null | undefined; size?: number; class?: string }) {
  const url = avatarUrl(user);
  const [failed, setFailed] = useState<string | null>(null);
  const style = `width:${size}px;height:${size}px;font-size:${Math.round(size * 0.4)}px`;
  return (
    <span class={`ow-avatar${cls ? ` ${cls}` : ''}`} style={style} aria-hidden="true">
      {url && failed !== url ? (
        <img src={url} alt="" width={size} height={size} loading="lazy" decoding="async" onError={() => setFailed(url)} />
      ) : (
        initialsOf(user)
      )}
    </span>
  );
}
