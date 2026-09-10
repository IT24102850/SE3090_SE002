import { useEffect, useRef, useState, type RefObject } from 'react';
import OrbitCanvas from '../OrbitCanvas';
import {
  buffer,
  createProgram,
  icosphere,
  multiply,
  particleShell,
  perspective,
  rotateX,
  rotateY,
  translate,
  type Mat4,
} from './glx';

/* The hero: a real 3D scene in WebGL, scrubbed by scroll.
 *
 * A geodesic wireframe sphere with glowing vertices, inside a drifting
 * particle shell. Scroll drives the camera's orbit and dolly and the amount
 * the surface is displaced; the pointer nudges the camera a little further.
 * Because rotation is a pure function of scroll position rather than time,
 * scrubbing back up runs the whole thing backwards exactly.
 *
 * Falls back to the 2D canvas orbit when WebGL is unavailable or the context
 * is lost - a visitor on a locked-down browser gets the lesser sculpture
 * rather than an empty rectangle.
 */

const VERT_SPHERE = `
precision mediump float;
attribute vec3 aPosition;
uniform mat4 uProjection;
uniform mat4 uView;
uniform float uTime;
uniform float uDisplace;
varying float vDepth;
varying float vElevation;

// Cheap value noise. A gradient/simplex implementation would be smoother, but
// this is displacing a wireframe by a few percent of its radius - the extra
// instructions would buy nothing anyone can see.
float hash(vec3 p) {
  return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float noise(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float n = mix(
    mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
        mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
    mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
        mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
    f.z);
  return n;
}

void main() {
  // Displace along the normal, which for a unit sphere is the position.
  float n = noise(aPosition * 2.4 + uTime * 0.18);
  vElevation = n;
  vec3 displaced = aPosition * (1.0 + (n - 0.5) * uDisplace);

  vec4 viewPos = uView * vec4(displaced, 1.0);
  vDepth = -viewPos.z;
  gl_Position = uProjection * viewPos;
  gl_PointSize = 3.2;
}
`;

const FRAG_SPHERE = `
precision mediump float;
varying float vDepth;
varying float vElevation;
uniform vec3 uNear;
uniform vec3 uFar;
uniform float uAlpha;

void main() {
  // Depth fade is what makes a wireframe read as a solid volume rather than a
  // flat tangle: the far side of the sphere recedes instead of competing.
  float fog = clamp((vDepth - 2.0) / 4.5, 0.0, 1.0);
  vec3 color = mix(uNear, uFar, fog * 0.85 + vElevation * 0.15);
  gl_FragColor = vec4(color, uAlpha * (1.0 - fog * 0.72));
}
`;

const VERT_PARTICLES = `
precision mediump float;
attribute vec4 aParticle; // xyz + seed
uniform mat4 uProjection;
uniform mat4 uView;
uniform float uTime;
varying float vSeed;
varying float vDepth;

void main() {
  // Each particle drifts on its own phase so the field breathes rather than
  // pulsing in unison.
  float phase = aParticle.w * 6.2831;
  vec3 drift = vec3(
    sin(uTime * 0.35 + phase) * 0.07,
    cos(uTime * 0.28 + phase * 1.7) * 0.07,
    sin(uTime * 0.31 + phase * 0.6) * 0.07
  );
  vec4 viewPos = uView * vec4(aParticle.xyz + drift, 1.0);
  vDepth = -viewPos.z;
  vSeed = aParticle.w;
  gl_Position = uProjection * viewPos;
  // Nearer particles are larger; the clamp stops the closest becoming blobs.
  gl_PointSize = clamp(9.0 / vDepth, 1.0, 3.4);
}
`;

const FRAG_PARTICLES = `
precision mediump float;
varying float vSeed;
varying float vDepth;
uniform vec3 uNear;
uniform vec3 uFar;

void main() {
  // gl_PointCoord is a square; discard outside the inscribed circle so the
  // points are round, then feather the edge.
  vec2 offset = gl_PointCoord - vec2(0.5);
  float d = length(offset);
  if (d > 0.5) discard;
  float alpha = smoothstep(0.5, 0.1, d);

  float fog = clamp((vDepth - 2.0) / 7.0, 0.0, 1.0);
  vec3 color = mix(uNear, uFar, vSeed);
  gl_FragColor = vec4(color, alpha * (1.0 - fog) * 0.72);
}
`;

const CYAN: [number, number, number] = [0.0, 0.898, 1.0];      // #00E5FF
const MAGENTA: [number, number, number] = [1.0, 0.176, 0.584]; // #FF2D95
const ELECTRIC: [number, number, number] = [0.298, 0.435, 1.0]; // #4C6FFF

/** Which of the three acts the camera is playing. The scene holds no global
 *  scroll state of its own: the act says which path, the progress says where
 *  along it, and nothing else reaches in. */
export type Act = 1 | 2 | 3;

interface Props {
  /** 0..1 within this act. Every structural value is a pure function of it. */
  progress: number;
  act?: Act;
  /**
   * Element the object sits over while the act is at rest.
   *
   * The canvas is full-bleed, but at the top of Act I the object should read
   * as the right-hand half of a two-column hero rather than as something
   * floating in the middle of the copy. Rather than boxing the canvas - which
   * would mean flying into a 460px window and feeling like watching rather
   * than entering - the camera is offset so the object lands over this
   * element, and the offset resolves to centre as the approach begins.
   */
  anchorRef?: RefObject<HTMLElement>;
}

export default function HeroScene({ progress, act = 1, anchorRef }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [failed, setFailed] = useState(false);

  // Scroll, act and pointer live in refs so the render loop reads the latest
  // values without the effect re-running (and rebuilding every GL buffer)
  // on each frame.
  const progressRef = useRef(progress);
  progressRef.current = progress;
  const actRef = useRef<Act>(act);
  actRef.current = act;
  const pointer = useRef({ x: 0, y: 0, tx: 0, ty: 0 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const gl = (canvas.getContext('webgl', { antialias: true, alpha: true }) ||
      canvas.getContext('experimental-webgl', { antialias: true, alpha: true })) as WebGLRenderingContext | null;

    if (!gl) { setFailed(true); return; }

    const sphereProgram = createProgram(gl, VERT_SPHERE, FRAG_SPHERE);
    const particleProgram = createProgram(gl, VERT_PARTICLES, FRAG_PARTICLES);
    if (!sphereProgram || !particleProgram) { setFailed(true); return; }

    const { positions, edges } = icosphere(2);
    const spherePositions = buffer(gl, positions);
    const edgeBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, edgeBuffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, edges, gl.STATIC_DRAW);

    const particles = particleShell(560, 1.7, 3.4);
    const particleBuffer = buffer(gl, particles);

    // Drawn count rather than uploaded count: the perf tier halves this, and
    // re-uploading a smaller buffer to draw fewer points would be work done
    // precisely on the machine that already cannot keep up.
    let particleCount = particles.length / 4;

    const loc = {
      spherePos: gl.getAttribLocation(sphereProgram, 'aPosition'),
      sphereProj: gl.getUniformLocation(sphereProgram, 'uProjection'),
      sphereView: gl.getUniformLocation(sphereProgram, 'uView'),
      sphereTime: gl.getUniformLocation(sphereProgram, 'uTime'),
      sphereDisplace: gl.getUniformLocation(sphereProgram, 'uDisplace'),
      sphereNear: gl.getUniformLocation(sphereProgram, 'uNear'),
      sphereFar: gl.getUniformLocation(sphereProgram, 'uFar'),
      sphereAlpha: gl.getUniformLocation(sphereProgram, 'uAlpha'),
      particleAttr: gl.getAttribLocation(particleProgram, 'aParticle'),
      particleProj: gl.getUniformLocation(particleProgram, 'uProjection'),
      particleView: gl.getUniformLocation(particleProgram, 'uView'),
      particleTime: gl.getUniformLocation(particleProgram, 'uTime'),
      particleNear: gl.getUniformLocation(particleProgram, 'uNear'),
      particleFar: gl.getUniformLocation(particleProgram, 'uFar'),
    };

    let projection: Mat4 = perspective(Math.PI / 4, 1, 0.1, 100);

    /* Device pixel ratio is capped at 2 always, and at 1.5 once the camera is
     * inside the shell. Inside, the geometry is inches from the lens and every
     * line covers a large share of the frame, so cost is fill rate rather than
     * vertex count - and a fifth fewer pixels is invisible on a wireframe that
     * is already blurred by additive blending and fog. */
    let dprCap = 2;

    /* Where the object rests, as a fraction of the half-width: 0 is centred,
     * 1 is the right edge. Measured in resize() rather than per frame - it
     * only changes when the layout does, and reading two rects inside the
     * render loop would force a layout on every frame. */
    let anchorX = 0;

    /* The render loop needs the canvas box every frame for the projection's
     * aspect. Reading it there forces a synchronous layout per frame, which
     * on a page with two pinned sections is the single easiest jank to
     * introduce - so it is measured here and cached. */
    let box = { width: 1, height: 1 };

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      box = { width: rect.width, height: Math.max(rect.height, 1) };

      const anchor = anchorRef?.current;
      if (anchor && rect.width > 0) {
        const a = anchor.getBoundingClientRect();
        anchorX = ((a.left + a.width / 2) - (rect.left + rect.width / 2)) / (rect.width / 2);
      } else {
        anchorX = 0;
      }

      const dpr = Math.min(window.devicePixelRatio || 1, dprCap);
      canvas.width = Math.max(1, Math.round(rect.width * dpr));
      canvas.height = Math.max(1, Math.round(rect.height * dpr));
      gl.viewport(0, 0, canvas.width, canvas.height);
      // The projection itself is rebuilt per frame in render(), because the
      // fly-through widens the field of view as it goes.
    };

    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const onPointer = (e: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointer.current.tx = (e.clientX - rect.left) / rect.width - 0.5;
      pointer.current.ty = (e.clientY - rect.top) / rect.height - 0.5;
    };

    gl.enable(gl.BLEND);
    // Additive blending: overlapping glowing lines should brighten, which is
    // what makes the dense far side of the sphere read as luminous.
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE);
    gl.disable(gl.DEPTH_TEST); // additive glow does not want depth rejection

    let raf = 0;
    const start = performance.now();

    /* Rolling frame-time budget.
     *
     * Tier 0 is everything on. Above 22ms average the particle field halves,
     * once. Tier 1 gets one further window, and above 30ms there the scene
     * gives up and hands over to the 2D fallback, which costs a fraction as
     * much. Tier 2 stops measuring - there is nothing left to decide.
     *
     * The brief says "drop the point count by half once and stop measuring",
     * then describes a second threshold after that; taken literally those
     * cannot both hold, so this stops measuring after the last decision
     * rather than before it.
     *
     * The first 20 frames are discarded. Shader compilation, the first draw
     * and buffer upload all land there, and judging a machine on them
     * demotes hardware that is about to be perfectly fine.
     */
    let tier = 0;
    let warmup = 20;
    let windowFrames = 0;
    let windowMs = 0;
    let lastFrame = start;

    const render = () => {
      const now = performance.now();
      const frameMs = now - lastFrame;
      lastFrame = now;

      if (warmup > 0) {
        warmup--;
      } else if (tier < 2) {
        windowMs += frameMs;
        windowFrames++;
        if (windowFrames >= 30) {
          const average = windowMs / windowFrames;
          windowFrames = 0;
          windowMs = 0;
          if (tier === 0 && average > 22) {
            tier = 1;
            particleCount = Math.floor(particleCount / 2);
          } else if (tier === 1 && average > 30) {
            tier = 2;
            cancelAnimationFrame(raf);
            setFailed(true);
            return;
          }
        }
      }

      const p = progressRef.current;
      // Time only advances the ambient drift. Everything structural is driven
      // by scroll, so the scene is deterministic at any given position.
      const time = reduced ? 0 : (performance.now() - start) / 1000;

      pointer.current.x += (pointer.current.tx - pointer.current.x) * 0.05;
      pointer.current.y += (pointer.current.ty - pointer.current.y) * 0.05;

      // ── Camera: one path per act ────────────────────────────────────
      //
      // Act I is a genuine fly-through, not a dolly. Distance runs 4.4 -> 0.30
      // while the shell stays at radius 1, so a little past four-fifths of the
      // scroll the camera crosses the surface and the rest is spent inside
      // looking out through the far wall. Eased so the approach is unhurried
      // and the crossing is quick - a linear dolly makes the whole thing feel
      // like a slow zoom instead of arrival.
      //
      // It starts at 4.4 rather than further out because the depth fog is
      // keyed to view distance: from 7-odd units the whole sphere sits in the
      // far half of the ramp and renders small and washed toward the fog
      // colour, which throws away the first impression to buy travel nobody
      // sees. 4.4 is where it reads at full size and full cyan.
      const approach = p * p * (3 - 2 * p); // smoothstep
      const currentAct = actRef.current;

      // Acts II and III continue the same journey: II holds where I left the
      // camera, III retraces I's last stretch outward. Sharing the endpoints
      // is what makes three pinned sections read as one continuous move.
      const distance =
        currentAct === 1 ? 4.4 - approach * 4.1
        : currentAct === 2 ? 0.30
        : 0.30 + approach * 2.9;
      const inside = distance < 1;

      // Re-rasterise at the lower cap on the way in and the higher one on the
      // way out. Compared against the applied value so this costs one integer
      // test per frame and reallocates the drawing buffer twice per visit.
      const wantCap = inside ? 1.5 : 2;
      if (wantCap !== dprCap) { dprCap = wantCap; resize(); }

      // How close the lens is to the shell, 0 away from it and 1 at the
      // moment of crossing. Drives the fades and the surface agitation.
      const crossing = 1 - Math.min(Math.abs(distance - 1) / 0.55, 1);

      // Rotation accelerates as the shell gets close, which is what sells
      // the sense of passing through something rather than into a backdrop.
      const yaw = p * Math.PI * 2.1 + approach * 1.1 + pointer.current.x * 0.6;
      const pitch = -0.32 + p * 0.62 + pointer.current.y * 0.4;

      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);

      // Widening the field of view as the camera closes is the standard
      // trick for making a dolly read as speed - the periphery stretches
      // past you. The near plane is tight so geometry can pass the lens.
      const aspect = box.width / box.height;
      const fov = (Math.PI / 4) * (1 + approach * 0.55);
      projection = perspective(fov, aspect, 0.05, 100);

      /* Convert the anchor from a screen fraction to a camera-space offset at
       * the object's own depth, so it lands exactly over the anchor element
       * whatever the viewport aspect. It unwinds with the approach: by the
       * time the lens reaches the shell the object is dead centre and the
       * whole viewport belongs to it. */
      const halfHeight = distance * Math.tan(fov / 2);
      const offsetX = anchorX * halfHeight * aspect * (1 - approach);

      const view = multiply(
        translate(offsetX, 0, -distance),
        multiply(rotateX(pitch), rotateY(yaw)),
      );

      // Particles first: they belong behind the sphere, and with depth
      // testing off, draw order is what decides that.
      gl.useProgram(particleProgram);
      gl.uniformMatrix4fv(loc.particleProj, false, projection);
      gl.uniformMatrix4fv(loc.particleView, false, view);
      gl.uniform1f(loc.particleTime, time);
      gl.uniform3fv(loc.particleNear, CYAN);
      gl.uniform3fv(loc.particleFar, MAGENTA);
      gl.bindBuffer(gl.ARRAY_BUFFER, particleBuffer);
      gl.enableVertexAttribArray(loc.particleAttr);
      gl.vertexAttribPointer(loc.particleAttr, 4, gl.FLOAT, false, 0, 0);
      gl.drawArrays(gl.POINTS, 0, particleCount);

      gl.useProgram(sphereProgram);
      gl.uniformMatrix4fv(loc.sphereProj, false, projection);
      gl.uniformMatrix4fv(loc.sphereView, false, view);
      gl.uniform1f(loc.sphereTime, time);
      // The surface unsettles most as you pass through it, and calms once
      // you are inside.
      gl.uniform1f(loc.sphereDisplace, 0.05 + Math.sin(p * Math.PI) * 0.14 + crossing * 0.22);
      gl.uniform3fv(loc.sphereNear, CYAN);
      gl.uniform3fv(loc.sphereFar, ELECTRIC);
      gl.bindBuffer(gl.ARRAY_BUFFER, spherePositions);
      gl.enableVertexAttribArray(loc.spherePos);
      gl.vertexAttribPointer(loc.spherePos, 3, gl.FLOAT, false, 0, 0);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, edgeBuffer);

      // Right at the crossing the near wall is inches from the lens and would
      // otherwise smear across the whole frame; fading it there turns the
      // moment into a passage instead of a collision.
      const shellAlpha = 0.55 * (1 - crossing * 0.72);

      gl.uniform1f(loc.sphereAlpha, shellAlpha);
      gl.drawElements(gl.LINES, edges.length, gl.UNSIGNED_SHORT, 0);

      // Vertices again as points, brighter, so the nodes read as lit. Inside
      // the shell they are all around the camera, so they are dimmed too.
      gl.uniform1f(loc.sphereAlpha, inside ? 0.5 : 0.95 * (1 - crossing * 0.5));
      gl.uniform3fv(loc.sphereFar, MAGENTA);
      gl.drawArrays(gl.POINTS, 0, positions.length / 3);

      if (running) raf = requestAnimationFrame(render);
    };

    // A lost context (GPU reset, tab backgrounded too long) would otherwise
    // leave a blank rectangle behind - fall back instead.
    const onLost = (e: Event) => { e.preventDefault(); cancelAnimationFrame(raf); setFailed(true); };
    canvas.addEventListener('webglcontextlost', onLost);

    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    if (!window.matchMedia('(pointer: coarse)').matches) {
      canvas.addEventListener('pointermove', onPointer);
    }

    /* Only render while the canvas is actually on screen. There are two of
     * these on the page and the visitor spends most of the scroll looking at
     * neither, so without this the page pays for a GPU pass per frame per
     * canvas the whole way down. Resumed by re-entry; the scene is a pure
     * function of progress, so nothing has to be caught up on the way back. */
    let running = false;
    const play = () => {
      if (running || tier === 2) return;
      running = true;
      lastFrame = performance.now();
      warmup = Math.max(warmup, 2); // the resume frame is always a long one
      raf = requestAnimationFrame(render);
    };
    const pause = () => {
      running = false;
      cancelAnimationFrame(raf);
    };

    const visibility = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) play(); else pause(); },
      { rootMargin: '10% 0px' },
    );
    visibility.observe(canvas);

    return () => {
      pause();
      observer.disconnect();
      visibility.disconnect();
      canvas.removeEventListener('pointermove', onPointer);
      canvas.removeEventListener('webglcontextlost', onLost);
      gl.deleteBuffer(spherePositions);
      gl.deleteBuffer(edgeBuffer);
      gl.deleteBuffer(particleBuffer);
      gl.deleteProgram(sphereProgram);
      gl.deleteProgram(particleProgram);
      /* Contexts are a scarce per-tab resource - browsers keep about 16 and
       * silently kill the oldest - so ours is released explicitly rather than
       * left for the collector.
       *
       * Deferred, and only if the canvas has actually left the document. A
       * cleanup does not mean the component is going away: StrictMode mounts,
       * unmounts and remounts in one commit, and React 18 will do the same on
       * a future refresh. Losing the context there is not recoverable by the
       * remount - getContext returns the same, now-lost context rather than a
       * fresh one, every shader compile fails against it, and the scene falls
       * back to the 2D orbit for the rest of the session. By the next task
       * the remount has already run and reclaimed this canvas, so isConnected
       * distinguishes the two cases cleanly. */
      setTimeout(() => {
        if (!canvas.isConnected) gl.getExtension('WEBGL_lose_context')?.loseContext();
      }, 0);
    };
  }, []);

  if (failed) return <OrbitCanvas progress={progress} />;

  return <canvas ref={canvasRef} className="lp-canvas" aria-hidden="true" />;
}
