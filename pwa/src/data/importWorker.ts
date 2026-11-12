/**
 * The import, off the main thread.
 *
 * A module Web Worker that answers one request — convert this file, or
 * sweep this `.bib` — and posts the result back as plain data. The Flutter
 * app does the same with `compute` on an isolate; the shelf starts one of
 * these for any file big enough to be worth it, and does the work inline
 * for anything smaller, or anywhere there are no workers.
 *
 * Nothing here touches the DOM: `importFile` and `tidyBib` are pure, and
 * the XML comes through `htmlparser2`, which needs no `DOMParser`.
 */
import { tidyBib } from './importTidy';
import { importFile, type ImportWorkerReply, type ImportWorkerRequest } from './shelf';

interface WorkerScope {
  onmessage: ((event: MessageEvent<ImportWorkerRequest>) => void) | null;
  postMessage(message: ImportWorkerReply, transfer?: Transferable[]): void;
}

/** Answers one request. Exported so a test can drive it without a worker. */
export function answer(request: ImportWorkerRequest): ImportWorkerReply {
  try {
    if (request.kind === 'import') {
      const imported = importFile(request.bytes, request.fileName);
      return { kind: 'import', bytes: imported.bytes, warnings: [...imported.warnings], failure: imported.failure };
    }
    const tidied = tidyBib(request.bytes);
    return { kind: 'tidy', bytes: tidied.bytes, removed: [...tidied.removed], failure: tidied.failure };
  } catch (error) {
    return { kind: 'error', message: error instanceof Error ? error.message : String(error) };
  }
}

// Only inside a worker: a test imports `answer` under Node, where there is
// no `self` to listen on.
if (typeof self !== 'undefined' && typeof (self as unknown as WorkerScope).postMessage === 'function') {
  const scope = self as unknown as WorkerScope;
  scope.onmessage = (event: MessageEvent<ImportWorkerRequest>) => {
    const reply = answer(event.data);
    // The file is handed over rather than copied: the worker is done with it.
    const transfer: Transferable[] =
      reply.kind !== 'error' && reply.bytes !== null ? [reply.bytes.buffer as ArrayBuffer] : [];
    scope.postMessage(reply, transfer);
  };
}
