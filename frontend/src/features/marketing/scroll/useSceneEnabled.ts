import { useEffect, useState } from 'react';

/* Whether this visitor should get the WebGL scene at all.
 *
 * This is a mounting decision, not a styling one, and that distinction is the
 * whole reason the hook exists. Hiding the canvas with `display: none` looks
 * equivalent and is not: the component still mounts, still acquires a WebGL
 * context, still compiles both shader programs and still uploads every
 * buffer. Nothing is ever drawn - a display:none canvas has a zero-sized box,
 * so the visibility observer never fires - but the allocation happens anyway,
 * on precisely the machines that can least afford it. CSS also cannot express
 * two of the four conditions below at all.
 *
 * Starts false and resolves in an effect. That costs one extra render and
 * buys two things: no hydration mismatch, and a first paint that never
 * includes a canvas, so the hero's text is the largest contentful paint
 * rather than competing with GL setup for the main thread.
 */

/** Below these the scene is not worth what it costs to run. */
const MIN_CORES = 4;
const MIN_MEMORY_GB = 4;

function hasHeadroom() {
  const nav = navigator as Navigator & { deviceMemory?: number };

  // Both are absent on Firefox and Safari. Treating "unknown" as "too weak"
  // would switch the scene off for most non-Chromium visitors on hardware
  // that runs it perfectly well, so unknown passes and only a reported
  // shortfall fails.
  if (typeof nav.hardwareConcurrency === 'number' && nav.hardwareConcurrency < MIN_CORES) return false;
  if (typeof nav.deviceMemory === 'number' && nav.deviceMemory < MIN_MEMORY_GB) return false;
  return true;
}

export function useSceneEnabled() {
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    // 1000px matches the stylesheet's layout breakpoint, where the hero stops
    // being two columns and the object no longer has anywhere to sit.
    const queries = [
      window.matchMedia('(prefers-reduced-motion: reduce)'),
      window.matchMedia('(max-width: 1000px)'),
    ];

    // Both conditions are negative, so the scene runs only when neither holds.
    const evaluate = () => setEnabled(!queries.some((q) => q.matches) && hasHeadroom());

    evaluate();
    // Someone who turns motion off, or drags a window narrow, gets the change
    // applied without a reload - and unmounting tears the context down through
    // the scene's own cleanup, which is where it should live.
    queries.forEach((q) => q.addEventListener('change', evaluate));
    return () => queries.forEach((q) => q.removeEventListener('change', evaluate));
  }, []);

  return enabled;
}
