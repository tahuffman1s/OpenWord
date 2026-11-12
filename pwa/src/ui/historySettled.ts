/**
 * Resolves once the back-step that closed a sheet or a screen has been
 * seen, or soon anyway, so that whatever is opened or closed next stacks
 * cleanly on the browser's history.
 */
export function historySettled(): Promise<void> {
  return new Promise((resolve) => {
    let done = false;
    const finish = (): void => {
      if (done) return;
      done = true;
      removeEventListener('popstate', finish);
      resolve();
    };
    addEventListener('popstate', finish);
    setTimeout(finish, 150);
  });
}
