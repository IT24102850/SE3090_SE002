import { useEffect, useRef, useState, type RefObject } from 'react';

/* The scroll-driven motion primitives the landing page is built from.
 *
 * All of them share one rAF loop and write transforms straight to the DOM
 * rather than through React state - a parallax layer that re-renders the
 * component tree sixty times a second drops frames on any machine. The one
 * exception is useReveal, which flips a class once and then stops.
 *
 * Every hook here no-ops under prefers-reduced-motion, leaving the page
 * static and fully readable.
 */

const prefersReduced = () =>
  typeof window !== 'undefined' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ── One shared rAF loop ──────────────────────────────────────────────── */
type Subscriber = () => void;
const subscribers = new Set<Subscriber>();
let loopId: number | null = null;

function runLoop() {
  subscribers.forEach((fn) => fn());
  loopId = subscribers.size > 0 ? requestAnimationFrame(runLoop) : null;
}

/** Exported so other scroll-driven hooks can share this one loop rather than
 *  opening their own. Every extra rAF is another wake-up per frame. */
export { subscribe as subscribeToScrollLoop };

function subscribe(fn: Subscriber) {
  subscribers.add(fn);
  if (loopId === null) loopId = requestAnimationFrame(runLoop);
  return () => {
    subscribers.delete(fn);
    if (subscribers.size === 0 && loopId !== null) {
      cancelAnimationFrame(loopId);
      loopId = null;
    }
  };
}

/**
 * How far an element has travelled through the viewport, 0 to 1.
 *
 * 0 when its top edge first reaches the bottom of the viewport, 1 when its
 * bottom edge leaves the top. This is the value every parallax layer and the
 * canvas sequence are driven from.
 *
 * Returned through a ref, not state: callers read it inside their own rAF
 * frame, so publishing it through React would re-render for nothing.
 */
export function useScrollProgress(ref: RefObject<HTMLElement>) {
  const progress = useRef(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const measure = () => {
      const rect = el.getBoundingClientRect();
      const total = window.innerHeight + rect.height;
      const travelled = window.innerHeight - rect.top;
      progress.current = Math.min(Math.max(travelled / total, 0), 1);
    };

    measure();
    return subscribe(measure);
  }, [ref]);

  return progress;
}

/**
 * Multi-layer parallax: each child carrying `data-depth` moves at its own
 * fraction of the scroll distance.
 *
 * Depth is a multiplier on the layer's travel: 0 is pinned to the page,
 * negative moves against the scroll (background), positive moves with it
 * (foreground). `speed` scales the whole effect in pixels.
 */
export function useParallaxLayers(ref: RefObject<HTMLElement>, speed = 120) {
  useEffect(() => {
    const el = ref.current;
    if (!el || prefersReduced()) return;

    const layers = Array.from(el.querySelectorAll<HTMLElement>('[data-depth]'));
    if (layers.length === 0) return;

    layers.forEach((l) => { l.style.willChange = 'transform'; });

    const update = () => {
      const rect = el.getBoundingClientRect();
      // -1 (element below the fold) .. 1 (element above it). Centre is 0, so
      // layers sit at their authored position when the section is centred.
      const centred = (window.innerHeight / 2 - (rect.top + rect.height / 2)) / window.innerHeight;

      for (const layer of layers) {
        const depth = parseFloat(layer.dataset.depth ?? '0');
        layer.style.transform = `translate3d(0, ${(centred * speed * depth).toFixed(2)}px, 0)`;
      }
    };

    update();
    const stop = subscribe(update);
    return () => {
      stop();
      layers.forEach((l) => { l.style.transform = ''; l.style.willChange = ''; });
    };
  }, [ref, speed]);
}

/**
 * Pointer parallax: children with `data-mouse-depth` drift toward the cursor.
 *
 * Damped rather than tracking the pointer exactly - a layer that snaps to the
 * cursor reads as jitter, one that eases toward it reads as depth. Skipped
 * entirely on coarse pointers, where there is no cursor to follow.
 */
export function useMouseParallax(ref: RefObject<HTMLElement>, strength = 26) {
  useEffect(() => {
    const el = ref.current;
    if (!el || prefersReduced()) return;
    if (window.matchMedia('(pointer: coarse)').matches) return;

    const layers = Array.from(el.querySelectorAll<HTMLElement>('[data-mouse-depth]'));
    if (layers.length === 0) return;

    // Target is where the pointer says to be; current eases toward it.
    const target = { x: 0, y: 0 };
    const current = { x: 0, y: 0 };

    const onMove = (e: PointerEvent) => {
      const rect = el.getBoundingClientRect();
      target.x = (e.clientX - rect.left) / rect.width - 0.5;
      target.y = (e.clientY - rect.top) / rect.height - 0.5;
    };
    const onLeave = () => { target.x = 0; target.y = 0; };

    const update = () => {
      current.x += (target.x - current.x) * 0.08;
      current.y += (target.y - current.y) * 0.08;
      for (const layer of layers) {
        const depth = parseFloat(layer.dataset.mouseDepth ?? '0');
        layer.style.transform =
          `translate3d(${(current.x * strength * depth).toFixed(2)}px, ${(current.y * strength * depth).toFixed(2)}px, 0)`;
      }
    };

    el.addEventListener('pointermove', onMove);
    el.addEventListener('pointerleave', onLeave);
    const stop = subscribe(update);

    return () => {
      el.removeEventListener('pointermove', onMove);
      el.removeEventListener('pointerleave', onLeave);
      stop();
      layers.forEach((l) => { l.style.transform = ''; });
    };
  }, [ref, strength]);
}

/**
 * Reveal-on-scroll for everything inside `ref` marked `data-reveal`.
 *
 * IntersectionObserver rather than the rAF loop: a reveal fires once and is
 * then done, so measuring it every frame forever would be waste. Elements
 * unobserve themselves as they fire, and stay revealed if the user scrolls
 * back up - re-hiding content someone has already read is hostile.
 */
export function useReveal(ref: RefObject<HTMLElement>) {
  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const items = Array.from(el.querySelectorAll<HTMLElement>('[data-reveal]'));
    if (items.length === 0) return;

    if (prefersReduced()) {
      items.forEach((i) => i.classList.add('is-revealed'));
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const item = entry.target as HTMLElement;
          // Stagger siblings so a grid cascades instead of snapping in as
          // one block. Authored per element, not derived from DOM order, so
          // a designer can break the cascade where it should not apply.
          item.style.transitionDelay = `${parseFloat(item.dataset.revealDelay ?? '0')}ms`;
          item.classList.add('is-revealed');
          observer.unobserve(item);
        }
      },
      // Fire a little before the element is fully on screen, so the motion
      // finishes about when it reaches a comfortable reading position.
      { threshold: 0.15, rootMargin: '0px 0px -8% 0px' },
    );

    items.forEach((i) => observer.observe(i));
    return () => observer.disconnect();
  }, [ref]);
}

/**
 * Progress through a pinned (sticky) section, 0 to 1.
 *
 * A sticky child holds still while its tall parent scrolls past; this reports
 * how far through that hold the page is, which is what drives the scrubbed
 * canvas and the pinned copy swaps. Published through state because callers
 * render from it - it changes at most once per frame and only while the
 * section is on screen.
 */
export function usePinnedProgress(ref: RefObject<HTMLElement>) {
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    let last = -1;
    const measure = () => {
      const rect = el.getBoundingClientRect();
      const distance = rect.height - window.innerHeight;
      if (distance <= 0) return;

      const raw = Math.min(Math.max(-rect.top / distance, 0), 1);
      // Quantise to 1/200ths: below that the change is invisible, and
      // skipping the setState avoids a render per frame while pinned.
      const stepped = Math.round(raw * 200) / 200;
      if (stepped !== last) {
        last = stepped;
        setProgress(stepped);
      }
    };

    measure();
    return subscribe(measure);
  }, [ref]);

  return progress;
}
