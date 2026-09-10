import { useRef } from 'react';
import { usePinnedProgress } from './scroll/useScrollMotion';

/* The section the page exists for.
 *
 * Pinned while the visitor scrolls through six trades. The mockup chrome
 * never changes - same window, same header, same shape - and only the modules
 * and rows inside it swap. That is the entire pitch made visible: one
 * platform, provisioned differently. If the frame changed too it would look
 * like six different products.
 *
 * Given the most scroll of any section, per the brief.
 */

interface BizType {
  name: string;
  workspace: string;
  modules: string[];
  rows: [string, string][];
  note: string;
}

const TYPES: BizType[] = [
  {
    name: 'Dive centre',
    workspace: 'Blue Reef Diving',
    modules: ['Bookings', 'Boats', 'Gear', 'Instructors'],
    rows: [
      ['06:30 · Reef dive', '8 / 12 divers'],
      ['Tanks filled', '24 of 30'],
      ['Nitrox cert · expires', '14 days'],
    ],
    note: 'Boats, tank stock and instructor rosters. Certification levels sit on the booking, so an unqualified diver cannot be put on a deep dive.',
  },
  {
    name: 'Homestay',
    workspace: 'Palm House',
    modules: ['Rooms', 'Rates', 'Check-ins', 'Housekeeping'],
    rows: [
      ['Tonight', '4 of 6 rooms'],
      ['Arriving today', '2 guests'],
      ['Room 3 · turnaround', 'due 11:00'],
    ],
    note: 'Rooms priced per night with a cleaning gap between stays. Check-in and check-out are the day, so they are the first thing on the screen.',
  },
  {
    name: 'Salon',
    workspace: 'Studio Nine',
    modules: ['Chairs', 'Stylists', 'Services', 'Products'],
    rows: [
      ['Chair 2 · colour', '13:00 – 15:30'],
      ['Walk-in waiting', '1'],
      ['Retail stock low', '3 lines'],
    ],
    note: 'A calendar per chair rather than per room. Services carry their own duration, so a colour books the chair for three hours and a trim for twenty minutes.',
  },
  {
    name: 'Restaurant',
    workspace: 'Cinnamon Table',
    modules: ['Tables', 'Covers', 'Shifts', 'Suppliers'],
    rows: [
      ['Tonight · covers', '62 booked'],
      ['Table 11 · 8pm', 'party of 6'],
      ['Delivery due', 'tomorrow 07:00'],
    ],
    note: 'Tables with sittings rather than all-day slots, and a supplier ledger behind the stock, because the order goes in before service not after it.',
  },
  {
    name: 'Gym',
    workspace: 'Iron Yard',
    modules: ['Classes', 'Members', 'Trainers', 'Equipment'],
    rows: [
      ['18:00 · Strength', '14 / 16 places'],
      ['Memberships expiring', '7 this week'],
      ['Rower 2 · service', 'overdue'],
    ],
    note: 'Recurring classes with a capacity, plus memberships that lapse. Equipment maintenance is tracked because a broken rower is a refund conversation.',
  },
  {
    name: 'Tuition class',
    workspace: 'Bright Path',
    modules: ['Batches', 'Students', 'Tutors', 'Fees'],
    rows: [
      ['Grade 10 · Maths', 'Mon & Thu 16:00'],
      ['Attendance today', '18 of 21'],
      ['Fees outstanding', '4 students'],
    ],
    note: 'Batches that repeat weekly for a term, attendance per session, and fees that are owed by month rather than paid at the door.',
  },
];

export default function BusinessTypes() {
  const ref = useRef<HTMLElement>(null);
  const progress = usePinnedProgress(ref);

  // Each type owns an equal slice of the pin. Clamped at the last one so the
  // final type stays on screen through the tail of the section rather than
  // flicking past as the pin releases.
  const index = Math.min(Math.floor(progress * TYPES.length), TYPES.length - 1);
  const active = TYPES[index];
  const within = progress * TYPES.length - index;

  return (
    <section
      className="lp-types"
      id="business-types"
      ref={ref}
      style={{ height: `${TYPES.length * 100 + 60}vh` }}
      aria-label="Business types"
    >
      <div className="lp-types-sticky">
        <div>
          <p className="lp-label">
            <span className="lp-label-n">03</span>
            <span className="lp-label-rule" />
            Business types
          </p>
          <h2 className="lp-h2">The same platform, shaped six ways.</h2>
          <p className="lp-body" style={{ marginBottom: 30 }}>
            Pick what you do when you sign up. The workspace comes provisioned with
            the modules that trade needs and none of the ones it does not.
          </p>

          <div className="lp-types-list">
            {TYPES.map((t, i) => (
              <div key={t.name} className={`lp-type-item${i === index ? ' is-active' : ''}`}>
                <span className="lp-type-index">{String(i + 1).padStart(2, '0')}</span>
                <span className="lp-type-name">{t.name}</span>
                <span className="lp-type-bar" aria-hidden="true">
                  {/* Fills across the slice of scroll this type owns, so the
                      rail doubles as a progress readout for the section. */}
                  <span style={{ transform: `scaleX(${i === index ? within : i < index ? 1 : 0})` }} />
                </span>
              </div>
            ))}
          </div>
        </div>

        <div>
          <div className="lp-mock">
            <div className="lp-mock-chrome">
              <span className="lp-mock-dot" /><span className="lp-mock-dot" /><span className="lp-mock-dot" />
              <span className="lp-mock-title">{active.workspace}</span>
            </div>

            <div className="lp-mock-modules">
              {active.modules.map((m) => (
                <div className="lp-mock-module" key={m}>{m}</div>
              ))}
            </div>

            <div className="lp-mock-rows">
              {active.rows.map(([label, value]) => (
                <div className="lp-mock-row" key={label}>
                  <span>{label}</span>
                  <b>{value}</b>
                </div>
              ))}
            </div>
          </div>
          <p className="lp-mock-note">{active.note}</p>
        </div>
      </div>
    </section>
  );
}
