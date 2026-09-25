import { useRef } from 'react';

/* A two-or-more way segmented control, as an accessible radiogroup.
 *
 * Extracted rather than inlined because the markup is the easy part and the
 * keyboard behaviour is not: a radiogroup is a single tab stop whose options
 * are reached with the arrow keys, which means roving tabindex, focus that
 * follows selection, and Home/End. Inlined among form fields that is exactly
 * the code that gets simplified away by the next person to touch the file.
 */

export interface SegmentOption<T extends string> {
  id: T;
  label: string;
}

interface Props<T extends string> {
  options: SegmentOption<T>[];
  value: T;
  onChange: (next: T) => void;
  /** Names the group for screen readers - there is no visible label. */
  label: string;
}

export default function SegmentedToggle<T extends string>({
  options, value, onChange, label,
}: Props<T>) {
  const groupRef = useRef<HTMLDivElement>(null);
  const index = Math.max(0, options.findIndex((o) => o.id === value));

  const onKeyDown = (e: React.KeyboardEvent) => {
    const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'];
    if (!keys.includes(e.key)) return;
    e.preventDefault();

    // Wraps, per the radiogroup pattern - arrowing off the end comes back
    // round rather than stopping dead.
    const back = e.key === 'ArrowLeft' || e.key === 'ArrowUp';
    const next =
      e.key === 'Home' ? options[0]
      : e.key === 'End' ? options[options.length - 1]
      : options[(index + (back ? -1 : 1) + options.length) % options.length];

    onChange(next.id);

    /* Focus follows selection, and the newly selected option is the only one
     * with tabIndex 0 after this render. Read off a ref rather than the
     * event: React resets currentTarget to null once the handler returns, so
     * reaching for it across the frame boundary finds nothing and focus
     * silently stays behind while the selection moves. */
    requestAnimationFrame(() => {
      groupRef.current?.querySelector<HTMLElement>('[tabindex="0"]')?.focus();
    });
  };

  return (
    <div
      className="lp-toggle"
      role="radiogroup"
      aria-label={label}
      ref={groupRef}
      onKeyDown={onKeyDown}
      style={{ gridTemplateColumns: `repeat(${options.length}, 1fr)` }}
    >
      <span
        className="lp-toggle-thumb"
        aria-hidden="true"
        style={{
          width: `calc(${100 / options.length}% - ${8 / options.length}px)`,
          transform: `translateX(${index * 100}%)`,
        }}
      />
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          role="radio"
          aria-checked={o.id === value}
          tabIndex={o.id === value ? 0 : -1}
          className={`lp-toggle-opt${o.id === value ? ' is-on' : ''}`}
          onClick={() => onChange(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
