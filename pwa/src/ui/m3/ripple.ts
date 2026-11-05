/**
 * The press ripple: a circle that grows from the pointer and fades, on any
 * element with the `m3-interactive` class. Attached once at the document,
 * so components need only the class.
 */
let installed = false;

export function installRipples(root: Document | HTMLElement = document): void {
  if (installed) return;
  installed = true;
  root.addEventListener(
    'pointerdown',
    (event) => {
      const e = event as PointerEvent;
      const target = (e.target as HTMLElement | null)?.closest<HTMLElement>('.m3-interactive');
      if (!target || (target as HTMLButtonElement).disabled || target.getAttribute('aria-disabled') === 'true') return;
      if (e.button !== 0) return;
      const rect = target.getBoundingClientRect();
      const size = Math.max(rect.width, rect.height);
      const ripple = document.createElement('span');
      ripple.className = 'm3-ripple';
      ripple.style.width = ripple.style.height = `${size}px`;
      ripple.style.left = `${e.clientX - rect.left - size / 2}px`;
      ripple.style.top = `${e.clientY - rect.top - size / 2}px`;
      target.appendChild(ripple);
      ripple.addEventListener('animationend', () => ripple.remove(), { once: true });
      setTimeout(() => ripple.remove(), 600);
    },
    { passive: true },
  );
}
