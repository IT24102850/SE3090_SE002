import { useEffect, useRef, useState, type RefObject } from 'react';

/**
 * How far down the whole document the visitor is, 0..100.
 *
 * Drives the persistent readout in the top rail. Rounded to whole percent
 * before publishing, so this re-renders at most a hundred times over the
 * entire page rather than once a frame.
 */
export function usePageProgress() {
  const [percent, setPercent] = useState(0);

  useEffect(() => {
    let raf = 0;
    let last = -1;

    const measure = () => {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const next = max > 0 ? Math.round((window.scrollY / max) * 100) : 0;
      if (next !== last) {
        last = next;
        setPercent(next);
      }
      raf = requestAnimationFrame(measure);
    };

    raf = requestAnimationFrame(measure);
    return () => cancelAnimationFrame(raf);
  }, []);

  return percent;
}

/**
 * Counts from zero to `target` once the element is on screen, then stops.
 *
 * Deliberately one-shot: a number that re-counts every time it scrolls back
 * into view reads as a gimmick rather than a fact. Under reduced motion it
 * simply starts at the final value - the number is the content, the count is
 * decoration.
 */
export function useCountUp(ref: RefObject<HTMLElement>, target: number, durationMs = 1400) {
  const reduced =
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const [value, setValue] = useState(reduced ? target : 0);
  const done = useRef(reduced);

  useEffect(() => {
    const el = ref.current;
    if (!el || done.current) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries[0].isIntersecting || done.current) return;
        done.current = true;
        observer.disconnect();

        const start = performance.now();
        const tick = (now: number) => {
          const t = Math.min((now - start) / durationMs, 1);
          // Ease-out quart: most of the distance is covered early, so the
          // number settles on its final value rather than crawling to it.
          setValue(Math.round(target * (1 - Math.pow(1 - t, 4))));
          if (t < 1) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      },
      { threshold: 0.4 },
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [ref, target, durationMs]);

  return value;
}
