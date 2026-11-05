import { appUpdates } from './serviceWorker';

/**
 * Notifications: permission, push subscriptions through the service worker,
 * and a notification shown from the page.
 *
 * The one thing a web app cannot do is what the Flutter app's reminder
 * does — fire a notification at a chosen time with nothing running. A page
 * can only schedule while it is open, and a service worker runs only in
 * answer to an event (a fetch, a push, a click). So a reminder before a
 * streak breaks has to come as a push from the server, which knows the
 * reader's reminder time (see `subscribeToPush`), or, where push is not
 * to be had, as an in-app banner the next time the app is opened — which
 * `reminderDueNow` decides.
 *
 * On iOS, push and `Notification` exist only for a web app added to the
 * home screen, on iOS 16.4 or later; in a Safari tab `Notification` is
 * undefined and `permission` answers `'unsupported'`.
 */
export type NotificationPermissionState = NotificationPermission | 'unsupported';

/** The current permission, or `'unsupported'` where notifications do not exist. */
export function notificationPermission(): NotificationPermissionState {
  if (typeof Notification === 'undefined') return 'unsupported';
  return Notification.permission;
}

/** Whether this browser can take a push subscription at all. */
export function pushSupported(): boolean {
  return typeof navigator !== 'undefined' && 'serviceWorker' in navigator && typeof PushManager !== 'undefined' && typeof Notification !== 'undefined';
}

/**
 * Asks for permission, from a tap: browsers ignore the request unless it
 * comes from a user gesture. Answers the resulting state.
 */
export async function requestNotificationPermission(): Promise<NotificationPermissionState> {
  if (typeof Notification === 'undefined') return 'unsupported';
  if (Notification.permission !== 'default') return Notification.permission;
  try {
    // Safari before 16 took a callback rather than answering a promise.
    const result = await new Promise<NotificationPermission>((resolve) => {
      const maybe = Notification.requestPermission(resolve);
      if (maybe && typeof (maybe as Promise<NotificationPermission>).then === 'function') {
        void (maybe as Promise<NotificationPermission>).then(resolve);
      }
    });
    return result;
  } catch (error) {
    console.warn('OpenWord: notification permission request failed', error);
    return Notification.permission;
  }
}

/** A VAPID public key, base64url as servers hand it out, as the bytes `subscribe` wants. */
export function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/**
 * Subscribes this browser to push, asking for permission first if it has
 * not been given, and answers the subscription as JSON to send to the
 * server. Null when the browser cannot (no worker, no push, permission
 * refused). An existing subscription is answered as is.
 */
export async function subscribeToPush(vapidPublicKey: string): Promise<PushSubscriptionJSON | null> {
  if (!pushSupported()) return null;
  const permission = await requestNotificationPermission();
  if (permission !== 'granted') return null;
  const registration = await appUpdates.whenRegistered();
  if (!registration) return null;
  try {
    const existing = await registration.pushManager.getSubscription();
    if (existing) return existing.toJSON();
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidPublicKey) as BufferSource,
    });
    return subscription.toJSON();
  } catch (error) {
    console.warn('OpenWord: push subscription failed', error);
    return null;
  }
}

/** The current subscription's JSON, if this browser has one. */
export async function currentPushSubscription(): Promise<PushSubscriptionJSON | null> {
  if (!pushSupported()) return null;
  const registration = await appUpdates.whenRegistered();
  if (!registration) return null;
  try {
    const existing = await registration.pushManager.getSubscription();
    return existing ? existing.toJSON() : null;
  } catch {
    return null;
  }
}

/** Ends the push subscription. Answers whether there was one to end. */
export async function unsubscribeFromPush(): Promise<boolean> {
  if (!pushSupported()) return false;
  const registration = await appUpdates.whenRegistered();
  if (!registration) return false;
  try {
    const existing = await registration.pushManager.getSubscription();
    if (!existing) return false;
    return await existing.unsubscribe();
  } catch (error) {
    console.warn('OpenWord: push unsubscribe failed', error);
    return false;
  }
}

/**
 * Shows a notification now, through the service worker's registration
 * (which is the only way on Android Chrome, where `new Notification` throws).
 * Falls back to `new Notification` where there is no worker. Answers
 * whether one was shown.
 */
export async function showLocalNotification(title: string, options: NotificationOptions & { url?: string } = {}): Promise<boolean> {
  if (notificationPermission() !== 'granted') return false;
  const { url, ...rest } = options;
  const merged: NotificationOptions = {
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    ...rest,
    data: { url: url ?? '/', ...(typeof rest.data === 'object' && rest.data !== null ? (rest.data as Record<string, unknown>) : {}) },
  };
  const registration = await appUpdates.whenRegistered();
  try {
    if (registration) {
      await registration.showNotification(title, merged);
      return true;
    }
    new Notification(title, merged);
    return true;
  } catch (error) {
    console.warn('OpenWord: could not show a notification', error);
    return false;
  }
}

/**
 * A reminder time as the settings keep it: `"HH:MM"` on a 24-hour clock,
 * or the hour and minute apart.
 */
export type ReminderTime = string | { hour: number; minute: number };

export function parseReminderTime(time: ReminderTime): { hour: number; minute: number } | null {
  if (typeof time !== 'string') {
    return Number.isInteger(time.hour) && Number.isInteger(time.minute) ? time : null;
  }
  const m = /^(\d{1,2}):(\d{2})$/.exec(time.trim());
  if (!m) return null;
  const hour = Number(m[1]);
  const minute = Number(m[2]);
  if (hour > 23 || minute > 59) return null;
  return { hour, minute };
}

/**
 * Whether the day's reminder is due: it is past the reminder time today,
 * and today's learning has not been done (`lastDone` is before today,
 * local time). For the in-app banner where no push can reach the reader.
 *
 *   if (reminderDueNow(settings.reminderTime, streak.lastDoneAt)) showBanner();
 */
export function reminderDueNow(settingsTime: ReminderTime | null | undefined, lastDone: Date | number | null | undefined, now: Date = new Date()): boolean {
  if (settingsTime == null) return false;
  const at = parseReminderTime(settingsTime);
  if (!at) return false;
  const due = new Date(now.getFullYear(), now.getMonth(), now.getDate(), at.hour, at.minute, 0, 0);
  if (now.getTime() < due.getTime()) return false;
  if (lastDone == null) return true;
  const last = lastDone instanceof Date ? lastDone : new Date(lastDone);
  if (Number.isNaN(last.getTime())) return true;
  const sameDay = last.getFullYear() === now.getFullYear() && last.getMonth() === now.getMonth() && last.getDate() === now.getDate();
  return !sameDay;
}
