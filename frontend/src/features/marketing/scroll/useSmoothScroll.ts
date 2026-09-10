import { useEffect, useRef } from 'react';

/* Lenis-equivalent smooth scrolling, hand-rolled.
 *
 * The real thing (npm `lenis`) is not installable on this network - the
 * registry answers 403 for every package, a condition this repo already
 * documents in vitest.config.ts. This is the same technique in ~120 lines:
 * intercept the wheel, hold a target scroll position, and ease the real
 * scroll toward it on requestAnimationFrame.
 *
 * To swap in the real library later: `npm i lenis`, then replace the body of
 * this hook with `new Lenis({ lerp })` plus its rAF loop. Everything else on
 * the page reads scroll through window.scrollY, which Lenis also drives, so
 * nothing downstream changes.
 *
 * Deliberately opt-in per page rather than global: it is mounted by the
 * landing page only. Hijacking the wheel inside the admin console - which
 * has scrollable tables and modals - would make it feel broken.
 */

interface Options {
  /** 0..1. Lower is slower and heavier; Lenis defaults to 0.1. */
  lerp?: number;
  /** Multiplier on raw wheel delta. */
  wheelMultiplier?: number;
}

export function useSmoothScroll({ lerp = 0.1, wheelMultiplier = 1 }: Options = {}) {
  const target = useRef(0);
  const current = useRef(0);
  const raf = useRef<number>();

  useEffect(() => {
    // Someone who asked the OS to reduce motion does not want the scroll
    // position lagging behind their input. Native scrolling, untouched.
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    // Coarse pointers already have momentum scrolling that feels better than
    // anything re-implemented on top of it, and hijacking touch there fights
    // the platform.
    if (window.matchMedia('(pointer: coarse)').matches) return;

    const maxScroll = () =>
      Math.max(0, document.documentElement.scrollHeight - window.innerHeight);

    target.current = window.scrollY;
    current.current = window.scrollY;

    // True while the loop is easing toward a target the wheel set. When it is
    // false the page scrolls natively and this hook keeps out of the way.
    let animating = false;
    // Set immediately before our own scrollTo so the scroll listener can tell
    // our writes apart from the user's. Without this the listener resyncs to
    // the position we just wrote and the easing never converges.
    let selfScroll = false;

    const onWheel = (e: WheelEvent) => {
      // Leave zoom gestures and anything with its own scrollport alone.
      if (e.ctrlKey) return;
      if ((e.target as Element | null)?.closest?.('[data-native-scroll]')) return;

      e.preventDefault();
      // Seed from the live position when starting a fresh gesture, so a wheel
      // after a scrollbar drag continues from where the page actually is.
      if (!animating) current.current = window.scrollY;
      target.current = Math.min(
        Math.max((animating ? target.current : window.scrollY) + e.deltaY * wheelMultiplier, 0),
        maxScroll(),
      );
      animating = true;
    };

    /* Everything that moves the page without going through the wheel -
     * dragging the scrollbar, PageDown, space, Home/End, find-in-page, and
     * the smooth scrollIntoView the nav buttons use. Previously the rAF loop
     * kept writing its own stale position on the next frame and yanked the
     * page straight back, which made all of those feel broken. */
    const onScroll = () => {
      if (selfScroll) {
        selfScroll = false;
        return;
      }
      animating = false;
      target.current = window.scrollY;
      current.current = window.scrollY;
    };

    const tick = () => {
      if (animating) {
        const delta = target.current - current.current;
        if (Math.abs(delta) > 0.35) {
          current.current += delta * lerp;
          selfScroll = true;
          window.scrollTo(0, current.current);
        } else {
          // Settle exactly and hand control back to the browser.
          current.current = target.current;
          animating = false;
        }
      }
      raf.current = requestAnimationFrame(tick);
    };

    const onResize = () => {
      animating = false;
      target.current = window.scrollY;
      current.current = window.scrollY;
    };

    window.addEventListener('wheel', onWheel, { passive: false });
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onResize);
    raf.current = requestAnimationFrame(tick);

    return () => {
      window.removeEventListener('wheel', onWheel);
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onResize);
      if (raf.current) cancelAnimationFrame(raf.current);
    };
  }, [lerp, wheelMultiplier]);
}

/** Smooth-scrolls to an element, used by the in-page nav anchors so they
 *  match the wheel feel instead of jumping. The hook above yields to this:
 *  its scroll listener sees the browser's own smooth scroll and stops
 *  animating rather than fighting it. */
export function scrollToId(id: string) {
  const el = document.getElementById(id);
  if (!el) return;
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  el.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' });
}
