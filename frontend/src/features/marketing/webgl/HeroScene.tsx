import { useEffect, useRef, useState, type RefObject } from 'react';
import OrbitCanvas from '../OrbitCanvas';
import {
  MODULE_STRIDE,
  buffer,
  createProgram,
  icosphere,
  moduleClusters,
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

/* The six module clusters and their links to the core.
 *
 * One program, one attribute layout, two buffers - the clusters drawn as
 * points and the links as lines. Cluster positions arrive as six vec3
 * uniforms rather than as vertex data, so animating the whole assembly costs
 * eighteen floats a frame instead of rewriting the buffer.
 */
const VERT_MODULES = `
precision mediump float;
attribute vec3 aLocal;
attribute float aModule;
attribute float aCore;   // 1 for the end of a tether that sits at the core

uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 uModulePos[6];
uniform float uModuleT[6];    // 0 off-camera, 1 locked on
uniform float uModuleLit[6];  // Act III: which modules this trade uses

varying float vDepth;
varying float vArrive;
varying float vLit;
varying float vCore;

void main() {
  /* Selected by a constant-bounds loop rather than uModulePos[int(aModule)].
     GLSL ES 1.0 only guarantees uniform arrays can be indexed by a constant
     expression, and the drivers that enforce it fail at link time on exactly
     the low-end hardware this scene is meant to survive on. */
  vec3 centre = vec3(0.0);
  float arrive = 0.0;
  float lit = 1.0;
  for (int i = 0; i < 6; i++) {
    if (abs(aModule - float(i)) < 0.5) {
      centre = uModulePos[i];
      arrive = uModuleT[i];
      lit = uModuleLit[i];
    }
  }

  vArrive = arrive;
  vLit = lit;
  // Interpolates 0..1 along a tether and stays 0 across a plate's own edges,
  // so one varying both fades the tether toward the core and leaves the
  // plate at full strength - no second draw call to tell them apart.
  vCore = aCore;

  vec3 world = mix(centre + aLocal, vec3(0.0), aCore);
  vec4 viewPos = uView * vec4(world, 1.0);
  vDepth = -viewPos.z;
  gl_Position = uProjection * viewPos;
  gl_PointSize = clamp(13.0 / max(vDepth, 0.35), 1.5, 6.0);
}
`;

const FRAG_MODULES = `
precision mediump float;
varying float vDepth;
varying float vArrive;
varying float vLit;
varying float vCore;
uniform vec3 uWarm;
uniform vec3 uCool;

void main() {
  vec2 offset = gl_PointCoord - vec2(0.5);
  // Lines rasterise with gl_PointCoord at (0,0), which the circle test would
  // discard - so only reject outside the disc when this is actually a point.
  if (offset.x != -0.5 && length(offset) > 0.5) discard;

  // A brief bloom as the cluster seats itself, peaking just before it stops.
  float flash = exp(-pow((vArrive - 0.9) / 0.07, 2.0));

  float fog = clamp((vDepth - 0.6) / 5.0, 0.0, 1.0);
  vec3 color = mix(uWarm, uCool, fog);
  // Unlit modules stay present as dim geometry. Absent would say the trade
  // cannot have them; dim says it is not using them.
  float body = mix(0.10, 1.0, vLit);
  // The tether is the connection, not the subject: it fades out along its
  // run so the eye follows it inward rather than reading it as structure.
  float tether = 1.0 - vCore * 0.78;

  float alpha = vArrive * (body + flash * 1.6) * (1.0 - fog * 0.55) * tether;
  gl_FragColor = vec4(color + flash * 0.5, alpha);
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
  /**
   * Act III: which of the six modules this business type uses.
   *
   * Unlit modules are dimmed rather than removed - the claim is that every
   * trade gets the same core and lights a different part of it, which only
   * reads if the unused part is visibly still there.
   */
  litModules?: boolean[];
  /**
   * Act II: elements to park at each cluster's landing site.
   *
   * The scene positions these itself, in its own render loop, because they
   * follow a projected 3D point - routing that through React would mean a
   * state update per frame per caption. Handing the scene six DOM nodes to
   * write transforms to is the smaller evil.
   */
  captionRefs?: RefObject<(HTMLElement | null)[]>;
}

export default function HeroScene({ progress, act = 1, anchorRef, litModules, captionRefs }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [failed, setFailed] = useState(false);

  // Scroll, act and pointer live in refs so the render loop reads the latest
  // values without the effect re-running (and rebuilding every GL buffer)
  // on each frame.
  const progressRef = useRef(progress);
  progressRef.current = progress;
  const actRef = useRef<Act>(act);
  actRef.current = act;
  const litRef = useRef<boolean[] | undefined>(litModules);
  litRef.current = litModules;
  const pointer = useRef({ x: 0, y: 0, tx: 0, ty: 0 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const gl = (canvas.getContext('webgl', { antialias: true, alpha: true }) ||
      canvas.getContext('experimental-webgl', { antialias: true, alpha: true })) as WebGLRenderingContext | null;

    if (!gl) { setFailed(true); return; }

    const sphereProgram = createProgram(gl, VERT_SPHERE, FRAG_SPHERE);
    const particleProgram = createProgram(gl, VERT_PARTICLES, FRAG_PARTICLES);
    const moduleProgram = createProgram(gl, VERT_MODULES, FRAG_MODULES);
    if (!sphereProgram || !particleProgram || !moduleProgram) { setFailed(true); return; }

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

    const modules = moduleClusters(6);
    const modulePointBuffer = buffer(gl, modules.points);
    const moduleLineBuffer = buffer(gl, modules.lines);

    // Reused every frame so the render loop allocates nothing.
    const modulePos = new Float32Array(6 * 3);
    const moduleT = new Float32Array(6);
    const moduleLit = new Float32Array(6).fill(1);

    /* Where the camera must be pointed to put each landing site dead centre.
     *
     * The view is translate(0,0,-d) * rotateX(pitch) * rotateY(yaw), so the
     * world turns rather than the camera. Solving for the yaw that swings an
     * anchor into the xz plane and the pitch that lifts it onto the view axis
     * is exact, which matters: six sites spread by the Fibonacci lattice are
     * deliberately nowhere near each other, and a hand-tuned sweep would miss
     * most of them from inside the shell where only a sixth of it is in shot.
     */
    const aimYaw = new Float32Array(6);
    const aimPitch = new Float32Array(6);
    for (let i = 0; i < 6; i++) {
      const ax = modules.anchors[i * 3];
      const ay = modules.anchors[i * 3 + 1];
      const az = modules.anchors[i * 3 + 2];
      const flat = Math.hypot(ax, az);
      /* Solved for the anchor landing on the NEGATIVE z axis in view space.
       *
       * There are two yaws that swing a point into the xz plane, half a turn
       * apart, and only one of them puts it in front of the lens: the view is
       * translate(0,0,-d) * R, so the camera looks along -z and a point is
       * visible when its view-space z is negative. Taking the +z solution -
       * the one that falls out of the algebra first - aims the camera exactly
       * 180 degrees from every landing site, which looks like the clusters
       * were never drawn at all. */
      aimYaw[i] = Math.atan2(ax, -az);
      aimPitch[i] = Math.atan2(-ay, flat);
    }

    /** Shortest way round: without this the camera unwinds the long way
     *  whenever consecutive sites straddle the +/-PI seam. */
    const lerpAngle = (a: number, b: number, t: number) => {
      let d = (b - a) % (Math.PI * 2);
      if (d > Math.PI) d -= Math.PI * 2;
      if (d < -Math.PI) d += Math.PI * 2;
      return a + d * t;
    };
    const smooth = (t: number) => t * t * (3 - 2 * t);
    const clamp01 = (v: number) => Math.min(Math.max(v, 0), 1);
    /* Act II's schedule, in one place because two things read it and they
     * must agree: module i flies in over [0.02 + 0.14i, 0.14 + 0.14i], so it
     * seats at BEAT * (i + 1). The last one lands at 0.84, leaving the tail
     * of the act for the pull-back that shows all six together. */
    const BEAT = 0.14;
    const arrival = (i: number, pr: number) =>
      smooth(clamp01((pr - (0.02 + i * BEAT)) / (BEAT - 0.02)));
    /** Fractional module index the camera should be facing at progress pr.
     *  Reaches exactly i at the moment module i seats - the earlier form was
     *  offset by most of a beat, so every cluster landed off-camera and every
     *  caption was clamped against the edge of the frame. */
    const facing = (pr: number) => Math.min(Math.max((pr - BEAT) / BEAT, 0), 5);
    /** The closing reveal: back out through the wall to take the whole thing in. */
    const finale = (pr: number) => smooth(clamp01((pr - 0.84) / 0.16));

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
      modLocal: gl.getAttribLocation(moduleProgram, 'aLocal'),
      modIndex: gl.getAttribLocation(moduleProgram, 'aModule'),
      modCore: gl.getAttribLocation(moduleProgram, 'aCore'),
      modProj: gl.getUniformLocation(moduleProgram, 'uProjection'),
      modView: gl.getUniformLocation(moduleProgram, 'uView'),
      modPos: gl.getUniformLocation(moduleProgram, 'uModulePos'),
      modT: gl.getUniformLocation(moduleProgram, 'uModuleT'),
      modLit: gl.getUniformLocation(moduleProgram, 'uModuleLit'),
      modWarm: gl.getUniformLocation(moduleProgram, 'uWarm'),
      modCool: gl.getUniformLocation(moduleProgram, 'uCool'),
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
        // Act II drifts back a little inside the shell - far enough that an
        // arriving cluster has somewhere to arrive into, still comfortably
        // within radius 1 so the visitor stays inside the object.
        /* The closing reveal has to clear the shell properly. Stopping just
         * outside it - the first thing that sounded like "out" - still framed
         * two plates and the inside of the far wall, which is the one shot
         * the act cannot end on: the whole point is that all six are on one
         * skeleton, and that is only a claim you can check from far enough
         * back to count them. */
        : currentAct === 2 ? 0.30 + smooth(p) * 0.42 + finale(p) * 1.58
        // Act III leaves through the wall early and then holds, so the six
        // trades swap against a settled view rather than a moving one.
        // Picks up exactly where Act II left the lens, so the boundary
        // between two pinned sections is invisible in the object itself.
        /* Further out than Act II ends, and further than looks right in
         * isolation. This act has a column of type down one side and a mock
         * panel down the other; the object is the backdrop to an argument
         * being made in words, and at a framing that flatters the object the
         * lattice runs straight through the copy. */
        /* Far enough back that the whole object reads, close enough that it
         * still has presence behind the copy. The scrim in landing.css is
         * what keeps the type legible, so this is free to be framed for the
         * object rather than pulled back until it stops being a problem. */
        : 2.30 + smooth(clamp01(p / 0.28)) * 1.30;
      const inside = distance < 1;

      // Re-rasterise at the lower cap on the way in and the higher one on the
      // way out. Compared against the applied value so this costs one integer
      // test per frame and reallocates the drawing buffer twice per visit.
      const wantCap = inside ? 1.5 : 2;
      if (wantCap !== dprCap) { dprCap = wantCap; resize(); }

      // How close the lens is to the shell, 0 away from it and 1 at the
      // moment of crossing. Drives the fades and the surface agitation.
      const crossing = 1 - Math.min(Math.abs(distance - 1) / 0.55, 1);

      /* Orientation.
       *
       * Act I: rotation accelerates as the shell gets close, which is what
       * sells passing through something rather than into a backdrop.
       * Act II: the camera turns to face each cluster as it lands, holding on
       * it while the caption reads, then swinging to the next.
       * Act III: a slow orbit of the finished object.
       */
      let yaw: number;
      let pitch: number;
      if (currentAct === 1) {
        yaw = p * Math.PI * 2.1 + approach * 1.1;
        pitch = -0.32 + p * 0.62;
      } else if (currentAct === 2) {
        // Trails the arrivals slightly: the camera is already turning as a
        // cluster comes in, so it is met rather than waited for.
        const stage = facing(p);
        const from = Math.floor(stage);
        const to = Math.min(from + 1, 5);
        /* Hold, then swing - rather than drifting evenly from one site to the
         * next. Interpolating linearly across the beat means half the act is
         * spent pointed at empty interior between two plates, with nothing
         * on screen but shell. Dwelling for the first third and crossing in
         * the middle puts the camera on a plate whenever there is one worth
         * looking at, and moving only when there is not. */
        const t = smooth(clamp01((stage - from - 0.32) / 0.46));
        yaw = lerpAngle(aimYaw[from], aimYaw[to], t);
        pitch = aimPitch[from] + (aimPitch[to] - aimPitch[from]) * t;
        // Level off for the closing reveal: staring up or down at the last
        // landing site is the wrong angle from which to read six of them.
        const out = finale(p);
        pitch += (-0.22 - pitch) * out;
        yaw += out * 0.8;
      } else {
        yaw = aimYaw[5] + 0.8 + smooth(p) * 2.4;
        pitch = -0.26 + Math.sin(p * Math.PI) * 0.2;
      }
      yaw += pointer.current.x * 0.6;
      pitch += pointer.current.y * 0.4;

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

      /* Where each cluster is this frame, and how lit.
       *
       * Act I has none of them - the core is still just a core. Act II flies
       * them in one at a time. Act III holds them all on the skeleton and
       * lights the subset the current trade uses.
       */
      const lit = litRef.current;
      let anyModule = false;
      for (let i = 0; i < 6; i++) {
        const t = currentAct === 1 ? 0 : currentAct === 2 ? arrival(i, p) : 1;
        moduleT[i] = t;
        if (t > 0) anyModule = true;
        moduleLit[i] = currentAct === 3 && lit ? (lit[i] ? 1 : 0) : 1;
        for (let k = 0; k < 3; k++) {
          const from = modules.origins[i * 3 + k];
          const to = modules.anchors[i * 3 + k];
          modulePos[i * 3 + k] = from + (to - from) * t;
        }
      }

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
      /* Act II dims the shell hard. It is the same geometry either way, but
       * once the plates arrive the shell is the room rather than the subject,
       * and at full strength its edges are brighter and far more numerous
       * than the thing the act is actually about. */
      const shellAlpha =
        0.55 * (1 - crossing * 0.72) *
        (currentAct === 2 ? 0.42 : currentAct === 3 ? 0.8 : 1);

      gl.uniform1f(loc.sphereAlpha, shellAlpha);
      gl.drawElements(gl.LINES, edges.length, gl.UNSIGNED_SHORT, 0);

      // Vertices again as points, brighter, so the nodes read as lit. Inside
      // the shell they are all around the camera, so they are dimmed too.
      gl.uniform1f(loc.sphereAlpha, inside ? 0.5 : 0.95 * (1 - crossing * 0.5));
      gl.uniform3fv(loc.sphereFar, MAGENTA);
      gl.drawArrays(gl.POINTS, 0, positions.length / 3);

      // ── Module clusters and their links to the core ─────────────────
      if (anyModule) {
        gl.useProgram(moduleProgram);
        gl.uniformMatrix4fv(loc.modProj, false, projection);
        gl.uniformMatrix4fv(loc.modView, false, view);
        gl.uniform3fv(loc.modPos, modulePos);
        gl.uniform1fv(loc.modT, moduleT);
        gl.uniform1fv(loc.modLit, moduleLit);
        gl.uniform3fv(loc.modWarm, MAGENTA);
        gl.uniform3fv(loc.modCool, ELECTRIC);

        const stride = MODULE_STRIDE * 4;
        const bindModuleAttribs = () => {
          gl.enableVertexAttribArray(loc.modLocal);
          gl.vertexAttribPointer(loc.modLocal, 3, gl.FLOAT, false, stride, 0);
          gl.enableVertexAttribArray(loc.modIndex);
          gl.vertexAttribPointer(loc.modIndex, 1, gl.FLOAT, false, stride, 12);
          gl.enableVertexAttribArray(loc.modCore);
          gl.vertexAttribPointer(loc.modCore, 1, gl.FLOAT, false, stride, 16);
        };

        // Wireframe first so the lit vertices sit on top of their own edges.
        gl.bindBuffer(gl.ARRAY_BUFFER, moduleLineBuffer);
        bindModuleAttribs();
        gl.drawArrays(gl.LINES, 0, modules.lineCount);

        gl.bindBuffer(gl.ARRAY_BUFFER, modulePointBuffer);
        bindModuleAttribs();
        gl.drawArrays(gl.POINTS, 0, modules.pointCount);

        // The sphere program owns attribute 0 on the next frame; leaving the
        // module attributes enabled would have it read from the wrong buffer.
        gl.disableVertexAttribArray(loc.modIndex);
        gl.disableVertexAttribArray(loc.modCore);
      }

      /* Captions ride their landing sites.
       *
       * Projected here rather than in React: this is a 3D point being turned
       * into a 2D one every frame, and the only honest place for that is
       * beside the matrices that define it. Written as transform and opacity,
       * which the compositor can take without a layout.
       */
      const captions = captionRefs?.current;
      if (captions && currentAct === 2) {
        for (let i = 0; i < 6; i++) {
          const el = captions[i];
          if (!el) continue;

          // The cluster's position this frame, not its landing site: the
          // caption starts fading in before the cluster has finished its
          // approach, and pinning it to the destination would leave it
          // hanging in empty space until the thing it labels caught up.
          const ax = modulePos[i * 3];
          const ay = modulePos[i * 3 + 1];
          const az = modulePos[i * 3 + 2];

          // view then projection, by hand - column-major, so a row of the
          // matrix is every fourth element starting at the row index.
          const vx = view[0] * ax + view[4] * ay + view[8] * az + view[12];
          const vy = view[1] * ax + view[5] * ay + view[9] * az + view[13];
          const vz = view[2] * ax + view[6] * ay + view[10] * az + view[14];
          const cw = -vz; // the projection's w is -z for this matrix form
          const cx = projection[0] * vx;
          const cy = projection[5] * vy;

          // Fade in as it seats, out as the next one starts its approach.
          /* Fades in as the plate seats and holds until the next one is well
           * into its approach. Keyed off the next arrival rather than a timer
           * so it cannot desync from the thing it is labelling - but starting
           * that fade at the first frame of the next approach left every
           * caption legible for only a moment. */
          const next = i < 5 ? moduleT[i + 1] : 0;
          /* Also cleared by the closing pull-back. The sixth caption has no
           * successor to fade it, so it stayed lit through the reveal and
           * then rode the section off the top of the viewport - which is the
           * one shot the act should end on with nothing but the object. */
          const show =
            clamp01((moduleT[i] - 0.5) / 0.28) *
            (1 - clamp01((next - 0.34) / 0.42)) *
            (1 - finale(p));

          if (cw <= 0.05 || show <= 0.01) {
            el.style.opacity = '0';
            continue;
          }
          /* Kept inside the frame. The camera aims at each cluster as it
           * lands, so this almost never binds - but "almost never" over six
           * arrivals and every viewport size is not the same as never, and a
           * caption half off the right edge is worse than one nudged in. */
          // Room for the offset as well as the card, or clamping to the edge
          // just moves the overflow rather than preventing it.
          const card = Math.min(box.width * 0.42, 380) + 130;
          const sx = Math.min(Math.max((cx / cw * 0.5 + 0.5) * box.width, 24), box.width - card);
          // The card hangs from -44px to about +100px around the anchor, so
          // the bottom bound has to leave room for the copy, not just the
          // point it is pinned to.
          const sy = Math.min(Math.max((0.5 - cy / cw * 0.5) * box.height, 120), box.height - 140);
          el.style.opacity = show.toFixed(3);
          el.style.transform = `translate3d(${sx.toFixed(1)}px, ${sy.toFixed(1)}px, 0)`;
        }
      }

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
      gl.deleteBuffer(modulePointBuffer);
      gl.deleteBuffer(moduleLineBuffer);
      gl.deleteProgram(sphereProgram);
      gl.deleteProgram(particleProgram);
      gl.deleteProgram(moduleProgram);
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
