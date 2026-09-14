// Unify — warm near-black UI kit, built to the reference dashboard.
// Flat near-black canvas (no gradient wash), warm orange accent, low-contrast
// charcoal cards, icon rail, and the reference's micro-chart family.
// Structure and nav still come from the real app: AppLayout.tsx NAV_ITEMS,
// tokens.css sidebar/logout values, public/unify-logo.svg.

export const T = {
  bg: '#0A0A0B',          // flat canvas — no gradient
  hero: '#0E0D0D',        // hero panel base
  card: 'rgba(255,255,255,0.042)',
  cardSolid: '#161618',
  line: 'rgba(255,255,255,0.07)',
  lineSoft: 'rgba(255,255,255,0.045)',
  accent: '#FF6B2C',      // warm orange — primary
  accent2: '#FFC940',     // chart yellow
  accentDim: '#FF5A1F',
  good: '#4ADE80',
  warn: '#FBBF24',
  crit: '#F87171',
  cool: '#7DD3FC',
  ink: '#FFFFFF',
  dim: '#9A9A9F',
  faint: '#6B6B70',
  font: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
};

export const TONES = {
  orange: T.accent, yellow: T.accent2, green: T.good, amber: T.warn,
  red: T.crit, cool: T.cool, slate: T.dim, white: '#E8E8EA',
};

// Flat charcoal surface. Barely-there border, no heavy blur, no glow wash.
export const surf = (radius = 18) =>
  `background:${T.card};border:1px solid ${T.line};border-radius:${radius}px;` +
  `backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px);`;

let uid = 0;
const nid = (p) => `${p}${++uid}`;

// ── Icons ────────────────────────────────────────────────────────────────
const P = {
  home: 'M4 10.5L12 4l8 6.5V20a1 1 0 01-1 1h-4v-6H9v6H5a1 1 0 01-1-1z',
  calendar: 'M3 6a2 2 0 012-2h14a2 2 0 012 2v13a2 2 0 01-2 2H5a2 2 0 01-2-2zM3 9h18M8 3v4M16 3v4',
  building: 'M4 21V5a1 1 0 011-1h9a1 1 0 011 1v16M15 21V9h4a1 1 0 011 1v11M4 21h17M8 8h3M8 12h3M8 16h3',
  box: 'M21 8.5v7l-9 5-9-5v-7l9-5zM3.2 7.9L12 13l8.8-5.1M12 13v7.5',
  chart: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
  gear: 'M12 15.2a3.2 3.2 0 100-6.4 3.2 3.2 0 000 6.4M19.4 14.5l1.6 1.2-1.8 3.1-1.9-.7a7.6 7.6 0 01-1.8 1l-.3 2h-3.6l-.3-2a7.6 7.6 0 01-1.8-1l-1.9.7-1.8-3.1 1.6-1.2a7.7 7.7 0 010-2l-1.6-1.2 1.8-3.1 1.9.7a7.6 7.6 0 011.8-1l.3-2h3.6l.3 2c.64.25 1.24.59 1.8 1l1.9-.7 1.8 3.1-1.6 1.2c.07.66.07 1.34 0 2z',
  layers: 'M12 3l8 4.5-8 4.5-8-4.5zM4 12l8 4.5 8-4.5M4 16.5L12 21l8-4.5',
  spark: 'M12 3l1.9 4.8L19 9.6l-4.2 3.2L15.6 18 12 15.2 8.4 18l.8-5.2L5 9.6l5.1-1.8z',
  tag: 'M3 12.5V5a2 2 0 012-2h7.5L21 11.5 13.5 19zM8 8h.01',
  users: 'M16 20v-1.5a4 4 0 00-4-4H7a4 4 0 00-4 4V20M9.5 10.5a3.5 3.5 0 100-7 3.5 3.5 0 000 7M21 20v-1.5a4 4 0 00-3-3.8M16.5 3.9a4 4 0 010 7.2',
  pin: 'M12 21s7-5.6 7-11a7 7 0 10-14 0c0 5.4 7 11 7 11zM12 12.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5',
  store: 'M3 9l1.5-5h15L21 9M3 9v11h18V9M3 9h18M9 20v-6h6v6',
  swap: 'M4 8h13l-3.5-3.5M20 16H7l3.5 3.5',
  receipt: 'M6 3h12v18l-3-2-3 2-3-2-3 2zM9.5 8h5M9.5 12h5',
  alert: 'M12 4.2L2.8 20h18.4zM12 10v4M12 17.2h.01',
  branches: 'M3 20V8l6-4 6 4v12M15 20V11l6 3.2V20M3 20h18M7 12h2M7 16h2',
  satellite: 'M12 12a5 5 0 015 5M12 8a9 9 0 019 9M6.5 17.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0M5 5l4 4M9 5L5 9',
  analytics: 'M4 19h16M6.5 16V9.5M11 16V5M15.5 16v-4M20 16v-8',
  search: 'M11 19a8 8 0 100-16 8 8 0 000 16zM21 21l-3.6-3.6',
  edit: 'M4 20h4L19 9a2.1 2.1 0 00-3-3L5 17z',
  chevron: 'M9 6l6 6-6 6',
  plus: 'M12 5v14M5 12h14',
  clock: 'M12 21a9 9 0 100-18 9 9 0 000 18zM12 7.5V12l3 1.8',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  bed: 'M3 18v-9M3 13h18v5M3 18h18M7.5 10.5h3.2a2 2 0 012 2v.5h-7.2v-.5a2 2 0 012-2z',
  surf: 'M5 20c3-6 7.5-12.5 13.5-16C19.5 10.5 14 18 5 20zM5 20l3.5-3',
  car: 'M4.5 16.5h15M6 16.5v2h2.5v-2M15.5 16.5v2H18v-2M4.5 16.5l1.6-5.4A2 2 0 018 9.6h8a2 2 0 011.9 1.5l1.6 5.4M7.5 13.5h.01M16.5 13.5h.01',
  boat: 'M4 17l1.5-5h13L20 17M8 12V6h8v6M12 6V3M3 20c1.6 0 1.6-1 3.2-1s1.6 1 3.2 1 1.6-1 3.2-1 1.6 1 3.2 1 1.6-1 3.2-1',
  bell: 'M18 9a6 6 0 10-12 0c0 5-2 6-2 6h16s-2-1-2-6M13.7 20a2 2 0 01-3.4 0',
  bars: 'M5 20V12M12 20V5M19 20v-5',
};

export const icon = (n, s = 20, c = 'currentColor', w = 1.7) =>
  `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${P[n]}"></path></svg>`;

export const logo = (size = 34) => {
  const g = nid('ug');
  return `<svg width="${size}" height="${size}" viewBox="0 0 64 64" fill="none" aria-hidden="true">
  <defs><linearGradient id="${g}" x1="8" y1="12" x2="56" y2="52" gradientUnits="userSpaceOnUse">
    <stop offset="0%" stop-color="#FFC940"></stop><stop offset="100%" stop-color="#FF5A1F"></stop></linearGradient></defs>
  <rect width="64" height="64" rx="18" fill="${T.accent}"></rect>
  <path d="M18 18V36C18 43.732 24.268 50 32 50C39.732 50 46 43.732 46 36V18" stroke="#1A0B04" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"></path>
  <circle cx="32" cy="36" r="3.5" fill="#1A0B04"></circle>
</svg>`;
};

// ── Navigation ───────────────────────────────────────────────────────────
// All 18 NAV_ITEMS from AppLayout.tsx, grouped so the rail stays narrow like
// the reference without losing a single destination.
export const GROUPS = [
  { key: 'home', ic: 'home', name: 'Overview', items: ['Dashboard'] },
  { key: 'book', ic: 'calendar', name: 'Bookings', items: ['Booking Manager', 'Multi-Branch Schedule', 'Booking Types', 'AI Planner', 'Agent Workflows'] },
  { key: 'res', ic: 'building', name: 'Resources', items: ['Resource Manager', 'Staff', 'Branches'] },
  { key: 'inv', ic: 'box', name: 'Inventory', items: ['Inventory Manager', 'Stock Movements', 'Purchase Orders', 'Low Stock Alerts', 'Inventory Analytics'] },
  { key: 'ins', ic: 'chart', name: 'Insights', items: ['Reports', 'Branch Overview'] },
  { key: 'set', ic: 'gear', name: 'Settings', items: ['Business Profile', 'Business Settings'] },
];
const ITEM_ICON = {
  'Dashboard': 'home', 'Booking Manager': 'calendar', 'Multi-Branch Schedule': 'layers',
  'Booking Types': 'tag', 'AI Planner': 'spark', 'Agent Workflows': 'satellite',
  'Resource Manager': 'building', 'Staff': 'users', 'Branches': 'pin',
  'Inventory Manager': 'box', 'Stock Movements': 'swap', 'Purchase Orders': 'receipt',
  'Low Stock Alerts': 'alert', 'Inventory Analytics': 'analytics',
  'Reports': 'chart', 'Branch Overview': 'branches',
  'Business Profile': 'store', 'Business Settings': 'gear',
};
export const groupOf = (page) => GROUPS.find((g) => g.items.includes(page)) || GROUPS[0];

// The rail: circular icon buttons, active one filled light like the reference.
export const rail = (activePage) => {
  const active = groupOf(activePage).key;
  const btn = (g) => {
    const on = g.key === active;
    return `<div style="width:42px;height:42px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;${on
      ? `background:#F2F2F3;color:#0A0A0B;box-shadow:0 4px 18px -4px rgba(0,0,0,0.9)`
      : `background:rgba(255,255,255,0.05);border:1px solid ${T.line};color:#B4B4B8`}">${icon(g.ic, 18, 'currentColor', on ? 1.9 : 1.6)}</div>`;
  };
  return `<div style="position:absolute;left:0;top:0;bottom:0;width:76px;display:flex;flex-direction:column;align-items:center;padding:18px 0 20px;gap:10px;z-index:5">
  <div style="margin-bottom:8px">${logo(38)}</div>
  ${GROUPS.map(btn).join('')}
  <div style="margin-top:auto;width:42px;height:42px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700;color:#fff;background:linear-gradient(140deg,${T.accent2},${T.accentDim});flex-shrink:0">SH</div>
</div>`;
};

// The flyout that proves the grouping loses nothing: every item in a section.
export const flyout = (activePage) => {
  const g = groupOf(activePage);
  return `<div style="position:absolute;left:76px;top:78px;width:214px;padding:12px;${surf(16)}background:#141416;z-index:6;box-shadow:0 24px 60px -20px rgba(0,0,0,0.95)">
  <div style="font-size:9.5px;color:${T.faint};font-weight:700;letter-spacing:0.09em;text-transform:uppercase;padding:2px 8px 9px">${g.name}</div>
  <div style="display:flex;flex-direction:column;gap:2px">
    ${g.items.map((it) => {
    const on = it === activePage;
    return `<div style="display:flex;align-items:center;gap:9px;padding:8px 9px;border-radius:10px;font-size:12px;${on
      ? `background:${T.accent}1F;color:${T.accent};font-weight:650`
      : `color:#B4B4B8;font-weight:500`}">
      <span style="display:flex;flex-shrink:0;opacity:${on ? 1 : 0.6}">${icon(ITEM_ICON[it], 15, 'currentColor', 1.6)}</span>
      <span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${it}</span></div>`;
  }).join('')}
  </div>
</div>`;
};

// ── Hero ─────────────────────────────────────────────────────────────────
// Grain + a single warm off-centre light, no colour wash. The reference gets
// its depth from a darkened photograph; with no photo to embed, this is a
// textured dark plate rather than a fabricated image.
const grain = (op = 0.32) => {
  const f = nid('gr');
  return `<svg style="position:absolute;inset:0;width:100%;height:100%;opacity:${op};mix-blend-mode:overlay;pointer-events:none" aria-hidden="true">
  <filter id="${f}"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" stitchTiles="stitch"></feTurbulence></filter>
  <rect width="100%" height="100%" filter="url(#${f})"></rect></svg>`;
};

export const topbar = (page, section) => `<div style="display:flex;align-items:flex-start;justify-content:space-between;gap:24px;position:relative;z-index:3">
  <div style="width:200px;flex-shrink:0;padding-top:3px">
    <div style="font-size:15px;font-weight:700;color:${T.ink};letter-spacing:-0.025em">Unify</div>
    <div style="font-size:11.5px;color:${T.dim};margin-top:2px">${section}</div>
  </div>
  <div style="display:flex;align-items:center;gap:12px;flex-shrink:0">
    <div style="width:36px;height:36px;border-radius:50%;background:rgba(255,255,255,0.06);border:1px solid ${T.line};display:flex;align-items:center;justify-content:center;color:#D4D4D8">${icon('plus', 17, 'currentColor', 2)}</div>
    <div style="display:flex;align-items:center;gap:10px">
      <span style="width:38px;height:38px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:12.5px;font-weight:700;color:#fff;background:linear-gradient(140deg,${T.accent2},${T.accentDim})">SH</span>
      <span>
        <div style="font-size:12.5px;color:${T.ink};font-weight:650;letter-spacing:-0.015em">Sakun Hansaka</div>
        <div style="font-size:11px;color:${T.dim};margin-top:1px">Admin</div>
      </span>
    </div>
  </div>
</div>`;

// The floating pill toolbar that sits at the foot of the hero.
export const toolbar = (action, range = '1 – 8 Sep, 2026') => `<div style="display:flex;align-items:center;gap:9px;position:relative;z-index:3">
  ${[['search'], ['edit']].map(([i]) => `<div style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,0.07);border:1px solid ${T.line};display:flex;align-items:center;justify-content:center;color:#D4D4D8;flex-shrink:0">${icon(i, 15, 'currentColor', 1.7)}</div>`).join('')}
  <div style="display:flex;align-items:center;gap:8px;height:34px;padding:0 13px;border-radius:999px;background:rgba(255,255,255,0.07);border:1px solid ${T.line};font-size:11.5px;color:#D4D4D8;white-space:nowrap">
    ${icon('calendar', 14, T.dim, 1.7)}<span>${range}</span>${icon('chevron', 12, T.faint, 2)}
  </div>
  <div style="display:flex;align-items:center;gap:6px;height:34px;padding:0 14px;border-radius:999px;background:rgba(255,255,255,0.07);border:1px solid ${T.line};font-size:11.5px;color:#D4D4D8;white-space:nowrap">
    ${icon('plus', 14, 'currentColor', 2)}<span>${action}</span>
  </div>
  <div style="display:flex;align-items:center;height:34px;padding:0 15px;border-radius:999px;background:${T.accent};color:#160800;font-size:11.5px;font-weight:700;white-space:nowrap">Create a Report</div>
</div>`;

// tall = the Dashboard's full-height hero; short = every inner page.
export const heroPanel = (page, section, action, tall = false) => {
  const h = tall ? 302 : 176;
  return `<div style="position:relative;height:${h}px;flex-shrink:0;border-radius:20px;overflow:hidden;background:${T.hero};border:1px solid ${T.line};display:flex;flex-direction:column;justify-content:space-between;padding:18px 22px">
  <div style="position:absolute;top:-40%;left:50%;transform:translateX(-50%);width:78%;height:180%;background:radial-gradient(ellipse at center, rgba(255,150,80,0.10), transparent 62%);pointer-events:none"></div>
  <div style="position:absolute;inset:0;background:radial-gradient(ellipse at 50% 120%, rgba(0,0,0,0.55), transparent 60%);pointer-events:none"></div>
  ${grain()}
  ${topbar(page, section)}
  <div style="text-align:center;position:relative;z-index:3;margin:${tall ? '2px 0 6px' : '-6px 0 0'}">
    <div style="font-size:${tall ? 27 : 21}px;font-weight:700;color:${T.ink};letter-spacing:-0.03em;line-height:1.2">Hey, Need help?</div>
    <div style="font-size:${tall ? 35 : 26}px;font-weight:500;color:rgba(255,255,255,0.5);letter-spacing:-0.035em;line-height:1.25;margin-top:${tall ? 5 : 3}px">
      <span style="display:inline-block;width:2px;height:${tall ? 30 : 22}px;background:${T.accent};vertical-align:-4px;margin-right:3px"></span>Just ask me anything
    </div>
  </div>
  <div style="display:flex;justify-content:flex-end">${toolbar(action)}</div>
</div>`;
};

// ── Card ─────────────────────────────────────────────────────────────────
export const card = (body, { pad = 16, radius = 18, grow = false, style = '' } = {}) =>
  `<div style="${surf(radius)}padding:${pad}px;${grow ? 'flex-grow:1;' : ''}min-width:0;display:flex;flex-direction:column;${style}">${body}</div>`;

// Icon chip + title on the left, muted meta on the right — the reference's
// card header exactly.
export const cardHead = (title, meta = '', ic = '', tone = 'orange') => {
  const c = TONES[tone];
  return `<div style="display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:14px;flex-shrink:0">
  <span style="display:flex;align-items:center;gap:10px;min-width:0">
    ${ic ? `<span style="width:30px;height:30px;border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:${c}22;color:${c}">${icon(ic, 16, 'currentColor', 1.8)}</span>` : ''}
    <span style="font-size:13px;font-weight:650;color:${T.ink};letter-spacing:-0.018em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${title}</span>
  </span>
  ${meta ? `<span style="font-size:10.5px;color:${T.faint};white-space:nowrap;flex-shrink:0">${meta}</span>` : ''}
</div>`;
};

// Big value + unit + caption, as under every reference chart.
export const stat = (value, unit, caption, ic = '', tone = 'orange') => `<div style="margin-top:auto;padding-top:12px">
  <div style="display:flex;align-items:baseline;gap:3px;line-height:1">
    <span style="font-size:26px;font-weight:700;color:${T.ink};letter-spacing:-0.04em">${value}</span>
    ${unit ? `<span style="font-size:13px;font-weight:600;color:${T.dim};letter-spacing:-0.02em">${unit}</span>` : ''}
  </div>
  <div style="display:flex;align-items:center;gap:5px;margin-top:6px">
    ${ic ? `<span style="color:${TONES[tone]};display:flex">${icon(ic, 12, 'currentColor', 2)}</span>` : ''}
    <span style="font-size:10.5px;color:${T.faint}">${caption}</span>
  </div>
</div>`;

// The three-part footer on the reference's wide cards.
export const cardFoot = (left, mid, right) => `<div style="display:flex;align-items:flex-end;justify-content:space-between;gap:14px;margin-top:auto;padding-top:14px">
  <span><span style="display:block;font-size:10px;color:${T.faint};margin-bottom:4px">${left[0]}</span><span style="font-size:14.5px;font-weight:650;color:${T.ink};letter-spacing:-0.025em">${left[1]}</span></span>
  <span style="display:flex;flex-direction:column;align-items:center;gap:4px">
    <span style="width:26px;height:26px;border-radius:8px;background:rgba(255,255,255,0.06);border:1px solid ${T.line};display:flex;align-items:center;justify-content:center;color:${T.dim}">${icon('bars', 13, 'currentColor', 1.9)}</span>
    <span style="font-size:9.5px;color:${T.faint}">${mid}</span>
  </span>
  <span style="text-align:right"><span style="display:block;font-size:10px;color:${T.faint};margin-bottom:4px">${right[0]}</span><span style="font-size:14.5px;font-weight:650;color:${T.ink};letter-spacing:-0.025em">${right[1]}</span></span>
</div>`;

// ── Micro-charts (the reference's family) ────────────────────────────────

// Scattered rounded blocks in labelled rows — the "Activity" chart.
export const scatter = (rows, xLabels, w = 232, rowH = 17, gap = 7) => {
  const labW = 74, plotW = w - labW;
  return `<div style="display:flex;flex-direction:column;gap:${gap}px">
  ${rows.map(([label, blocks, tone]) => `<div style="display:flex;align-items:center;gap:8px">
    <span style="width:${labW}px;flex-shrink:0;font-size:9.5px;color:${T.faint};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${label}</span>
    <svg width="${plotW}" height="${rowH}" viewBox="0 0 ${plotW} ${rowH}" fill="none" style="display:block;flex-shrink:0" aria-hidden="true">
      ${blocks.map(([x, hh]) => {
    const bh = hh * rowH, bw = 5;
    return `<rect x="${(x * plotW).toFixed(1)}" y="${((rowH - bh) / 2).toFixed(1)}" width="${bw}" height="${bh.toFixed(1)}" rx="2.5" fill="${TONES[tone]}"></rect>`;
  }).join('')}
    </svg>
  </div>`).join('')}
  <div style="display:flex;gap:8px;margin-top:1px">
    <span style="width:${labW}px;flex-shrink:0"></span>
    <span style="width:${plotW}px;display:flex;justify-content:space-between">
      ${xLabels.map((l) => `<span style="font-size:9px;color:${T.faint}">${l}</span>`).join('')}
    </span>
  </div>
</div>`;
};

const smooth = (pts) => {
  let d = `M${pts[0][0].toFixed(1)},${pts[0][1].toFixed(1)}`;
  for (let i = 1; i < pts.length; i++) {
    const [x0, y0] = pts[i - 1], [x1, y1] = pts[i], cx = (x0 + x1) / 2;
    d += ` C${cx.toFixed(1)},${y0.toFixed(1)} ${cx.toFixed(1)},${y1.toFixed(1)} ${x1.toFixed(1)},${y1.toFixed(1)}`;
  }
  return d;
};

// Two stacked smooth lines with a y-scale — the "Sleep" chart.
export const dualLine = (a, b, yTicks, xLabels, w = 232, h = 62) => {
  const labW = 18, plotW = w - labW;
  const all = [...a, ...b], max = Math.max(...all), min = Math.min(...all), rng = (max - min) || 1;
  const map = (vals) => vals.map((v, i) => [(i / (vals.length - 1)) * plotW, h - 6 - ((v - min) / rng) * (h - 14)]);
  return `<div style="display:flex;flex-direction:column;gap:5px">
  <div style="display:flex;gap:6px">
    <span style="width:${labW - 6}px;height:${h}px;display:flex;flex-direction:column;justify-content:space-between;flex-shrink:0">
      ${yTicks.map((t) => `<span style="font-size:9px;color:${T.faint};line-height:1">${t}</span>`).join('')}
    </span>
    <svg width="${plotW}" height="${h}" viewBox="0 0 ${plotW} ${h}" fill="none" style="display:block" aria-hidden="true">
      <path d="${smooth(map(b))}" stroke="${T.accent2}" stroke-width="2" stroke-linecap="round" fill="none"></path>
      <path d="${smooth(map(a))}" stroke="${T.accent}" stroke-width="2" stroke-linecap="round" fill="none"></path>
    </svg>
  </div>
  <div style="display:flex;gap:6px">
    <span style="width:${labW - 6}px;flex-shrink:0"></span>
    <span style="width:${plotW}px;display:flex;justify-content:space-between">
      ${xLabels.map((l) => `<span style="font-size:9px;color:${T.faint}">${l}</span>`).join('')}
    </span>
  </div>
</div>`;
};

// Per-day stacks of small blocks — the "Heart" chart.
export const blockCols = (data, labels, w = 232, h = 62, hot = []) => {
  const n = data.length, cw = w / n, bw = cw * 0.52, unit = 7, gapY = 2.5;
  return `<div style="display:flex;flex-direction:column;gap:5px">
  <svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" fill="none" style="display:block" aria-hidden="true">
    ${data.map((count, i) => {
    const cx = i * cw + (cw - bw) / 2;
    return Array.from({ length: count }, (_, k) => {
      const y = h - (k + 1) * (unit + gapY);
      return `<rect x="${cx.toFixed(1)}" y="${y.toFixed(1)}" width="${bw.toFixed(1)}" height="${unit}" rx="2.5" fill="${hot.includes(i) ? T.accent2 : T.accent}" opacity="${hot.includes(i) ? 1 : 0.62}"></rect>`;
    }).join('');
  }).join('')}
  </svg>
  <span style="width:${w}px;display:flex">
    ${labels.map((l) => `<span style="flex-grow:1;text-align:center;font-size:9px;color:${T.faint}">${l}</span>`).join('')}
  </span>
</div>`;
};

// Two interleaved waves — the "Wellness Score" chart.
export const dualWave = (w = 420, h = 74) => {
  const wave = (amp, phase, thick, color, op) => {
    const pts = Array.from({ length: 40 }, (_, i) => {
      const x = (i / 39) * w;
      const y = h / 2 + Math.sin(i / 39 * Math.PI * 3 + phase) * amp * Math.sin(i / 39 * Math.PI);
      return [x, y];
    });
    return `<path d="${smooth(pts)}" stroke="${color}" stroke-width="${thick}" stroke-linecap="round" fill="none" opacity="${op}"></path>`;
  };
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" fill="none" style="display:block;width:100%" preserveAspectRatio="none" aria-hidden="true">
    ${wave(h * 0.34, 0, 2, T.accent, 1)}
    ${wave(h * 0.30, Math.PI * 0.7, 2, T.accent2, 0.95)}
    ${wave(h * 0.22, Math.PI * 1.4, 1.4, T.accent, 0.4)}
  </svg>`;
};

// Dense vertical waveform with a playhead — the "Focus Activity" chart.
export const waveform = (n = 76, w = 420, h = 74, head = 0.52) => {
  const gap = w / n;
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" fill="none" style="display:block;width:100%" preserveAspectRatio="none" aria-hidden="true">
    ${Array.from({ length: n }, (_, i) => {
    const t = i / (n - 1);
    const env = Math.sin(t * Math.PI) ** 0.6;
    const bh = Math.max(3, env * h * 0.86 * (0.42 + 0.58 * Math.abs(Math.sin(i * 1.9))));
    const on = Math.abs(t - head) < 0.008;
    return `<rect x="${(i * gap).toFixed(2)}" y="${((h - bh) / 2).toFixed(1)}" width="${(gap * 0.42).toFixed(2)}" height="${bh.toFixed(1)}" rx="${(gap * 0.21).toFixed(2)}" fill="${on ? T.accent2 : 'rgba(255,255,255,0.20)'}"></rect>`;
  }).join('')}
    <rect x="${(w * head).toFixed(1)}" y="2" width="1.6" height="${h - 4}" rx="0.8" fill="${T.accent}"></rect>
  </svg>`;
};

// Semicircular tick gauge with pointer marks — the "Speed" dial.
export const tickGauge = (pct, size = 190, label = '', cap = '') => {
  const n = 46, cx = size / 2, cy = size * 0.62, r = size * 0.42;
  const ticks = Array.from({ length: n }, (_, i) => {
    const t = i / (n - 1), ang = Math.PI + t * Math.PI;
    const on = t <= pct / 100;
    const len = on ? 13 : 9;
    const x1 = cx + Math.cos(ang) * r, y1 = cy + Math.sin(ang) * r;
    const x2 = cx + Math.cos(ang) * (r - len), y2 = cy + Math.sin(ang) * (r - len);
    return `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="${on ? '#F2F2F3' : 'rgba(255,255,255,0.17)'}" stroke-width="${on ? 2 : 1.5}" stroke-linecap="round"></line>`;
  }).join('');
  const mark = (t) => {
    const ang = Math.PI + t * Math.PI;
    const x = cx + Math.cos(ang) * (r + 11), y = cy + Math.sin(ang) * (r + 11);
    return `<path d="M${x.toFixed(1)},${(y - 4).toFixed(1)} l4,-6 l-8,0 z" fill="${T.accent}" transform="rotate(${(t * 180 - 90).toFixed(1)} ${x.toFixed(1)} ${y.toFixed(1)})"></path>`;
  };
  return `<div style="position:relative;width:${size}px;height:${size * 0.72}px;flex-shrink:0">
  <svg width="${size}" height="${size * 0.72}" viewBox="0 0 ${size} ${size * 0.72}" fill="none" style="display:block" aria-hidden="true">
    ${ticks}${mark(pct / 100)}
  </svg>
  <div style="position:absolute;left:0;right:0;top:${size * 0.40}px;text-align:center">
    <span style="font-size:30px;font-weight:700;color:${T.ink};letter-spacing:-0.045em">${label}</span>
  </div>
  ${cap ? `<div style="position:absolute;left:0;right:0;top:${size * 0.15}px;text-align:center;font-size:10px;color:${T.faint}">${cap}</div>` : ''}
</div>`;
};

export const spark = (vals, tone = 'orange', w = 150, h = 34) => {
  const c = TONES[tone], g = nid('sg');
  const max = Math.max(...vals), min = Math.min(...vals), rng = (max - min) || 1;
  const pts = vals.map((v, i) => [(i / (vals.length - 1)) * w, h - 3 - ((v - min) / rng) * (h - 8)]);
  const d = smooth(pts);
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" fill="none" style="display:block" aria-hidden="true">
  <defs><linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="${c}" stop-opacity="0.3"></stop><stop offset="100%" stop-color="${c}" stop-opacity="0"></stop></linearGradient></defs>
  <path d="${d} L${w},${h} L0,${h} Z" fill="url(#${g})"></path>
  <path d="${d}" stroke="${c}" stroke-width="1.9" stroke-linecap="round" fill="none"></path>
  <circle cx="${pts[pts.length - 1][0].toFixed(1)}" cy="${pts[pts.length - 1][1].toFixed(1)}" r="2.6" fill="${c}"></circle>
</svg>`;
};

export const cols = (vals, tone = 'orange', w = 150, h = 34, peak = -1) => {
  const c = TONES[tone], max = Math.max(...vals) || 1;
  const bw = w / (vals.length * 1.7), gap = (w - bw * vals.length) / (vals.length - 1);
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" fill="none" style="display:block" aria-hidden="true">` +
    vals.map((v, i) => {
      const bh = Math.max(3, (v / max) * (h - 4));
      return `<rect x="${(i * (bw + gap)).toFixed(1)}" y="${(h - bh).toFixed(1)}" width="${bw.toFixed(1)}" height="${bh.toFixed(1)}" rx="${(bw / 2.6).toFixed(1)}" fill="${i === peak ? T.accent2 : c}" opacity="${i === peak ? 1 : 0.55}"></rect>`;
    }).join('') + `</svg>`;
};

export const bar = (pct, tone = 'orange', w = '100%', h = 5) => {
  const c = TONES[tone];
  return `<span style="display:block;width:${w};height:${h}px;border-radius:999px;background:rgba(255,255,255,0.09);overflow:hidden">
  <span style="display:block;width:${pct}%;height:100%;border-radius:999px;background:${c}"></span></span>`;
};

export const donut = (pct, tone = 'orange', size = 92, thick = 8, label = '', sub = '') => {
  const c = TONES[tone], r = (size - thick) / 2, cx = size / 2, circ = 2 * Math.PI * r;
  return `<div style="position:relative;width:${size}px;height:${size}px;flex-shrink:0">
  <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="display:block;transform:rotate(-90deg)" aria-hidden="true">
    <circle cx="${cx}" cy="${cx}" r="${r}" stroke="rgba(255,255,255,0.09)" stroke-width="${thick}" fill="none"></circle>
    <circle cx="${cx}" cy="${cx}" r="${r}" stroke="${c}" stroke-width="${thick}" fill="none" stroke-linecap="round" stroke-dasharray="${(circ * pct / 100).toFixed(1)} ${circ.toFixed(1)}"></circle>
  </svg>
  <div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center">
    <span style="font-size:${size > 80 ? 20 : 15}px;font-weight:700;color:${T.ink};letter-spacing:-0.035em;line-height:1">${label}</span>
    ${sub ? `<span style="font-size:9px;color:${T.faint};margin-top:2px">${sub}</span>` : ''}
  </div>
</div>`;
};

export const heatmap = (rowLabels, grid, cell = 22, gap = 4) => {
  const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  const g = `grid-template-columns:58px repeat(7, minmax(0,1fr));gap:${gap}px`;
  return `<div style="display:flex;flex-direction:column;gap:${gap}px">
  <div style="display:grid;${g};align-items:center"><span></span>
    ${days.map((d) => `<span style="font-size:9px;color:${T.faint};text-align:center;font-weight:600">${d}</span>`).join('')}</div>
  ${grid.map((rw, r) => `<div style="display:grid;${g};align-items:center">
    <span style="font-size:10px;color:${T.dim};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${rowLabels[r]}</span>
    ${rw.map((v) => `<span style="height:${cell}px;border-radius:6px;background:${v > 0.75 ? T.accent2 : T.accent};opacity:${(0.14 + v * 0.86).toFixed(2)}"></span>`).join('')}
  </div>`).join('')}
</div>`;
};

// ── Table bits ───────────────────────────────────────────────────────────
export const table = (heads, rows, widths) => {
  const g = `display:grid;grid-template-columns:${widths};gap:14px;align-items:center;`;
  return `<div style="display:flex;flex-direction:column;min-width:0">
  <div style="${g}padding:0 12px 9px">${heads.map((h) => `<span style="font-size:9.5px;font-weight:700;color:${T.faint};letter-spacing:0.08em;text-transform:uppercase">${h}</span>`).join('')}</div>
  ${rows.map((c, i) => `<div style="${g}padding:9px 12px;border-top:1px solid ${T.lineSoft};${i === 0 ? 'background:rgba(255,255,255,0.03);border-radius:12px;border-top-color:transparent;' : ''}">${c.join('')}</div>`).join('')}
</div>`;
};

export const cellMain = (title, sub, ic, tone = 'orange') => {
  const c = TONES[tone];
  return `<span style="display:flex;align-items:center;gap:11px;min-width:0">
  <span style="width:32px;height:32px;border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:${c}22;color:${c}">${icon(ic, 16, 'currentColor', 1.7)}</span>
  <span style="min-width:0">
    <span style="display:block;font-size:12.5px;font-weight:600;color:${T.ink};letter-spacing:-0.014em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${title}</span>
    <span style="display:block;font-size:10px;color:${T.faint};margin-top:2px">${sub}</span>
  </span></span>`;
};

export const pill = (text, tone = 'green') => {
  const c = TONES[tone];
  return `<span style="display:inline-flex;align-items:center;gap:5px;padding:3px 9px 3px 7px;border-radius:999px;font-size:10px;font-weight:700;letter-spacing:0.03em;text-transform:uppercase;white-space:nowrap;color:${c};background:${c}1C;border:1px solid ${c}33">
  <span style="width:5px;height:5px;border-radius:50%;background:${c}"></span>${text}</span>`;
};

export const badge = (text, tone = 'slate') => {
  const c = TONES[tone];
  return `<span style="display:inline-flex;align-items:center;padding:3px 9px;border-radius:7px;font-size:10.5px;font-weight:600;white-space:nowrap;color:${c};background:${c}17;border:1px solid ${c}2B">${text}</span>`;
};

export const txt = (s, { size = 12, color = T.dim, weight = 500 } = {}) =>
  `<span style="font-size:${size}px;color:${color};font-weight:${weight};letter-spacing:-0.005em;white-space:nowrap">${s}</span>`;

export const capacity = (pct, label, tone = 'orange') =>
  `<span style="display:flex;flex-direction:column;gap:5px;min-width:0">
  <span style="font-size:11px;color:#C4C4C8;font-weight:600">${label}</span>${bar(pct, tone, '100%', 4)}</span>`;

export const btnPrimary = (label) =>
  `<span style="display:inline-flex;align-items:center;justify-content:center;padding:9px 16px;border-radius:11px;background:${T.accent};color:#160800;font-size:12px;font-weight:700;white-space:nowrap">${label}</span>`;

export const btnGhost = (label) =>
  `<span style="display:inline-flex;align-items:center;justify-content:center;padding:9px 16px;border-radius:11px;background:rgba(255,255,255,0.06);border:1px solid ${T.line};color:#D4D4D8;font-size:12px;font-weight:600;white-space:nowrap">${label}</span>`;

// ── Page shell ───────────────────────────────────────────────────────────
export const page = (activePage, section, action, bodyHtml, { tall = false, showFlyout = false } = {}) => `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
    body { margin: 0; font-family: ${T.font}; -webkit-font-smoothing: antialiased; }
    a { color: ${T.accent}; text-decoration: none; }
    a:hover { color: #FF8A57; }
  </style>
</helmet>
<div style="width:1600px;height:900px;overflow:hidden;position:relative;background:${T.bg};color:${T.ink};font-family:${T.font}">
  ${rail(activePage)}
  ${showFlyout ? flyout(activePage) : ''}
  <div style="margin-left:76px;height:100%;padding:14px 16px 16px 0;display:flex;flex-direction:column;gap:14px">
    ${heroPanel(activePage, section, action, tall)}
    ${bodyHtml}
  </div>
</div>
</x-dc>
</body>
</html>
`;
