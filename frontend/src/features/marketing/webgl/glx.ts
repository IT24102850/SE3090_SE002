/* Minimal WebGL helpers and 4x4 matrix maths.
 *
 * Hand-written rather than pulled from three.js / gl-matrix because this
 * environment's npm registry answers 403 for every package. That turns out
 * fine: the hero scene needs a perspective matrix, a look-at, two rotations
 * and a shader compiler, which is a couple of hundred lines - importing a
 * 600KB engine to draw one lit wireframe would have been the wrong trade even
 * with a working registry.
 *
 * Column-major throughout, matching what WebGL's uniformMatrix4fv expects
 * with `transpose = false`.
 */

export type Mat4 = Float32Array;

export function mat4(): Mat4 {
  const m = new Float32Array(16);
  m[0] = m[5] = m[10] = m[15] = 1;
  return m;
}

export function perspective(fovY: number, aspect: number, near: number, far: number): Mat4 {
  const f = 1 / Math.tan(fovY / 2);
  const nf = 1 / (near - far);
  const m = new Float32Array(16);
  m[0] = f / aspect;
  m[5] = f;
  m[10] = (far + near) * nf;
  m[11] = -1;
  m[14] = 2 * far * near * nf;
  return m;
}

export function multiply(a: Mat4, b: Mat4): Mat4 {
  const out = new Float32Array(16);
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) {
      out[c * 4 + r] =
        a[r] * b[c * 4] +
        a[4 + r] * b[c * 4 + 1] +
        a[8 + r] * b[c * 4 + 2] +
        a[12 + r] * b[c * 4 + 3];
    }
  }
  return out;
}

export function translate(x: number, y: number, z: number): Mat4 {
  const m = mat4();
  m[12] = x; m[13] = y; m[14] = z;
  return m;
}

export function rotateX(rad: number): Mat4 {
  const m = mat4();
  const c = Math.cos(rad); const s = Math.sin(rad);
  m[5] = c; m[6] = s; m[9] = -s; m[10] = c;
  return m;
}

export function rotateY(rad: number): Mat4 {
  const m = mat4();
  const c = Math.cos(rad); const s = Math.sin(rad);
  m[0] = c; m[2] = -s; m[8] = s; m[10] = c;
  return m;
}

export function rotateZ(rad: number): Mat4 {
  const m = mat4();
  const c = Math.cos(rad); const s = Math.sin(rad);
  m[0] = c; m[1] = s; m[4] = -s; m[5] = c;
  return m;
}

/* ── Shader plumbing ──────────────────────────────────────────────── */

function compile(gl: WebGLRenderingContext, type: number, source: string): WebGLShader | null {
  const shader = gl.createShader(type);
  if (!shader) return null;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    // Logged rather than thrown: a shader that fails to compile should cost
    // the visitor a background graphic, not the whole page.
    console.warn('[glx] shader compile failed:', gl.getShaderInfoLog(shader));
    gl.deleteShader(shader);
    return null;
  }
  return shader;
}

export function createProgram(
  gl: WebGLRenderingContext,
  vertexSource: string,
  fragmentSource: string,
): WebGLProgram | null {
  const vs = compile(gl, gl.VERTEX_SHADER, vertexSource);
  const fs = compile(gl, gl.FRAGMENT_SHADER, fragmentSource);
  if (!vs || !fs) return null;

  const program = gl.createProgram();
  if (!program) return null;
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);

  // The shaders are linked into the program now; the objects themselves are
  // no longer needed and would otherwise leak for the page's lifetime.
  gl.deleteShader(vs);
  gl.deleteShader(fs);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.warn('[glx] program link failed:', gl.getProgramInfoLog(program));
    gl.deleteProgram(program);
    return null;
  }
  return program;
}

export function buffer(gl: WebGLRenderingContext, data: Float32Array): WebGLBuffer | null {
  const buf = gl.createBuffer();
  if (!buf) return null;
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  return buf;
}

/* ── Geometry ─────────────────────────────────────────────────────── */

export interface Icosphere {
  /** xyz triples, unit length. */
  positions: Float32Array;
  /** Index pairs into positions, one pair per wireframe edge. */
  edges: Uint16Array;
}

/**
 * A geodesic sphere built by subdividing an icosahedron.
 *
 * Chosen over a UV sphere because its triangles are near-uniform: a UV
 * sphere bunches its wireframe at the poles, which reads as a defect rather
 * than a design once the thing is rotating.
 *
 * `subdivisions` of 2 gives 320 faces - dense enough to read as a sphere,
 * sparse enough that every edge stays individually visible.
 */
export function icosphere(subdivisions = 2): Icosphere {
  const t = (1 + Math.sqrt(5)) / 2;
  let verts: number[][] = [
    [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
    [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
    [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
  ];
  let faces: number[][] = [
    [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
    [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
    [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
    [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
  ];

  // Cache by edge key so a shared edge yields one vertex, not two - without
  // it the sphere cracks apart at every seam.
  for (let s = 0; s < subdivisions; s++) {
    const midpoints = new Map<string, number>();
    const next: number[][] = [];

    const midpoint = (a: number, b: number): number => {
      const key = a < b ? `${a}_${b}` : `${b}_${a}`;
      const cached = midpoints.get(key);
      if (cached !== undefined) return cached;
      const va = verts[a]; const vb = verts[b];
      verts.push([(va[0] + vb[0]) / 2, (va[1] + vb[1]) / 2, (va[2] + vb[2]) / 2]);
      const index = verts.length - 1;
      midpoints.set(key, index);
      return index;
    };

    for (const [a, b, c] of faces) {
      const ab = midpoint(a, b);
      const bc = midpoint(b, c);
      const ca = midpoint(c, a);
      next.push([a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]);
    }
    faces = next;
  }

  // Push every vertex out to unit length - subdivision produces midpoints
  // inside the sphere, and without this the form is a faceted lump.
  verts = verts.map(([x, y, z]) => {
    const len = Math.hypot(x, y, z) || 1;
    return [x / len, y / len, z / len];
  });

  const positions = new Float32Array(verts.length * 3);
  verts.forEach(([x, y, z], i) => {
    positions[i * 3] = x;
    positions[i * 3 + 1] = y;
    positions[i * 3 + 2] = z;
  });

  // Deduplicate edges: each interior edge is shared by two faces, and drawing
  // it twice doubles the line count for no visible gain.
  const seen = new Set<string>();
  const edgeList: number[] = [];
  for (const [a, b, c] of faces) {
    for (const [p, q] of [[a, b], [b, c], [c, a]]) {
      const key = p < q ? `${p}_${q}` : `${q}_${p}`;
      if (seen.has(key)) continue;
      seen.add(key);
      edgeList.push(p, q);
    }
  }

  return { positions, edges: new Uint16Array(edgeList) };
}

/** A shell of points at random directions, between two radii. Used for the
 *  drifting field behind the sphere. */
export function particleShell(count: number, innerRadius: number, outerRadius: number): Float32Array {
  const data = new Float32Array(count * 4); // xyz + a per-particle seed
  for (let i = 0; i < count; i++) {
    // Rejection-free uniform direction: acos of a uniform z avoids the
    // clustering at the poles that naive theta/phi sampling produces.
    const z = Math.random() * 2 - 1;
    const theta = Math.random() * Math.PI * 2;
    const r = Math.sqrt(1 - z * z);
    const radius = innerRadius + Math.random() * (outerRadius - innerRadius);
    data[i * 4] = Math.cos(theta) * r * radius;
    data[i * 4 + 1] = Math.sin(theta) * r * radius;
    data[i * 4 + 2] = z * radius;
    data[i * 4 + 3] = Math.random();
  }
  return data;
}

/* ── Module clusters ──────────────────────────────────────────────── */

export interface ModuleGeometry {
  /** Interleaved: local xyz, module index, core-end flag. 5 floats/vertex. */
  points: Float32Array;
  /** Same layout. Cluster edges plus one tether per cluster back to the core. */
  lines: Float32Array;
  /** Unit directions the clusters lock onto, 3 floats each. */
  anchors: Float32Array;
  /** Where each cluster starts, off-camera. 3 floats each. */
  origins: Float32Array;
  pointCount: number;
  lineCount: number;
}

/** Floats per vertex in both buffers above. */
export const MODULE_STRIDE = 5;

/**
 * Six module plates, each with a landing site on the unit sphere and a start
 * position off-camera.
 *
 * Each plate is two concentric rings around a hub, wired up - not a cloud of
 * random points. A scatter reads as dust at the distances this is seen from;
 * a ring with spokes reads as a made thing arriving, which is the whole claim
 * of the act. The plate is built in the tangent plane at its landing site, so
 * it lies flat on the shell instead of hanging at whatever angle the local
 * axes happened to give it.
 *
 * Positions animate by uniform, not by re-upload: the vertex shader adds its
 * cluster's current centre to a fixed local offset, so moving six plates
 * costs eighteen floats a frame rather than rewriting the buffer.
 */
export function moduleClusters(count = 6): ModuleGeometry {
  const OUTER = 9;
  const INNER = 5;
  // Sized against where they are seen from: a plate seats about 1.4 units
  // from the lens, so this is roughly 120px across on a 900px-tall viewport.
  const R_OUTER = 0.155;
  const R_INNER = 0.072;
  const perCluster = OUTER + INNER + 1; // + the hub

  const edgesPer = OUTER + INNER + INNER + INNER; // rims, spokes out, spokes in
  const points = new Float32Array(count * perCluster * MODULE_STRIDE);
  const lines = new Float32Array(count * (edgesPer + 1) * 2 * MODULE_STRIDE);
  const anchors = new Float32Array(count * 3);
  const origins = new Float32Array(count * 3);

  const golden = Math.PI * (3 - Math.sqrt(5));
  let p = 0;
  let l = 0;

  for (let i = 0; i < count; i++) {
    // Fibonacci lattice: y walks evenly down the axis while longitude turns
    // by the golden angle, which is what stops successive sites lining up.
    const y = 1 - (i / (count - 1)) * 2;
    const ring = Math.sqrt(Math.max(0, 1 - y * y));
    const theta = golden * i;
    const ax = Math.cos(theta) * ring;
    const az = Math.sin(theta) * ring;

    anchors[i * 3] = ax;
    anchors[i * 3 + 1] = y;
    anchors[i * 3 + 2] = az;

    // Start well outside the shell, thrown off the landing axis so the six
    // approaches are visibly different rather than six radial zooms.
    const swing = ((i % 3) - 1) * 2.4;
    origins[i * 3] = ax * 5.4 + swing;
    origins[i * 3 + 1] = y * 5.4 - swing * 0.5;
    origins[i * 3 + 2] = az * 5.4 - swing;

    /* Tangent basis at the landing site. The helper axis is swapped near the
     * poles because the cross product collapses when it is parallel to the
     * normal, which would flatten the plate to a line at exactly the two
     * sites the Fibonacci lattice always puts there. */
    const hx = Math.abs(y) < 0.9 ? 0 : 1;
    const hy = Math.abs(y) < 0.9 ? 1 : 0;
    let ux = hy * az - 0 * y;
    let uy = 0 * ax - hx * az;
    let uz = hx * y - hy * ax;
    const ul = Math.hypot(ux, uy, uz) || 1;
    ux /= ul; uy /= ul; uz /= ul;
    const vx = y * uz - az * uy;
    const vy = az * ux - ax * uz;
    const vz = ax * uy - y * ux;

    /** A point in the plate's own plane, as a local offset in world axes. */
    const plate = (radius: number, angle: number, lift: number) => {
      const a = Math.cos(angle) * radius;
      const b = Math.sin(angle) * radius;
      return [
        ux * a + vx * b + ax * lift,
        uy * a + vy * b + y * lift,
        uz * a + vz * b + az * lift,
      ];
    };

    // Hub first, then the inner ring, then the outer: index 0 is the hub.
    const local: number[][] = [plate(0, 0, 0.02)];
    for (let n = 0; n < INNER; n++) local.push(plate(R_INNER, (n / INNER) * Math.PI * 2, 0.012));
    for (let n = 0; n < OUTER; n++) local.push(plate(R_OUTER, (n / OUTER) * Math.PI * 2, 0));

    for (const [lx, ly, lz] of local) {
      points[p++] = lx; points[p++] = ly; points[p++] = lz;
      points[p++] = i; points[p++] = 0;
    }

    const edge = (a: number[], b: number[]) => {
      lines[l++] = a[0]; lines[l++] = a[1]; lines[l++] = a[2]; lines[l++] = i; lines[l++] = 0;
      lines[l++] = b[0]; lines[l++] = b[1]; lines[l++] = b[2]; lines[l++] = i; lines[l++] = 0;
    };

    const innerAt = (n: number) => local[1 + (n % INNER)];
    const outerAt = (n: number) => local[1 + INNER + (n % OUTER)];

    for (let n = 0; n < OUTER; n++) edge(outerAt(n), outerAt(n + 1));
    for (let n = 0; n < INNER; n++) edge(innerAt(n), innerAt(n + 1));
    for (let n = 0; n < INNER; n++) edge(local[0], innerAt(n));
    // Spokes out to the rim, spaced so they do not all land on one side.
    for (let n = 0; n < INNER; n++) edge(innerAt(n), outerAt(Math.round((n * OUTER) / INNER)));

    // The tether: plate hub, then the core at the origin. The second vertex
    // carries the core flag, which the shader reads as "ignore the centre".
    lines[l++] = 0; lines[l++] = 0; lines[l++] = 0; lines[l++] = i; lines[l++] = 0;
    lines[l++] = 0; lines[l++] = 0; lines[l++] = 0; lines[l++] = i; lines[l++] = 1;
  }

  return {
    points, lines, anchors, origins,
    pointCount: count * perCluster,
    lineCount: count * (edgesPer + 1) * 2,
  };
}
