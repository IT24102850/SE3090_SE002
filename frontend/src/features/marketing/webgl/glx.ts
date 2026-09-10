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
