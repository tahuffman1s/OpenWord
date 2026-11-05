/**
 * Handing a file to the reader, on the web.
 *
 * A page has no filesystem to write into, so "save a copy" means one of
 * three things, tried in the order a reader would want them: a save
 * dialog where the browser has one (`showSaveFilePicker`, Chromium), the
 * share sheet where files can be shared (phones, mostly), and failing
 * both an ordinary download through an anchor. Pure browser glue, kept
 * small; nothing here is tested under Node beyond the refusal.
 */

/** A writable file handle, as the File System Access API gives one. */
interface SaveFileHandle {
  createWritable(): Promise<{ write(data: Blob): Promise<void>; close(): Promise<void> }>;
}

interface SavePickerHost {
  showSaveFilePicker?: (options: {
    suggestedName?: string;
    types?: { description?: string; accept: Record<string, string[]> }[];
  }) => Promise<SaveFileHandle>;
}

/**
 * Saves `bytes` as a file called `name`. Resolves once the file has been
 * handed over — or once the reader has cancelled, which is not an error.
 * Throws where there is no browser to hand it to.
 */
export async function saveBytes(name: string, bytes: Uint8Array, mime = 'application/octet-stream'): Promise<void> {
  // A copy, so a view into a bigger buffer — or a shared one — is not
  // what the browser is given.
  const blob = new Blob([bytes.slice()], { type: mime });

  const host = globalThis as unknown as SavePickerHost;
  if (typeof host.showSaveFilePicker === 'function') {
    try {
      const extension = name.includes('.') ? name.substring(name.lastIndexOf('.')) : '';
      const handle = await host.showSaveFilePicker({
        suggestedName: name,
        types: extension.length > 1 ? [{ accept: { [mime]: [extension] } }] : undefined,
      });
      const writable = await handle.createWritable();
      await writable.write(blob);
      await writable.close();
      return;
    } catch (error) {
      // The reader closed the dialog: nothing to save, nothing to fall
      // back to. Anything else — a browser that offers the picker and
      // then refuses — falls through to the next way.
      if ((error as { name?: string }).name === 'AbortError') return;
    }
  }

  if (typeof navigator !== 'undefined' && typeof navigator.share === 'function' && typeof File !== 'undefined') {
    const file = new File([blob], name, { type: mime });
    const data: ShareData = { files: [file] };
    if (typeof navigator.canShare === 'function' && navigator.canShare(data)) {
      try {
        await navigator.share(data);
        return;
      } catch (error) {
        if ((error as { name?: string }).name === 'AbortError') return;
        // Fall through to a download.
      }
    }
  }

  if (typeof document === 'undefined' || typeof URL.createObjectURL !== 'function') {
    throw new Error('there is nowhere here to save a file');
  }

  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = name;
  anchor.rel = 'noopener';
  anchor.style.display = 'none';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // The browser reads the URL when the click lands, not before this
  // returns, so it is kept alive a while rather than revoked at once.
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
