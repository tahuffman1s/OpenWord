import type { ComponentChildren } from 'preact';

/** The drag handle at the top of a bottom sheet. */
export function SheetHandle() {
  return <div class="m3-sheet__handle" aria-hidden="true" />;
}

export function SheetTitle({ children, class: cls }: { children: ComponentChildren; class?: string }) {
  return <div class={`m3-sheet__title${cls ? ` ${cls}` : ''}`}>{children}</div>;
}

/** The scrolling body of a sheet. */
export function SheetBody({ children, class: cls, padded }: { children: ComponentChildren; class?: string; padded?: boolean }) {
  return <div class={`m3-sheet__body${cls ? ` ${cls}` : ''}`} style={padded ? 'padding:0 24px 24px' : undefined}>{children}</div>;
}

/** A whole sheet: handle, optional title, scrolling body. */
export function Sheet({ title, children, handle = true, padded, class: cls, header }: { title?: ComponentChildren; children: ComponentChildren; handle?: boolean; padded?: boolean; class?: string; header?: ComponentChildren }) {
  return (
    <>
      {handle && <SheetHandle />}
      {title && <SheetTitle>{title}</SheetTitle>}
      {header}
      <SheetBody padded={padded} class={cls}>
        {children}
      </SheetBody>
    </>
  );
}
