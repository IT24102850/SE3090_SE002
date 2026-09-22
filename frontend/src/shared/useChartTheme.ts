import { useEffect, useState } from 'react';

/* Chart chrome colours, resolved from the theme tokens.
 *
 * Recharts writes fill and stroke as SVG attributes, and attributes are not
 * CSS - `fill="var(--chart-tick)"` renders nothing. So the values have to be
 * real strings, read from the same custom properties the rest of the console
 * uses, and read again whenever data-theme changes on <html>. Before this the
 * chart colours were literals tuned for the dark canvas, which is why the
 * light theme had white gridlines on white panels.
 */

export interface ChartTheme {
  tick: string;
  grid: string;
  tooltip: { background: string; border: string; borderRadius: number; color: string };
  tooltipItem: { color: string };
  /** Series colours, named by role rather than hue - the palette has been
   *  re-pointed once already and hue names go stale the moment it is. */
  series: { blue: string; teal: string; green: string; amber: string; red: string; slate: string; cyan: string };
}

function read(): ChartTheme {
  const css = getComputedStyle(document.documentElement);
  const v = (name: string, fallback: string) => css.getPropertyValue(name).trim() || fallback;
  return {
    tick: v('--chart-tick', '#63728C'),
    grid: v('--chart-grid', 'rgba(10,15,29,0.07)'),
    tooltip: {
      background: v('--chart-tooltip-bg', '#FFFFFF'),
      border: `1px solid ${v('--chart-tooltip-border', '#DCE5EF')}`,
      borderRadius: 10,
      color: v('--chart-tooltip-fg', '#0A0F1D'),
    },
    tooltipItem: { color: v('--chart-tooltip-fg', '#0A0F1D') },
    series: {
      blue: v('--color-primary', '#2563EB'),
      teal: v('--color-accent-high', '#0E7490'),
      green: v('--color-good', '#15803D'),
      amber: v('--color-warning', '#B45309'),
      red: v('--color-critical', '#B91C1C'),
      slate: v('--color-neutral', '#63728C'),
      cyan: v('--color-accent-cyan', '#0E7490'),
    },
  };
}

export function useChartTheme(): ChartTheme {
  const [theme, setTheme] = useState<ChartTheme>(read);

  useEffect(() => {
    // The theme selector writes data-theme on <html>; that attribute change
    // is the one signal that the resolved token values may have moved.
    const observer = new MutationObserver(() => setTheme(read()));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    // "System" also moves when the OS does, with no attribute change.
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const onMedia = () => setTheme(read());
    media.addEventListener('change', onMedia);
    return () => {
      observer.disconnect();
      media.removeEventListener('change', onMedia);
    };
  }, []);

  return theme;
}
