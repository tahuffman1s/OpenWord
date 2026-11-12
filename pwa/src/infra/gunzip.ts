import { gunzipSync } from 'fflate';

/**
 * Unpacks gzip where it is gzip, and hands back anything else untouched.
 *
 * The bundled layers are `.gz` files the app unpacks itself. Some servers
 * — Vite's own, for one — see the extension, send `Content-Encoding: gzip`
 * and so have the browser unpack them on the way in; what arrives is then
 * already plain. Checking the two magic bytes reads either.
 */
export function gunzipIfNeeded(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 2 || bytes[0] !== 0x1f || bytes[1] !== 0x8b) return bytes;
  return gunzipSync(bytes);
}
