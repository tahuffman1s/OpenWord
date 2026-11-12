/** A linear progress bar; without `value` it is indeterminate. */
export function LinearProgress({ value, class: cls, height }: { value?: number; class?: string; height?: number }) {
  const indeterminate = value === undefined;
  return (
    <div
      class={`m3-linear-progress${indeterminate ? ' m3-linear-progress--indeterminate' : ''}${cls ? ` ${cls}` : ''}`}
      style={height ? `height:${height}px` : undefined}
      role="progressbar"
      aria-valuenow={indeterminate ? undefined : Math.round(value * 100)}
    >
      <div class="m3-linear-progress__bar" style={indeterminate ? undefined : `width:${Math.max(0, Math.min(1, value)) * 100}%`} />
    </div>
  );
}

/** A circular progress indicator; without `value` it spins. */
export function CircularProgress({ value, size = 40, stroke = 4 }: { value?: number; size?: number; stroke?: number }) {
  const r = 18;
  const c = 2 * Math.PI * r;
  const determinate = value !== undefined;
  return (
    <svg class={`m3-circular-progress${determinate ? ' m3-circular-progress--determinate' : ''}`} viewBox="0 0 48 48" width={size} height={size} role="progressbar">
      {determinate && <circle class="m3-circular-progress__track" cx="24" cy="24" r={r} style={`stroke-width:${stroke}`} />}
      <circle
        cx="24"
        cy="24"
        r={r}
        style={determinate ? `stroke-width:${stroke};stroke-dasharray:${c};stroke-dashoffset:${c * (1 - Math.max(0, Math.min(1, value)))};transform:rotate(-90deg);transform-origin:center` : `stroke-width:${stroke}`}
      />
    </svg>
  );
}
