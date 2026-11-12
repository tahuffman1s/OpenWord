import type { ComponentChildren, RefObject } from 'preact';
import { useCallback, useState } from 'preact/hooks';

export interface ScreenProps {
  /** Built with the current scrolled state, so an AppBar can tint itself. */
  appBar?: ComponentChildren | ((scrolled: boolean) => ComponentChildren);
  children?: ComponentChildren;
  /** Something fixed under the body: a navigation bar, a playback bar. */
  bottom?: ComponentChildren;
  /** A FAB, placed bottom-end over the body. */
  fab?: ComponentChildren;
  /** Pads the body 16px at the sides. */
  padded?: boolean;
  bodyRef?: RefObject<HTMLDivElement>;
  onScroll?: (top: number) => void;
  class?: string;
  bodyClass?: string;
  style?: string;
}

/** Flutter's Scaffold: an app bar, a scrolling body, something along the bottom, a FAB. */
export function Screen({ appBar, children, bottom, fab, padded, bodyRef, onScroll, class: cls, bodyClass, style }: ScreenProps) {
  const [scrolled, setScrolled] = useState(false);
  const handleScroll = useCallback(
    (e: Event) => {
      const top = (e.currentTarget as HTMLDivElement).scrollTop;
      setScrolled(top > 0);
      onScroll?.(top);
    },
    [onScroll],
  );
  return (
    <div class={`m3-screen${cls ? ` ${cls}` : ''}`} style={style}>
      {typeof appBar === 'function' ? appBar(scrolled) : appBar}
      <div class="m3-screen__main">
        <div ref={bodyRef} class={`m3-screen__body${padded ? ' m3-screen__body--padded' : ''}${bodyClass ? ` ${bodyClass}` : ''}`} onScroll={handleScroll}>
          {children}
        </div>
        {fab && <div class="m3-screen__fab" style={bottom ? undefined : 'bottom:calc(16px + var(--ow-safe-bottom))'}>{fab}</div>}
      </div>
      {bottom}
    </div>
  );
}
