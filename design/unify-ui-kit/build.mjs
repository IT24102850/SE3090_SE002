import { writeFileSync } from 'node:fs';
import {
  T, TONES, surf, icon, logo, page, card, cardHead, stat, cardFoot, table, cellMain,
  badge, pill, bar, spark, cols, donut, txt, capacity, heatmap, scatter, dualLine,
  blockCols, dualWave, waveform, tickGauge, btnPrimary, btnGhost, GROUPS,
} from './lib.mjs';

const W = (n, h) => writeFileSync(new URL(`./${n}`, import.meta.url), h);
const row = (h, { gap = 14, grow = false, height = '' } = {}) =>
  `<div style="display:flex;gap:${gap}px;min-width:0;${grow ? 'flex-grow:1;min-height:0;' : ''}${height ? `height:${height};` : ''}">${h}</div>`;
const col = (h, { gap = 14, w = '', grow = false } = {}) =>
  `<div style="display:flex;flex-direction:column;gap:${gap}px;min-width:0;${w ? `width:${w};flex-shrink:0;` : ''}${grow ? 'flex-grow:1;min-height:0;' : ''}">${h}</div>`;
const grid4 = (h) => `<div style="display:grid;grid-template-columns:repeat(4, minmax(0,1fr));gap:14px;flex-shrink:0">${h}</div>`;

// KPI card in the reference's anatomy: chip + title + meta, chart, big number.
const kpi = (title, ic, tone, meta, chart, value, unit, caption, capIcon) =>
  card(cardHead(title, meta, ic, tone) + chart + stat(value, unit, caption, capIcon, tone), { pad: 15 });

// ── 1. Dashboard ─────────────────────────────────────────────────────────
{
  const chips = ['bed', 'surf', 'boat', 'car', 'box', 'users']
    .map((i, k) => `<span style="width:29px;height:29px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,0.07);border:1px solid ${T.line};color:${k === 0 ? T.accent2 : '#9A9A9F'}">${icon(i, 14, 'currentColor', 1.7)}</span>`).join('');

  W('Dashboard.dc.html', page('Dashboard', 'Dashboard', 'Add booking',
    row(
      col(
        `<div style="display:grid;grid-template-columns:repeat(3, minmax(0,1fr));gap:14px;flex-grow:1;min-height:0">
          ${kpi('Booking Activity', 'calendar', 'orange', 'Last 7 days',
      scatter([
        ['Room nights', [[0.04, 0.75], [0.12, 0.45], [0.3, 0.9], [0.38, 0.6], [0.55, 0.8], [0.72, 0.5], [0.86, 0.7]], 'orange'],
        ['Lessons', [[0.08, 0.5], [0.22, 0.8], [0.29, 0.55], [0.46, 0.95], [0.63, 0.6], [0.79, 0.85]], 'yellow'],
        ['Excursions', [[0.06, 0.6], [0.19, 0.4], [0.44, 0.75], [0.58, 0.5], [0.81, 0.9], [0.92, 0.55]], 'orange'],
      ], ['08', '12', '18', '22']),
      '48', '', 'Bookings this week', 'check')}
          ${kpi('Occupancy', 'bed', 'orange', 'Last 7 days',
        dualLine([48, 55, 51, 62, 58, 69, 66, 74], [40, 44, 47, 50, 53, 57, 59, 62], ['80', '40', '0'], ['08', '12', '18', '22']),
        '74', '%', '+6 pts from last week', 'check')}
          ${kpi('Check-ins', 'users', 'orange', 'Last 7 days',
          blockCols([3, 5, 4, 6, 5, 7, 4], ['M', 'T', 'W', 'T', 'F', 'S', 'S'], 232, 62, [3, 5]),
          '12', '', 'Avg per day', 'check')}
        </div>` +
        row(
          card(cardHead('Revenue Health', 'This month', 'chart', 'orange') +
            `<div style="text-align:center;margin-bottom:2px">
               <div style="font-size:30px;font-weight:700;color:${T.accent};letter-spacing:-0.045em;line-height:1">87</div>
               <div style="font-size:12px;color:${T.ink};font-weight:600;margin-top:5px">Strong Condition</div>
               <div style="font-size:10.5px;color:${T.faint};margin-top:3px">+5 vs monthly average</div>
             </div>` + dualWave() +
            cardFoot(['Room nights', 'LKR 312K'], 'Insights', ['Activities', 'LKR 174K']), { pad: 15, grow: true }) +
          card(cardHead('Today’s Load', 'Sep 8', 'clock', 'orange') +
            `<div style="margin-bottom:2px">
               <div style="font-size:30px;font-weight:700;color:${T.accent};letter-spacing:-0.045em;line-height:1">73</div>
               <div style="font-size:12px;color:${T.ink};font-weight:600;margin-top:5px">Load Score</div>
               <div style="font-size:10.5px;color:${T.faint};margin-top:3px">17 bookings across 3 branches</div>
             </div>` + waveform() +
            cardFoot(['Busiest slot', '09:30'], 'Insights', ['Free capacity', '27%']), { pad: 15, grow: true }),
          { grow: true }),
        { grow: true }) +
      card(
        `<div style="display:flex;gap:7px;justify-content:center;flex-wrap:wrap;margin-bottom:16px">${chips}</div>
         <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;flex-grow:1">
           ${tickGauge(67, 196, '67%', 'Utilization')}
         </div>
         <div style="text-align:center;padding-top:8px">
           <div style="font-size:12.5px;font-weight:650;color:${T.ink};letter-spacing:-0.018em">Balanced Load & Capacity</div>
           <div style="font-size:10.5px;color:${T.faint};margin-top:4px">Across Weligama, Mirissa, Ahangama</div>
         </div>`, { pad: 15, style: 'width:248px;flex-shrink:0' }),
      { grow: true }),
    { tall: true }));
}

// ── 2. Resource Manager ──────────────────────────────────────────────────
{
  const rate = (a, b) => txt(a, { size: 12, color: '#E8E8EA', weight: 650 }) + txt(b, { size: 10, color: T.faint });
  const rows = [
    [cellMain('Sea View Double — Room 1', 'MB-R1 · Weligama', 'bed', 'orange'), badge('Room', 'orange'), capacity(100, '2 of 2 guests'), rate('LKR 4,000', ' / night'), pill('Available', 'green')],
    [cellMain('Sea View Double — Room 2', 'MB-R2 · Weligama', 'bed', 'orange'), badge('Room', 'orange'), capacity(100, '2 of 2 guests'), rate('LKR 4,000', ' / night'), pill('Reserved', 'yellow')],
    [cellMain('Sea View Double — Room 3', 'MB-R3 · Weligama', 'bed', 'orange'), badge('Room', 'orange'), capacity(50, '1 of 2 guests'), rate('LKR 4,000', ' / night'), pill('Available', 'green')],
    [cellMain('Soft-Top Surfboard 8′0', 'MB-SB2 · Surf Annex', 'surf', 'yellow'), badge('Equipment', 'yellow'), capacity(25, '1 of 4 boards'), rate('LKR 1,000', ' / day'), pill('Available', 'green')],
    [cellMain('Whale Watching Boat', 'MB-BT1 · Mirissa Harbour', 'boat', 'cool'), badge('Vehicle', 'cool'), capacity(83, '5 of 6 seats'), rate('LKR 16,000', ' / seat'), pill('Maintenance', 'amber')],
    [cellMain('Airport Transfer Car', 'MB-CAR1 · Weligama', 'car', 'cool'), badge('Vehicle', 'cool'), capacity(67, '2 of 3 seats'), rate('LKR 18,000', ' / trip'), pill('Reserved', 'yellow')],
  ];
  const filters = ['All resources', 'Room', 'Equipment', 'Vehicle', 'Staff', 'Desk']
    .map((c, i) => `<span style="padding:5px 12px;border-radius:999px;font-size:11.5px;font-weight:600;white-space:nowrap;${i === 0
      ? `background:${T.accent};color:#160800` : `background:rgba(255,255,255,0.055);color:${T.dim};border:1px solid ${T.line}`}">${c}</span>`).join('');

  W('Main.dc.html', page('Resource Manager', 'Resources · Resource Manager', 'New resource',
    grid4(
      kpi('Total Resources', 'building', 'orange', 'All branches', cols([9, 12, 11, 15, 14, 18, 17, 21, 20, 24], 'orange', 232, 44, 9), '24', '', '+3 this week', 'check') +
      kpi('Available Now', 'check', 'orange', 'Live', spark([12, 14, 13, 16, 15, 17, 16, 18], 'orange', 232, 44), '18', '', 'Ready to book', 'check') +
      kpi('Utilization', 'chart', 'orange', 'Last 7 days', `<div style="display:flex;align-items:center;gap:14px">${donut(67, 'orange', 74, 7, '67%')}<div style="display:flex;flex-direction:column;gap:7px;flex-grow:1;min-width:0">${[['Rooms', 88, 'orange'], ['Equipment', 54, 'yellow'], ['Vehicles', 41, 'cool']].map(([n, v, t]) => `<div style="display:flex;align-items:center;gap:8px"><span style="font-size:9.5px;color:${T.faint};width:58px;flex-shrink:0">${n}</span>${bar(v, t, '100%', 4)}</div>`).join('')}</div></div>`, '67', '%', 'Up 5 pts vs last week', 'check') +
      kpi('Alerts', 'alert', 'amber', 'Needs action', cols([1, 0, 2, 1, 3, 2, 3, 3, 2, 3], 'amber', 232, 44, 9), '3', '', 'Low stock items', 'alert')
    ) +
    row(
      card(cardHead('All resources', 'Sorted by name · 24 total', 'building', 'orange') +
        `<div style="display:flex;gap:7px;margin-bottom:14px;flex-wrap:wrap">${filters}</div>` +
        table(['Resource', 'Category', 'Capacity', 'Rate', 'Status'], rows, 'minmax(0,2.3fr) 108px minmax(0,1.15fr) 140px 124px') +
        `<div style="margin-top:auto;padding-top:14px;display:flex;align-items:center;justify-content:space-between;border-top:1px solid ${T.lineSoft}">
           ${txt('Showing 6 of 24 resources', { size: 11, color: T.faint })}
           <span style="display:flex;gap:6px">${['1', '2', '3', '4'].map((n, i) => `<span style="width:24px;height:24px;border-radius:7px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:600;${i === 0 ? `background:${T.accent};color:#160800` : `color:${T.faint};border:1px solid ${T.line}`}">${n}</span>`).join('')}</span>
         </div>`, { grow: true }) +
      col(
        card(cardHead('Weekly Availability', 'Sep 1 – 7', 'calendar', 'orange') +
          heatmap(['Rooms', 'Boards', 'Boats', 'Cars'], [
            [0.35, 0.5, 0.6, 0.85, 1, 1, 0.9], [0.2, 0.3, 0.45, 0.6, 0.8, 0.95, 0.7],
            [0.15, 0.15, 0.3, 0.4, 0.7, 0.9, 0.55], [0.4, 0.45, 0.35, 0.5, 0.65, 0.8, 0.6],
          ], 24) +
          `<div style="display:flex;align-items:center;gap:8px;margin-top:auto;padding-top:13px">
             ${txt('Quiet', { size: 10, color: T.faint })}
             <span style="flex-grow:1;height:5px;border-radius:999px;background:linear-gradient(90deg, rgba(255,107,44,0.16), ${T.accent2})"></span>
             ${txt('Full', { size: 10, color: T.faint })}
           </div>`, { grow: true }) +
        card(cardHead('By Category', '', 'analytics', 'orange') +
          `<div style="display:flex;flex-direction:column;gap:12px">
             ${[['Rooms', 88, 'orange', '3 resources'], ['Equipment', 54, 'yellow', '9 resources'], ['Vehicles', 41, 'cool', '4 resources'], ['Staff', 72, 'green', '6 resources'], ['Desks', 18, 'slate', '2 resources']]
      .map(([n, v, t, s]) => `<div>
               <div style="display:flex;align-items:baseline;justify-content:space-between;margin-bottom:6px">
                 <span style="font-size:11.5px;color:#E8E8EA;font-weight:600">${n}</span>
                 <span style="font-size:11.5px;color:${TONES[t]};font-weight:700;letter-spacing:-0.02em">${v}%</span></div>
               ${bar(v, t, '100%', 5)}
               <div style="font-size:9.5px;color:${T.faint};margin-top:5px">${s}</div></div>`).join('')}
           </div>`, { grow: true }),
        { w: '360px' }),
      { grow: true }),
    { showFlyout: true }));
}

// ── 3. Booking Manager ───────────────────────────────────────────────────
{
  const statCards = [['Pending', 4, 'amber'], ['Confirmed', 22, 'orange'], ['Checked In', 9, 'yellow'], ['Completed', 13, 'green']]
    .map(([n, v, t]) => card(`<div style="display:flex;align-items:center;justify-content:space-between;gap:10px">
      <div><div style="font-size:10.5px;font-weight:600;color:${T.dim};letter-spacing:0.05em;text-transform:uppercase">${n}</div>
      <div style="font-size:27px;font-weight:700;color:${T.ink};letter-spacing:-0.04em;margin-top:5px;line-height:1">${v}</div></div>
      ${donut(Math.round(v / 48 * 100), t, 54, 6)}</div>`, { pad: 15 })).join('');

  const days = [['Mon', '7'], ['Tue', '8'], ['Wed', '9'], ['Thu', '10'], ['Fri', '11'], ['Sat', '12'], ['Sun', '13']];
  const blocks = [
    [['Room 1 · 3 nights', 'orange'], ['Surf Lesson 09:30', 'yellow']],
    [['Room 1 · 3 nights', 'orange'], ['Whale Watch 06:00', 'cool'], ['Cooking 17:00', 'amber']],
    [['Room 1 · 3 nights', 'orange'], ['Surf Lesson 09:30', 'yellow'], ['Transfer 13:00', 'cool']],
    [['Room 2 · 2 nights', 'orange'], ['Board rental', 'yellow']],
    [['Room 2 · 2 nights', 'orange'], ['Whale Watch 06:00', 'cool'], ['Surf Lesson 09:30', 'yellow'], ['Cooking 17:00', 'amber']],
    [['Room 3 · 4 nights', 'orange'], ['Private Surf 08:00', 'yellow'], ['Whale Watch 06:00', 'cool']],
    [['Room 3 · 4 nights', 'orange'], ['Transfer 11:00', 'cool']],
  ];
  const week = `<div style="display:grid;grid-template-columns:repeat(7, minmax(0,1fr));gap:9px;flex-grow:1;min-height:0">
    ${days.map(([d, n], i) => {
    const today = i === 1;
    return `<div style="display:flex;flex-direction:column;gap:7px;min-width:0;padding:10px 9px;border-radius:14px;background:${today ? 'rgba(255,107,44,0.09)' : 'rgba(255,255,255,0.025)'};border:1px solid ${today ? 'rgba(255,107,44,0.34)' : T.line}">
      <div style="display:flex;align-items:center;gap:6px;margin-bottom:2px">
        <span style="font-size:9.5px;color:${T.faint};font-weight:600;letter-spacing:0.06em;text-transform:uppercase">${d}</span>
        <span style="font-size:12px;font-weight:700;letter-spacing:-0.02em;${today ? `background:${T.accent};color:#160800;border-radius:6px;padding:0 6px` : 'color:#C4C4C8'}">${n}</span>
      </div>
      ${blocks[i].map(([l, t]) => `<div style="padding:7px 8px;border-radius:9px;font-size:10.5px;font-weight:600;color:${TONES[t]};background:${TONES[t]}1C;border-left:2px solid ${TONES[t]};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${l}</div>`).join('')}
    </div>`;
  }).join('')}</div>`;

  const list = [
    [cellMain('Nadeesha Perera', 'BK-2419 · Room Night', 'bed', 'orange'), txt('Sea View Double — Room 1', { size: 11.5, color: '#C4C4C8' }), txt('Sep 8 – Sep 11 · 3 nights', { size: 11.5 }), txt('LKR 12,000', { color: '#E8E8EA', weight: 650 }), pill('Confirmed', 'orange')],
    [cellMain('Tom Whitfield', 'BK-2420 · Beginner Surf Lesson', 'surf', 'yellow'), txt('Weligama beach break', { size: 11.5, color: '#C4C4C8' }), txt('Sep 8 · 09:30 – 11:30', { size: 11.5 }), txt('LKR 3,000', { color: '#E8E8EA', weight: 650 }), pill('Checked In', 'yellow')],
    [cellMain('Ravi Kumar', 'BK-2421 · Airport Transfer', 'car', 'cool'), txt('Airport Transfer Car', { size: 11.5, color: '#C4C4C8' }), txt('Sep 8 · 13:00 – 16:00', { size: 11.5 }), txt('LKR 18,000', { color: '#E8E8EA', weight: 650 }), pill('Pending', 'amber')],
    [cellMain('Aiko Tanaka', 'BK-2415 · Mirissa Whale Watching', 'boat', 'cool'), txt('Whale Watching Boat', { size: 11.5, color: '#C4C4C8' }), txt('Sep 8 · 06:00 – 11:00', { size: 11.5 }), txt('LKR 32,000', { color: '#E8E8EA', weight: 650 }), pill('Completed', 'green')],
  ];

  W('BookingManager.dc.html', page('Booking Manager', 'Bookings · Booking Manager', 'New booking',
    grid4(statCards) +
    card(`<div style="display:flex;align-items:center;justify-content:space-between;gap:14px;margin-bottom:13px">
        <span style="font-size:13px;font-weight:650;color:${T.ink};letter-spacing:-0.018em">Mon, Sep 7 – Sun, Sep 13</span>
        <div style="display:flex;gap:7px">${['This week', 'All statuses', 'All resources', 'All branches'].map((c, i) => `<span style="display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border-radius:999px;font-size:11.5px;font-weight:600;white-space:nowrap;${i === 0 ? `background:${T.accent};color:#160800` : `background:rgba(255,255,255,0.055);color:${T.dim};border:1px solid ${T.line}`}">${c}${icon('chevron', 11, 'currentColor', 2)}</span>`).join('')}</div>
      </div>` + week, { grow: true, pad: 15 }) +
    card(cardHead('Today · 4 bookings', 'Sep 8, 2026', 'calendar', 'orange') +
      table(['Guest', 'Resource', 'When', 'Total', 'Status'], list, 'minmax(0,1.9fr) minmax(0,1.5fr) minmax(0,1.3fr) 116px 122px'),
      { pad: 15, style: 'flex-shrink:0' })));
}

// ── 4. Multi-Branch Schedule ─────────────────────────────────────────────
{
  const branches = [
    ['Weligama — Main House', 'Rooms · Cooking · Transfers', 'orange', [[2, 5, 'Room 1 · Perera', 'orange'], [8, 4, 'Cooking class', 'amber'], [14, 6, 'Room 3 · Tanaka', 'orange']]],
    ['Mirissa — Harbour Desk', 'Whale watching · Boat ops', 'cool', [[0, 4, 'Whale watch 06:00', 'cool'], [6, 3, 'Boat service', 'amber'], [11, 5, 'Whale watch 06:00', 'cool']]],
    ['Ahangama — Surf Annex', 'Lessons · Board rental', 'yellow', [[3, 4, 'Surf lesson', 'yellow'], [9, 6, 'Board rental · 3 days', 'yellow'], [17, 3, 'Private surf', 'yellow']]],
  ];
  const gantt = `<div style="display:flex;flex-direction:column;gap:9px;flex-grow:1;min-height:0">
    <div style="display:grid;grid-template-columns:206px minmax(0,1fr);gap:14px;align-items:center"><span></span>
      <div style="display:grid;grid-template-columns:repeat(21, minmax(0,1fr))">
        ${Array.from({ length: 21 }, (_, i) => `<span style="font-size:9px;color:${T.faint};text-align:center;font-weight:600">${i % 3 === 0 ? `${String(6 + i).padStart(2, '0')}:00` : ''}</span>`).join('')}
      </div></div>
    ${branches.map(([name, sub, tone, bars]) => `<div style="display:grid;grid-template-columns:206px minmax(0,1fr);gap:14px;align-items:center;flex-grow:1;min-height:0">
      <div style="display:flex;align-items:center;gap:10px;min-width:0">
        <span style="width:32px;height:32px;border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:${TONES[tone]}22;color:${TONES[tone]}">${icon('pin', 16, 'currentColor', 1.7)}</span>
        <span style="min-width:0">
          <span style="display:block;font-size:12.5px;font-weight:600;color:${T.ink};letter-spacing:-0.014em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${name}</span>
          <span style="display:block;font-size:10px;color:${T.faint};margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${sub}</span></span></div>
      <div style="position:relative;height:100%;min-height:58px;border-radius:12px;background:rgba(255,255,255,0.025);border:1px solid ${T.line};overflow:hidden">
        <div style="position:absolute;inset:0;display:grid;grid-template-columns:repeat(21, minmax(0,1fr))">
          ${Array.from({ length: 21 }, () => `<span style="border-right:1px solid rgba(255,255,255,0.032)"></span>`).join('')}</div>
        ${bars.map(([s, sp, l, t]) => `<div style="position:absolute;top:50%;transform:translateY(-50%);left:${(s / 21 * 100).toFixed(2)}%;width:${(sp / 21 * 100).toFixed(2)}%;height:32px;border-radius:9px;display:flex;align-items:center;padding:0 10px;font-size:10.5px;font-weight:650;color:#160800;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;background:${TONES[t]}">${l}</div>`).join('')}
      </div></div>`).join('')}
  </div>`;

  W('MultiBranch.dc.html', page('Multi-Branch Schedule', 'Bookings · Multi-Branch Schedule', 'Add branch',
    grid4(
      kpi('Active Branches', 'pin', 'orange', 'All operating', cols([3, 3, 3, 3, 3, 3, 3, 3, 3, 3], 'orange', 232, 44), '3', '', 'Weligama · Mirissa · Ahangama', 'check') +
      kpi('Bookings Today', 'calendar', 'orange', 'Live', spark([9, 11, 10, 13, 12, 15, 14, 17], 'orange', 232, 44), '17', '', '+4 vs yesterday', 'check') +
      kpi('Cross-Branch Clashes', 'alert', 'amber', 'Needs action', cols([0, 1, 0, 0, 2, 1, 0, 1, 0, 1], 'amber', 232, 44, 9), '1', '', 'Boat double-booked', 'alert') +
      kpi('Staff On Shift', 'users', 'orange', 'Live', spark([7, 8, 9, 8, 10, 11, 10, 11], 'orange', 232, 44), '11', '', 'Across 3 branches', 'check')
    ) +
    row(
      card(cardHead('Monday, Sep 8 · 06:00 – 03:00', 'Colour = booking type', 'layers', 'orange') + gantt, { grow: true, pad: 15 }) +
      col(
        card(cardHead('Branch Load', 'This week', 'analytics', 'orange') +
          heatmap(['Weligama', 'Mirissa', 'Ahangama'], [
            [0.5, 0.65, 0.7, 0.9, 1, 1, 0.85], [0.3, 0.35, 0.5, 0.55, 0.9, 1, 0.6], [0.45, 0.5, 0.55, 0.7, 0.85, 0.95, 0.75],
          ], 24)) +
        card(cardHead('Clash Detected', '', 'alert', 'amber') +
          `<div style="padding:12px;border-radius:13px;background:${T.warn}12;border:1px solid ${T.warn}30">
             <div style="font-size:12.5px;font-weight:650;color:${T.ink};letter-spacing:-0.018em;margin-bottom:8px">Whale Watching Boat</div>
             <p style="margin:0;font-size:11.5px;color:${T.dim};line-height:1.55">MB-BT1 is booked at Mirissa Harbour 06:00–11:00 while flagged <strong style="color:${T.warn};font-weight:650">Under Maintenance</strong> until Sep 9.</p>
             <div style="display:flex;gap:8px;margin-top:12px">${btnPrimary('Reassign')}${btnGhost('Dismiss')}</div>
           </div>`, { grow: true }),
        { w: '330px' }),
      { grow: true })));
}

// ── 5. Inventory Manager + Low Stock Alerts ──────────────────────────────
{
  const items = [
    ['Bath Towel — Large', 'TWL-LG', 'Supplies', 42, 60, 25, 'each', 'green', 'In Stock'],
    ['Bed Linen Set — Double', 'LIN-DBL', 'Supplies', 18, 40, 20, 'each', 'amber', 'Low'],
    ['Surf Wax — Tropical', 'WAX-TRP', 'Equipment', 4, 24, 10, 'box', 'red', 'Critical'],
    ['Reef-Safe Sunscreen', 'SUN-50', 'General', 31, 40, 12, 'pack', 'green', 'In Stock'],
    ['Drinking Water 1 L', 'WTR-1L', 'General', 96, 120, 40, 'l', 'green', 'In Stock'],
    ['Snorkel Mask', 'SNK-MSK', 'Equipment', 9, 20, 8, 'each', 'amber', 'Low'],
  ].map(([n, sku, cat, q, max, ro, unit, tone, st]) => [
    cellMain(n, `${sku} · ${cat}`, cat === 'Equipment' ? 'surf' : 'box', tone === 'red' ? 'red' : tone === 'amber' ? 'amber' : 'orange'),
    badge(cat, 'slate'),
    `<span style="display:flex;flex-direction:column;gap:5px;min-width:0">
       <span style="font-size:12px;color:${T.ink};font-weight:700;letter-spacing:-0.02em">${q}<span style="color:${T.faint};font-weight:500;font-size:10px"> / ${max} ${unit}</span></span>
       ${bar(Math.round(q / max * 100), tone, '100%', 4)}</span>`,
    txt(String(ro), { size: 12, color: '#C4C4C8', weight: 650 }),
    pill(st, tone === 'red' ? 'red' : tone === 'amber' ? 'amber' : 'green'),
  ]);

  const alerts = [
    ['Surf Wax — Tropical', '4 boxes left · reorder at 10', 'Out in ~2 days at current burn', 'red', 17],
    ['Bed Linen Set — Double', '18 sets left · reorder at 20', 'Below threshold since Sep 6', 'amber', 45],
    ['Snorkel Mask', '9 masks left · reorder at 8', 'One unit above threshold', 'amber', 45],
  ].map(([n, sub, note, tone, pct]) => `<div style="padding:13px;border-radius:14px;background:${TONES[tone]}12;border:1px solid ${TONES[tone]}30">
    <div style="display:flex;align-items:flex-start;gap:10px;margin-bottom:10px">
      <span style="width:29px;height:29px;border-radius:9px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:${TONES[tone]}22;color:${TONES[tone]}">${icon('alert', 15, 'currentColor', 1.9)}</span>
      <span style="min-width:0;flex-grow:1">
        <span style="display:block;font-size:12.5px;font-weight:650;color:${T.ink};letter-spacing:-0.018em">${n}</span>
        <span style="display:block;font-size:10.5px;color:${T.dim};margin-top:2px">${sub}</span></span></div>
    ${bar(pct, tone, '100%', 4)}
    <div style="font-size:10px;color:${T.faint};margin-top:8px">${note}</div></div>`).join('');

  W('Inventory.dc.html', page('Inventory Manager', 'Inventory · Inventory Manager', 'Add item',
    grid4(
      kpi('Total Items', 'box', 'orange', 'Weligama', cols([30, 31, 33, 32, 34, 35, 36, 36, 37, 38], 'orange', 232, 44, 9), '38', '', '+2 this week', 'check') +
      kpi('Stock Value', 'chart', 'orange', 'This month', spark([182, 190, 186, 198, 194, 205, 201, 214], 'orange', 232, 44), 'LKR 214K', '', '+3.1% this month', 'check') +
      kpi('Low Stock', 'alert', 'amber', 'Needs action', cols([1, 1, 2, 1, 2, 3, 2, 3, 3, 3], 'amber', 232, 44, 9), '3', '', '1 critical', 'alert') +
      kpi('Open Purchase Orders', 'receipt', 'orange', 'Pending', cols([1, 2, 1, 1, 2, 2, 1, 2, 2, 2], 'orange', 232, 44), '2', '', 'LKR 48K committed', 'clock')
    ) +
    row(
      card(cardHead('All items', 'Weligama · Main House', 'box', 'orange') +
        table(['Item', 'Category', 'Stock level', 'Reorder at', 'Status'], items, 'minmax(0,2.1fr) 118px minmax(0,1.4fr) 92px 112px'), { grow: true, pad: 15 }) +
      col(
        card(cardHead('Low Stock Alerts', '3 active', 'alert', 'amber') +
          `<div style="display:flex;flex-direction:column;gap:11px">${alerts}</div>
           <div style="margin-top:auto;padding-top:14px;display:flex">${btnPrimary('Create purchase order')}</div>`, { grow: true, pad: 15 }),
        { w: '374px' }),
      { grow: true })));
}

// ── 6. AI Planner ────────────────────────────────────────────────────────
{
  const bubbleUser = (s) => `<div style="display:flex;justify-content:flex-end">
    <div style="max-width:76%;padding:11px 15px;border-radius:16px 16px 5px 16px;background:${T.accent}20;border:1px solid ${T.accent}38;font-size:12.5px;color:#F6E4D8;line-height:1.55">${s}</div></div>`;
  const bubbleAI = (s) => `<div style="display:flex;gap:11px">
    <span style="width:29px;height:29px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:${T.accent};color:#160800">${icon('spark', 15, 'currentColor', 2)}</span>
    <div style="max-width:82%;padding:11px 15px;border-radius:5px 16px 16px 16px;background:rgba(255,255,255,0.05);border:1px solid ${T.line};font-size:12.5px;color:#C4C4C8;line-height:1.6">${s}</div></div>`;

  const plans = [
    ['Open a second surf slot', 'Add an 07:30 beginner lesson on Sat & Sun. Both instructors are free and the 09:30 slot has been full 6 weekends running.', '+LKR 24,000 / week', 'yellow', 'surf', 92],
    ['Hold Room 3 for 4-night stays', 'Room 3 turns over most often. A 4-night minimum over the Dec peak lifts occupancy without new inventory.', '+9 pts occupancy', 'orange', 'bed', 84],
    ['Reorder surf wax now', 'At the current burn rate you run out in 2 days, which would cancel 3 booked lessons.', 'Avoids 3 cancellations', 'amber', 'alert', 97],
  ].map(([t, b, im, tone, ic, conf]) => `<div style="padding:13px;${surf(15)}display:flex;flex-direction:column">
    <div style="display:flex;align-items:flex-start;gap:10px;margin-bottom:9px">
      <span style="width:30px;height:30px;border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:${TONES[tone]}22;color:${TONES[tone]}">${icon(ic, 15, 'currentColor', 1.8)}</span>
      <span style="min-width:0;flex-grow:1">
        <span style="display:block;font-size:12.5px;font-weight:650;color:${T.ink};letter-spacing:-0.018em">${t}</span>
        <span style="display:block;font-size:10px;color:${TONES[tone]};font-weight:650;margin-top:3px">${im}</span></span></div>
    <p style="margin:0 0 11px;font-size:11.5px;color:${T.dim};line-height:1.55">${b}</p>
    <div style="display:flex;align-items:center;gap:9px;margin-top:auto">
      <span style="font-size:9.5px;color:${T.faint};white-space:nowrap">Confidence</span>${bar(conf, tone, '100%', 4)}
      <span style="font-size:10.5px;color:${TONES[tone]};font-weight:700">${conf}%</span></div>
    <div style="display:flex;gap:8px;margin-top:11px">
      <span style="flex-grow:1;text-align:center;padding:7px;border-radius:9px;background:${T.accent};color:#160800;font-size:11.5px;font-weight:700">Apply plan</span>
      <span style="padding:7px 12px;border-radius:9px;background:rgba(255,255,255,0.06);border:1px solid ${T.line};color:#D4D4D8;font-size:11.5px;font-weight:600">Preview</span></div>
  </div>`).join('');

  // Horizontal pipeline strip — a stacked list of four agents plus three plan
  // cards overran the 900px frame, and the strip reads better anyway.
  const agents = `<div style="display:flex;align-items:center;gap:6px;padding:10px 12px;border-radius:12px;background:rgba(255,255,255,0.035);border:1px solid ${T.line};margin-bottom:12px">
    ${[['Intake', 'green'], ['Analyst', 'green'], ['Planner', 'orange'], ['Reviewer', 'slate']]
      .map(([n, tone], i) => `${i ? `<span style="flex-grow:1;height:1px;background:${T.lineSoft}"></span>` : ''}
        <span style="display:flex;align-items:center;gap:5px;flex-shrink:0">
          <span style="width:6px;height:6px;border-radius:50%;background:${TONES[tone]}"></span>
          <span style="font-size:10.5px;color:${tone === 'slate' ? T.faint : T.ink};font-weight:600">${n}</span></span>`).join('')}
  </div>`;

  W('AIPlanner.dc.html', page('AI Planner', 'Bookings · AI Planner', 'New plan',
    row(
      card(cardHead('Conversation', 'Gemini · 4-agent pipeline', 'spark', 'orange') +
        `<div style="display:flex;flex-direction:column;gap:14px;flex-grow:1;min-height:0">
           ${bubbleUser('We keep selling out the 09:30 surf lesson at weekends. What should I change before the December peak?')}
           ${bubbleAI('I looked at 90 days of bookings for Moonlit Bay. The 09:30 beginner lesson hit capacity on <strong style="color:#fff;font-weight:650">6 of the last 6 weekends</strong>, and 11 guests who viewed it booked nothing instead. Room nights are steady at 74% — the constraint is instructor slots, not beds.')}
           ${bubbleAI('Three options, ranked by impact against effort. The surf wax reorder is unrelated but urgent, so I have folded it in.')}
         </div>
         <div style="margin-top:14px;display:flex;align-items:center;gap:11px;padding:11px 15px;border-radius:14px;background:rgba(255,255,255,0.05);border:1px solid ${T.accent}38">
           <span style="color:${T.accent};display:flex">${icon('spark', 16, 'currentColor', 1.8)}</span>
           <span style="font-size:12.5px;color:${T.faint};flex-grow:1">Hey, need help? Just ask me anything…</span>
           <span style="width:28px;height:28px;border-radius:9px;background:${T.accent};display:flex;align-items:center;justify-content:center;color:#160800">${icon('chevron', 15, 'currentColor', 2.4)}</span>
         </div>`, { grow: true, pad: 15 }) +
      col(
        card(cardHead('Suggested Plans', 'Run 4c81 · 3 options', 'spark', 'orange') + agents +
          `<div style="display:flex;flex-direction:column;gap:11px">${plans}</div>`, { grow: true, pad: 15 }),
        { w: '392px' }),
      { grow: true })));
}

// ── 7. Staff & Branches ──────────────────────────────────────────────────
{
  const staff = [
    ['Sakun Hansaka', 'Admin', 'sakun@moonlitbay.lk', '+94 77 412 8890', 'Weligama — Main House', 'green', 'On shift', 'SH'],
    ['Dilani Fernando', 'Manager', 'dilani@moonlitbay.lk', '+94 71 305 2214', 'Mirissa — Harbour Desk', 'green', 'On shift', 'DF'],
    ['Kasun Silva', 'Staff', 'kasun@moonlitbay.lk', '+94 76 118 7743', 'Ahangama — Surf Annex', 'green', 'On shift', 'KS'],
    ['Ishara Wick.', 'Staff', 'ishara@moonlitbay.lk', '+94 70 664 0192', 'Weligama — Main House', 'amber', 'On leave', 'IW'],
  ].map(([n, role, em, ph, br, tone, st, ini]) => [
    `<span style="display:flex;align-items:center;gap:11px;min-width:0">
       <span style="width:34px;height:34px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;font-size:11.5px;font-weight:700;color:#160800;background:linear-gradient(140deg,${T.accent2},${T.accentDim})">${ini}</span>
       <span style="min-width:0">
         <span style="display:block;font-size:12.5px;font-weight:600;color:${T.ink};letter-spacing:-0.014em">${n}</span>
         <span style="display:block;font-size:10px;color:${T.faint};margin-top:2px">${em}</span></span></span>`,
    badge(role, role === 'Admin' ? 'orange' : role === 'Manager' ? 'yellow' : 'slate'),
    txt(br, { size: 11.5, color: '#C4C4C8' }), txt(ph, { size: 11.5 }), pill(st, tone),
  ]);

  const branchCards = [
    ['Weligama — Main House', 'No. 189, Kapparatota, Fishermen Bay Hotel Road, 81700 Weligama', '+94 41 225 0189', 3, 12, 'orange', 88],
    ['Mirissa — Harbour Desk', 'Mirissa Fisheries Harbour, 81740 Mirissa', '+94 41 225 4410', 1, 6, 'cool', 62],
    ['Ahangama — Surf Annex', 'Kathaluwa West, 80650 Ahangama', '+94 91 228 7730', 2, 9, 'yellow', 74],
  ].map(([n, addr, ph, res, st, tone, load]) => `<div style="padding:13px;${surf(16)}display:flex;flex-direction:column">
    <div style="display:flex;align-items:center;gap:11px;margin-bottom:10px">
      <span style="width:34px;height:34px;border-radius:11px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:${TONES[tone]}22;color:${TONES[tone]}">${icon('pin', 16, 'currentColor', 1.7)}</span>
      <span style="min-width:0;flex-grow:1">
        <span style="display:block;font-size:12.5px;font-weight:650;color:${T.ink};letter-spacing:-0.018em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${n}</span>
        <span style="display:block;font-size:10px;color:${T.faint};margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${res} resources · ${st} staff · ${ph}</span></span>
      ${pill('Active', 'green')}</div>
    <div style="font-size:9.5px;color:#55555A;margin-bottom:10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${addr}</div>
    <div style="display:flex;align-items:center;gap:10px;margin-top:auto">
      <span style="font-size:10px;color:${T.faint};white-space:nowrap">Weekly load</span>${bar(load, tone, '100%', 5)}
      <span style="font-size:11.5px;color:${TONES[tone]};font-weight:700">${load}%</span></div>
  </div>`).join('');

  W('StaffBranches.dc.html', page('Staff', 'Resources · Staff & Branches', 'Invite member',
    grid4(
      kpi('Team Members', 'users', 'orange', 'All branches', cols([8, 8, 9, 9, 10, 10, 10, 11, 11, 11], 'orange', 232, 44), '11', '', '+1 this month', 'check') +
      kpi('On Shift Now', 'check', 'orange', 'Live', spark([6, 7, 7, 8, 8, 9, 9, 9], 'orange', 232, 44), '9', '', 'Across 3 branches', 'check') +
      kpi('On Leave', 'clock', 'amber', 'This week', cols([0, 1, 1, 0, 2, 1, 2, 2, 1, 2], 'amber', 232, 44, 9), '2', '', 'Back Sep 12', 'clock') +
      kpi('Branches', 'pin', 'orange', 'All active', cols([2, 2, 2, 3, 3, 3, 3, 3, 3, 3], 'orange', 232, 44), '3', '', 'Weligama · Mirissa · Ahangama', 'check')
    ) +
    row(
      card(cardHead('Team', '11 members · 3 branches', 'users', 'orange') +
        table(['Member', 'Role', 'Branch', 'Phone', 'Status'], staff, 'minmax(0,1.9fr) 100px minmax(0,1.5fr) minmax(0,1.1fr) 112px') +
        `<div style="margin-top:auto;padding-top:14px;border-top:1px solid ${T.lineSoft};display:flex;align-items:center;justify-content:space-between">
           ${txt('Showing 4 of 11 members', { size: 11, color: T.faint })}${btnGhost('View all')}</div>`, { grow: true, pad: 15 }) +
      col(card(cardHead('Branches', '3 active', 'pin', 'orange') + `<div style="display:flex;flex-direction:column;gap:11px">${branchCards}</div>`, { grow: true, pad: 15 }), { w: '404px' }),
      { grow: true })));
}

// ── 8. Design System sheet ───────────────────────────────────────────────
{
  const sw = (hex, name, note) => `<div style="display:flex;flex-direction:column;gap:8px;min-width:0">
    <span style="height:52px;border-radius:12px;background:${hex};border:1px solid rgba(255,255,255,0.1)"></span>
    <span><span style="display:block;font-size:11.5px;color:${T.ink};font-weight:600">${name}</span>
    <span style="display:block;font-size:10px;color:${T.faint};margin-top:2px">${hex}</span>
    <span style="display:block;font-size:9.5px;color:#55555A;margin-top:2px">${note}</span></span></div>`;
  const tr = (s, spec, size, weight) => `<div style="display:flex;align-items:baseline;gap:18px;padding:8px 0;border-top:1px solid ${T.lineSoft}">
    <span style="font-size:${size}px;font-weight:${weight};color:${T.ink};letter-spacing:-0.03em;line-height:1.15;flex-grow:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${s}</span>
    <span style="font-size:9.5px;color:${T.faint};white-space:nowrap">${spec}</span></div>`;

  const railStrip = GROUPS.map((g, i) => `<div style="display:flex;flex-direction:column;align-items:center;gap:6px">
    <div style="width:38px;height:38px;border-radius:50%;display:flex;align-items:center;justify-content:center;${i === 0 ? 'background:#F2F2F3;color:#0A0A0B' : `background:rgba(255,255,255,0.05);border:1px solid ${T.line};color:#B4B4B8`}">${icon(g.ic, 17, 'currentColor', 1.7)}</div>
    <span style="font-size:8.5px;color:${T.faint};white-space:nowrap">${g.name}</span>
    <span style="font-size:8.5px;color:#4A4A4F">${g.items.length}</span></div>`).join('');

  W('DesignSystem.dc.html', `<!doctype html>
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
<div style="width:1600px;height:900px;overflow:hidden;display:flex;flex-direction:column;gap:14px;padding:24px;background:${T.bg};color:${T.ink};font-family:${T.font}">
  <div style="display:flex;align-items:center;gap:14px">
    ${logo(40)}
    <div><h1 style="margin:0;font-size:24px;font-weight:700;letter-spacing:-0.035em">Unify Design System</h1>
    <p style="margin:4px 0 0;font-size:12px;color:${T.dim}">Warm near-black · flat surfaces · the vocabulary every screen is built from</p></div>
  </div>
  <div style="display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,1fr) minmax(0,1.05fr);gap:14px;flex-grow:1;min-height:0">
    <div style="display:flex;flex-direction:column;gap:14px;min-width:0">
      ${card(cardHead('Colour', 'Flat canvas, warm accent', 'analytics', 'orange') +
    `<div style="display:grid;grid-template-columns:repeat(4, minmax(0,1fr));gap:11px">
        ${sw('#0A0A0B', 'Canvas', 'flat, no gradient')}${sw('#161618', 'Card', '4% white over canvas')}
        ${sw('#FF6B2C', 'Accent', 'primary action')}${sw('#FFC940', 'Chart high', 'peaks, highlights')}
        ${sw('#4ADE80', 'Available', 'status')}${sw('#FBBF24', 'Alert', 'status')}
        ${sw('#F87171', 'Critical', 'status')}${sw('#9A9A9F', 'Secondary', 'body text')}</div>`, { pad: 15 })}
      ${card(cardHead('Typography', 'SF Pro / system stack', 'edit', 'orange') +
      tr('Resource Manager', '23 / 700', 22, 700) + tr('Weekly Availability', '13 / 650', 13, 650) +
      tr('Sea View Double — Room 1', '12.5 / 600', 12.5, 600) + tr('Rooms and vehicles', '11.5 / 500', 11.5, 500) +
      `<div style="display:flex;align-items:baseline;gap:18px;padding:8px 0;border-top:1px solid ${T.lineSoft}">
         <span style="font-size:28px;font-weight:700;letter-spacing:-0.04em;line-height:1;flex-grow:1">19,840</span>
         <span style="font-size:9.5px;color:${T.faint}">28 / 700 · KPI numeral</span></div>`, { pad: 15, grow: true })}
    </div>
    <div style="display:flex;flex-direction:column;gap:14px;min-width:0">
      ${card(cardHead('Icon rail', 'All 18 pages, 6 groups', 'home', 'orange') +
        `<div style="display:flex;justify-content:space-between;gap:6px;padding:4px 0 12px">${railStrip}</div>
         <p style="margin:0;font-size:11px;color:${T.dim};line-height:1.6;border-top:1px solid ${T.lineSoft};padding-top:11px">Every NAV_ITEMS entry keeps a home. Selecting a rail icon opens its section list, so nothing that was one click away is now unreachable.</p>`, { pad: 15 })}
      ${card(cardHead('Surface & status', 'One card recipe', 'box', 'orange') +
          `<div style="${surf(14)}padding:13px;margin-bottom:11px">
           <div style="font-size:11.5px;color:${T.ink};font-weight:600;margin-bottom:6px">Card anatomy</div>
           <div style="font-size:10.5px;color:${T.dim};line-height:1.7">4% white fill · 1px rgba(255,255,255,0.07)<br>radius 18px · pad 15px · blur 18px<br>no glow, no gradient wash</div></div>
         <div style="display:flex;flex-wrap:wrap;gap:7px">${pill('Available', 'green')}${pill('Reserved', 'yellow')}${pill('Maintenance', 'amber')}${pill('Critical', 'red')}</div>
         <div style="display:flex;flex-wrap:wrap;gap:7px;margin-top:10px">${badge('Room', 'orange')}${badge('Equipment', 'yellow')}${badge('Vehicle', 'cool')}${badge('Staff', 'green')}</div>
         <div style="display:flex;gap:8px;margin-top:12px">${btnPrimary('Primary')}${btnGhost('Secondary')}</div>`, { pad: 15, grow: true })}
    </div>
    <div style="display:flex;flex-direction:column;gap:14px;min-width:0">
      ${card(cardHead('Micro-charts', 'The data layer', 'bars', 'orange') +
            `<div style="display:flex;flex-direction:column;gap:13px">
           <div><div style="font-size:9.5px;color:${T.faint};margin-bottom:6px;letter-spacing:0.06em;text-transform:uppercase">Scatter rows</div>
             ${scatter([['Room nights', [[0.05, 0.7], [0.2, 0.45], [0.4, 0.9], [0.6, 0.6], [0.8, 0.75]], 'orange'], ['Lessons', [[0.1, 0.5], [0.3, 0.85], [0.55, 0.6], [0.75, 0.9]], 'yellow']], ['08', '12', '18', '22'], 330)}</div>
           <div><div style="font-size:9.5px;color:${T.faint};margin-bottom:6px;letter-spacing:0.06em;text-transform:uppercase">Dual line · block columns</div>
             <div style="display:flex;gap:14px">${dualLine([2, 3, 2.5, 4, 3.6, 4.4], [1.4, 1.8, 2.2, 2.6, 3, 3.3], ['4', '2', '0'], ['08', '18'], 150, 52)}${blockCols([3, 5, 4, 6, 5, 7, 4], ['M', 'T', 'W', 'T', 'F', 'S', 'S'], 150, 52, [3, 5])}</div></div>
           <div><div style="font-size:9.5px;color:${T.faint};margin-bottom:6px;letter-spacing:0.06em;text-transform:uppercase">Waveform</div>${waveform(60, 330, 46)}</div>
         </div>`, { pad: 15 })}
      ${card(`<div style="display:flex;align-items:center;gap:14px;flex-grow:1">
           ${tickGauge(67, 150, '67%', 'Gauge')}
           <div style="flex-grow:1;min-width:0">
             <div style="font-size:9.5px;color:${T.faint};margin-bottom:7px;letter-spacing:0.06em;text-transform:uppercase">Heatmap</div>
             ${heatmap(['Rooms', 'Boards'], [[0.3, 0.5, 0.65, 0.85, 1, 1, 0.9], [0.2, 0.3, 0.45, 0.6, 0.8, 0.95, 0.7]], 19, 4)}
             <div style="margin-top:11px">${dualWave(220, 46)}</div>
           </div></div>`, { pad: 15, grow: true })}
    </div>
  </div>
</div>
</x-dc>
</body>
</html>
`);
}

// ── Canvas ───────────────────────────────────────────────────────────────
const AB = [
  ['Dashboard.dc.html', 0, 0], ['Main.dc.html', 1720, 0],
  ['BookingManager.dc.html', 0, 1060], ['MultiBranch.dc.html', 1720, 1060],
  ['Inventory.dc.html', 0, 2120], ['AIPlanner.dc.html', 1720, 2120],
  ['StaffBranches.dc.html', 0, 3180], ['DesignSystem.dc.html', 1720, 3180],
];
W('canvas.json', JSON.stringify({
  artboards: AB.map(([file, x, y]) => ({ file, x, y, w: 1600, h: 900 })),
  annotations: [
    { id: 'kit-intro', x: 0, y: -160, w: 760, text: 'Unify — warm near-black UI kit\nBuilt to the reference dashboard: flat #0A0A0B canvas (no gradient wash), warm orange accent, icon rail, and the reference micro-chart family. 8 artboards at 1600×900.' },
    { id: 'note-nav', x: 1720, y: -160, w: 700, text: 'Resource Manager shows the rail section list open — all 18 NAV_ITEMS stay reachable behind 6 grouped rail icons, so the narrow rail costs no function.' },
  ],
  launch: { view: 'canvas' },
}, null, 2));
console.log(`wrote ${AB.length} artboards + canvas.json`);
