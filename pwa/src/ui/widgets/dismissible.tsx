import type { ComponentChildren } from 'preact';
import { useRef, useState } from 'preact/hooks';
import { Icon } from '../m3/icon';
import './dismissible.css';

/**
 * A row that is swiped away to the left, showing what the swipe does
 * behind it — a bin on the error colour — and gone once dragged far
 * enough or flung.
 *
 * A drag that is mostly up and down is left to the list, so the page still
 * scrolls under the finger; a tap that never became a drag is the row's own.
 */
export function Dismissible({ children, onDismissed, label = 'Remove' }: { children: ComponentChildren; onDismissed: () => void; label?: string }) {
  const rowRef = useRef<HTMLDivElement>(null);
  const [offset, setOffset] = useState(0);
  const [settling, setSettling] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const drag = useRef<{ id: number; x: number; y: number; at: number; active: boolean } | null>(null);
  const suppressClick = useRef(false);

  const onPointerDown = (event: PointerEvent): void => {
    if (leaving || (event.pointerType === 'mouse' && event.button !== 0)) return;
    drag.current = { id: event.pointerId, x: event.clientX, y: event.clientY, at: event.timeStamp, active: false };
    suppressClick.current = false;
  };

  const onPointerMove = (event: PointerEvent): void => {
    const state = drag.current;
    if (state === null || state.id !== event.pointerId) return;
    const dx = event.clientX - state.x;
    const dy = event.clientY - state.y;
    if (!state.active) {
      if (Math.abs(dx) < 10 || Math.abs(dx) < Math.abs(dy) * 1.5) {
        // Going up or down: the list's to scroll, not ours to drag.
        if (Math.abs(dy) > 12) drag.current = null;
        return;
      }
      state.active = true;
      suppressClick.current = true;
      setSettling(false);
      try {
        rowRef.current?.setPointerCapture(event.pointerId);
      } catch {
        // No capture: the drag still follows while the pointer is over the row.
      }
    }
    setOffset(Math.min(0, dx));
  };

  const finish = (event: PointerEvent): void => {
    const state = drag.current;
    drag.current = null;
    if (state === null || !state.active) return;
    const width = rowRef.current?.offsetWidth ?? 1;
    const dx = Math.min(0, event.clientX - state.x);
    const elapsed = Math.max(event.timeStamp - state.at, 1);
    const flung = -dx / elapsed > 0.7 && dx < -40;
    setSettling(true);
    if (event.type !== 'pointercancel' && (dx < -width * 0.4 || flung)) {
      setLeaving(true);
      setOffset(-width);
      setTimeout(onDismissed, 200);
    } else {
      setOffset(0);
    }
  };

  return (
    <div class={`ow-dismissible${leaving ? ' ow-dismissible--leaving' : ''}`}>
      <div class="ow-dismissible__background" aria-hidden="true" style={offset === 0 ? 'visibility:hidden' : undefined}>
        <Icon name="delete" label={label} />
      </div>
      <div
        ref={rowRef}
        class={`ow-dismissible__row${settling ? ' ow-dismissible__row--settling' : ''}`}
        style={`transform:translateX(${offset}px)`}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={finish}
        onPointerCancel={finish}
        onClickCapture={(event) => {
          if (!suppressClick.current) return;
          suppressClick.current = false;
          event.stopPropagation();
          event.preventDefault();
        }}
      >
        {children}
      </div>
    </div>
  );
}
