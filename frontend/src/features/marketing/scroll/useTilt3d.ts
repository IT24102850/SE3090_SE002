import { useEffect, type RefObject } from 'react';

/* Pointer-driven 3D tilt for every `[data-tilt]` inside `ref`.
 *
 * Each card gets its own perspective and rotates about X and Y toward the
 * cursor, with a highlight that tracks the pointer across its surface. The
 * rotation is small on purpose - past about 10 degrees a card stops reading
 * as a tilted plane and starts reading as a bug.
 *
 * Damped toward the target rather than snapped to it, and reset on leave, so
 * the card settles instead of twitching.
 */
export function useTilt3d(ref: RefObject<HTMLElement>, maxDeg = 7) {
  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    // No cursor to follow, and on touch the tilt would fight scrolling.
    if (window.matchMedia('(pointer: coarse)').matches) return;

    const cards = Array.from(root.querySelectorAll<HTMLElement>('[data-tilt]'));
    if (cards.length === 0) return;

    const cleanups: Array<() => void> = [];

    for (const card of cards) {
      const state = { rx: 0, ry: 0, trx: 0, try_: 0, active: false };
      let raf = 0;

      const tick = () => {
        state.rx += (state.trx - state.rx) * 0.12;
        state.ry += (state.try_ - state.ry) * 0.12;
        card.style.transform =
          `perspective(900px) rotateX(${state.rx.toFixed(2)}deg) rotateY(${state.ry.toFixed(2)}deg)`;

        // Stop the loop once it has settled and the pointer is gone, rather
        // than running a rAF per card for the life of the page.
        const settled = Math.abs(state.trx - state.rx) < 0.01 && Math.abs(state.try_ - state.ry) < 0.01;
        if (!state.active && settled) {
          card.style.transform = '';
          raf = 0;
          return;
        }
        raf = requestAnimationFrame(tick);
      };

      const start = () => { if (!raf) raf = requestAnimationFrame(tick); };

      const onMove = (e: PointerEvent) => {
        const rect = card.getBoundingClientRect();
        const px = (e.clientX - rect.left) / rect.width;
        const py = (e.clientY - rect.top) / rect.height;
        state.active = true;
        // Y movement tilts about X, and inverted: pointer near the top should
        // push the top edge away, which is a negative rotateX.
        state.trx = -(py - 0.5) * 2 * maxDeg;
        state.try_ = (px - 0.5) * 2 * maxDeg;
        card.style.setProperty('--tilt-x', `${(px * 100).toFixed(1)}%`);
        card.style.setProperty('--tilt-y', `${(py * 100).toFixed(1)}%`);
        start();
      };

      const onLeave = () => {
        state.active = false;
        state.trx = 0;
        state.try_ = 0;
        card.style.removeProperty('--tilt-x');
        card.style.removeProperty('--tilt-y');
        start();
      };

      card.addEventListener('pointermove', onMove);
      card.addEventListener('pointerleave', onLeave);
      cleanups.push(() => {
        card.removeEventListener('pointermove', onMove);
        card.removeEventListener('pointerleave', onLeave);
        if (raf) cancelAnimationFrame(raf);
        card.style.transform = '';
      });
    }

    return () => cleanups.forEach((fn) => fn());
  }, [ref, maxDeg]);
}
