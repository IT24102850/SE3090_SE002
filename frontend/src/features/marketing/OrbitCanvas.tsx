import { useEffect, useRef } from 'react';

/* The scroll-scrubbed hero sculpture: scrolling rotates the object, the way
 * Apple's product pages rotate a laptop as you scroll.
 *
 * ── Why this is not a frame sequence ──────────────────────────────────
 * Apple ships a few hundred pre-rendered JPEGs and blits frame N to a canvas
 * where N is a function of scroll. That needs a 3D render pipeline to produce
 * the frames, and lands several megabytes of images on the visitor.
 *
 * This draws the same object procedurally instead, with rotation indexed by
 * scroll rather than by time. The interaction is identical - scroll position
 * *is* the frame index - but there is no image payload, it stays sharp at any
 * size and on any DPR, and there is no sequence to re-render when the brand
 * colours move. The trade is that the geometry has to be something drawable
 * in a couple of hundred lines of canvas, which intertwined rings are and a
 * photorealistic laptop is not.
 *
 * If a real render sequence ever exists, `draw(progress)` is the only thing
 * that has to change: swap the ring drawing for
 * `ctx.drawImage(frames[Math.round(progress * (frames.length - 1))], …)`.
 */

interface RingSpec {
  /** Fraction of the canvas half-size this ring spans. */
  scale: number;
  /** Fixed tilt, radians. */
  tiltX: number;
  tiltY: number;
  /** Turns per full scroll of the pinned section. Negative reverses. */
  turns: number;
  /** Starting angle, so the rings never begin aligned. */
  phase: number;
  color: string;
  alpha: number;
  width: number;
}

// The same four rings as the Flutter OrbitHero, in the same order.
const RINGS: RingSpec[] = [
  { scale: 1.0, tiltX: 1.15, tiltY: 0.1, turns: 1.0, phase: 0.0, color: '#E8ECF8', alpha: 0.5, width: 1.6 },
  { scale: 0.84, tiltX: 0.55, tiltY: 0.85, turns: -1.6, phase: 0.8, color: '#00E5FF', alpha: 0.62, width: 1.8 },
  { scale: 0.68, tiltX: 1.35, tiltY: -0.6, turns: 2.1, phase: 1.9, color: '#FF2D95', alpha: 0.5, width: 1.8 },
  { scale: 0.52, tiltX: 0.25, tiltY: 0.35, turns: -2.8, phase: 3.1, color: '#CBD5F5', alpha: 0.34, width: 1.4 },
];

/** Points per ring. 96 is past the point where more is visible at any size we
 *  render, and keeps four rings well inside one frame's budget. */
const SEGMENTS = 96;
/** Perspective focal length, in units of the canvas half-size. */
const FOCAL = 2.6;

export default function OrbitCanvas({ progress }: { progress: number }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  // Held in a ref so the draw effect does not re-subscribe every frame; the
  // second effect below just re-runs draw when it changes.
  const progressRef = useRef(progress);
  progressRef.current = progress;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let width = 0;
    let height = 0;

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      // Cap DPR at 2: beyond that the pixel cost doubles again for a
      // difference nobody can see on a gradient-stroked hairline.
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = rect.width;
      height = rect.height;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      draw();
    };

    const draw = () => {
      const p = progressRef.current;
      const cx = width / 2;
      const cy = height / 2;
      const half = Math.min(width, height) / 2;
      const radius = half * 0.78;

      ctx.clearRect(0, 0, width, height);

      // Core glow first, so the rings composite over it.
      const coreR = half * 0.2;
      const glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, coreR * 3.4);
      glow.addColorStop(0, 'rgba(255,255,255,0.95)');
      glow.addColorStop(0.14, 'rgba(0,229,255,0.75)');
      glow.addColorStop(0.42, 'rgba(76,111,255,0.32)');
      glow.addColorStop(1, 'rgba(76,111,255,0)');
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(cx, cy, coreR * 3.4, 0, Math.PI * 2);
      ctx.fill();

      for (const ring of RINGS) {
        // Scroll drives the angle. This is the whole trick: the object's
        // rotation is a pure function of scroll position, so scrubbing back
        // and forth runs it backwards and forwards exactly.
        const spin = ring.phase + p * ring.turns * Math.PI * 2;
        const r = radius * ring.scale;

        const cosX = Math.cos(ring.tiltX);
        const sinX = Math.sin(ring.tiltX);
        const cosY = Math.cos(ring.tiltY + spin);
        const sinY = Math.sin(ring.tiltY + spin);

        // Each segment is stroked on its own so alpha can track depth - the
        // far half of a ring must read as *behind* the core, and a single
        // uniform stroke would make the ring look flat.
        let prev: { x: number; y: number; z: number } | null = null;

        for (let i = 0; i <= SEGMENTS; i++) {
          const t = (i / SEGMENTS) * Math.PI * 2;
          // Circle in the XY plane...
          const x0 = Math.cos(t) * r;
          const y0 = Math.sin(t) * r;
          // ...tilted about X, then spun about Y.
          const y1 = y0 * cosX;
          const z1 = y0 * sinX;
          const x2 = x0 * cosY + z1 * sinY;
          const z2 = -x0 * sinY + z1 * cosY;

          // Perspective projection; +z is toward the viewer.
          const depth = FOCAL / (FOCAL - z2 / half);
          const point = { x: cx + x2 * depth, y: cy + y1 * depth, z: z2 };

          if (prev) {
            // Map z from [-r, r] to [0.25, 1] so the back of the ring dims
            // without disappearing.
            const zMid = (prev.z + point.z) / 2;
            const depthAlpha = 0.25 + 0.75 * ((zMid / r + 1) / 2);
            ctx.globalAlpha = ring.alpha * depthAlpha;
            ctx.strokeStyle = ring.color;
            ctx.lineWidth = ring.width * (0.7 + 0.5 * depthAlpha);
            ctx.beginPath();
            ctx.moveTo(prev.x, prev.y);
            ctx.lineTo(point.x, point.y);
            ctx.stroke();
          }
          prev = point;
        }
      }

      ctx.globalAlpha = 1;

      // Solid core last, so it sits over the near half of every ring.
      const core = ctx.createRadialGradient(
        cx - coreR * 0.3, cy - coreR * 0.35, 0, cx, cy, coreR,
      );
      core.addColorStop(0, '#FFFFFF');
      core.addColorStop(0.45, '#00E5FF');
      core.addColorStop(1, '#4C6FFF');
      ctx.fillStyle = core;
      ctx.beginPath();
      ctx.arc(cx, cy, coreR, 0, Math.PI * 2);
      ctx.fill();
    };

    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);

    // Expose the draw so the progress effect below can call it without
    // rebuilding the observer.
    (canvas as HTMLCanvasElement & { _draw?: () => void })._draw = draw;

    return () => observer.disconnect();
  }, []);

  // Redraw whenever scroll moves the sculpture. usePinnedProgress quantises
  // its output, so this fires at most once per frame and only while pinned.
  useEffect(() => {
    const canvas = canvasRef.current as (HTMLCanvasElement & { _draw?: () => void }) | null;
    canvas?._draw?.();
  }, [progress]);

  return <canvas ref={canvasRef} className="lp-canvas" aria-hidden="true" />;
}
