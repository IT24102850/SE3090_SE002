import { useEffect, useState } from 'react';
import { useQuoteTicketsMutation } from '../../../api/bookingApi';
import { TICKET_TYPES, type TicketLine } from '../../booking/types';

/* The "2 adults + 1 child" control.
 *
 * The prices shown come from the server's quote endpoint, never from the
 * client: unit prices live on BookingType.ConfigJson and are re-resolved
 * server-side on create, so anything this component displays is a preview
 * of what the server will charge, not an input to it. */

export default function TicketBreakdownField({
  bookingTypeId,
  startTime,
  value,
  onChange,
}: {
  bookingTypeId: string;
  startTime: string;
  value: TicketLine[];
  onChange: (lines: TicketLine[]) => void;
}) {
  const [quote, { data: quoted }] = useQuoteTicketsMutation();
  const [error, setError] = useState<string | null>(null);

  const qtyOf = (type: string) => value.find((l) => l.type === type)?.qty ?? 0;

  const setQty = (type: string, qty: number) => {
    const next = value.filter((l) => l.type !== type);
    if (qty > 0) next.push({ type, qty });
    // Keep the canonical Adult/Child/Infant order so the summary line and
    // the manifest read the same way everywhere.
    next.sort((a, b) => TICKET_TYPES.indexOf(a.type as never) - TICKET_TYPES.indexOf(b.type as never));
    onChange(next);
  };

  // Re-quote whenever the mix, the type, or the date changes - a seasonal
  // window can move the price between two dates on the same booking type.
  useEffect(() => {
    if (!bookingTypeId || value.length === 0) return;
    let cancelled = false;
    quote({ bookingTypeId, startTime, ticketBreakdown: value })
      .unwrap()
      .then(() => { if (!cancelled) setError(null); })
      .catch(() => { if (!cancelled) setError('Could not price these tickets.'); });
    return () => { cancelled = true; };
  }, [bookingTypeId, startTime, value, quote]);

  const totalQty = value.reduce((sum, l) => sum + l.qty, 0);

  return (
    <div className="field field-full">
      <label>Tickets</label>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        {TICKET_TYPES.map((type) => (
          <div key={type} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: '0.85rem', minWidth: 48 }}>{type}</span>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() => setQty(type, Math.max(qtyOf(type) - 1, 0))}
              aria-label={`One fewer ${type.toLowerCase()} ticket`}
            >
              −
            </button>
            <span style={{ minWidth: 20, textAlign: 'center', fontWeight: 700 }}>{qtyOf(type)}</span>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() => setQty(type, qtyOf(type) + 1)}
              aria-label={`One more ${type.toLowerCase()} ticket`}
            >
              +
            </button>
          </div>
        ))}
      </div>

      {totalQty > 0 && (
        <div style={{ marginTop: 8, fontSize: '0.85rem' }}>
          {error ? (
            <span style={{ color: 'var(--color-critical)' }}>{error}</span>
          ) : quoted ? (
            <>
              <span style={{ color: 'var(--color-text-secondary)' }}>
                {quoted.lines.map((l) => `${l.qty} × ${l.type} @ ${l.unitPrice ?? 0}`).join('  ·  ')}
              </span>
              <strong style={{ marginLeft: 8 }}>
                {quoted.currency} {quoted.total.toLocaleString()}
              </strong>
              {quoted.seasonLabel && (
                <span
                  className={`badge ${quoted.isOffPeakRate ? 'badge-good' : 'badge-primary'}`}
                  style={{ marginLeft: 8 }}
                >
                  {quoted.isOffPeakRate ? 'Off-peak rate' : quoted.seasonLabel}
                </span>
              )}
              {quoted.inSeason === false && (
                <span className="badge badge-warning" style={{ marginLeft: 8 }}>
                  Outside the declared season
                </span>
              )}
            </>
          ) : (
            <span style={{ color: 'var(--color-text-muted)' }}>Pricing…</span>
          )}
        </div>
      )}
      <p style={{ fontSize: '0.78rem', color: 'var(--color-text-muted)', margin: '6px 0 0' }}>
        Capacity is consumed by the total headcount, infants included. Leave every count at zero to book
        without a ticket breakdown.
      </p>
    </div>
  );
}
