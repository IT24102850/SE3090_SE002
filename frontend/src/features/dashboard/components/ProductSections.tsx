import { Link } from 'react-router-dom';
import type { BookingType } from '../../booking/types';
import {
  getProductCategory,
  parseProductConfig,
  PRODUCT_CATEGORY_LABELS,
} from '../productCategory';

/* The two product sections of the whale-watching dashboard:
 *
 *   Packages & Tours  - the trips this operator sells (category tour/package)
 *   Services & Add-ons - the extras attached to them (category addon)
 *
 * Both read the same booking types the rest of the app already uses; the
 * only thing separating them is the `category` key on ConfigJson. Editing
 * anything sends the operator to /booking-types, the page that already owns
 * product editing - this dashboard shows, it does not duplicate that editor.
 */

function money(value: number | undefined, currency: string): string | null {
  if (value === undefined || value === null || Number.isNaN(value)) return null;
  return `${currency} ${value.toLocaleString()}`;
}

function StatusChip({ status }: { status: BookingType['status'] }) {
  // Inactive and Archived are both "not on sale"; the operator only needs to
  // know it is not being sold, and Archived products are filtered out anyway.
  const active = status === 'Active';
  return (
    <span className={`badge ${active ? 'badge-good' : 'badge-neutral'}`}>
      {active ? 'Active' : 'Hidden'}
    </span>
  );
}

/** One line of a product's rate card: "Adult / Above 12 years / LKR 7,500".
 *  The band is omitted rather than guessed when the operator publishes no
 *  age policy - plenty of products have one rate and no age split at all. */
function TicketRow({ label, band, price }: { label: string; band: string | null; price: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
      <span>
        {label}
        {band && (
          <span style={{ color: 'var(--color-text-muted)', fontSize: '0.75rem', marginLeft: 6 }}>{band}</span>
        )}
      </span>
      <strong style={{ whiteSpace: 'nowrap' }}>{price}</strong>
    </div>
  );
}

function TourCard({ product }: { product: BookingType }) {
  const config = parseProductConfig(product.configJson);
  const currency = config.pricing?.currency ?? 'LKR';
  const adult = money(config.pricing?.adult, currency);
  const child = money(config.pricing?.child, currency);
  const category = getProductCategory(product.configJson);
  const seasonal = Array.isArray(config.seasonalPricing) && config.seasonalPricing.length > 0;

  return (
    <div className="card" style={{ padding: 14 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
        <strong style={{ fontSize: '0.95rem' }}>
          {config.icon && <span style={{ marginRight: 6 }}>{config.icon}</span>}
          {product.name}
        </strong>
        <StatusChip status={product.status} />
      </div>
      {product.description && (
        <p style={{ margin: '6px 0 0', fontSize: '0.8rem', color: 'var(--color-text-secondary)' }}>
          {product.description}
        </p>
      )}

      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', margin: '8px 0' }}>
        <span className="badge badge-primary">{PRODUCT_CATEGORY_LABELS[category]}</span>
        <span className="badge badge-neutral">{product.bookingUnit}</span>
        {seasonal && <span className="badge badge-warning">Seasonal pricing</span>}
      </div>

      <div style={{ fontSize: '0.82rem', color: 'var(--color-text-secondary)' }}>
        {product.defaultDurationMinutes} min
        {product.maxParticipants ? ` · up to ${product.maxParticipants} pax` : ''}
      </div>

      {/* The ticket table, mirroring the operator's own rate card: one row
          per ticket type, with the age band it applies to. */}
      <div style={{ marginTop: 10, fontSize: '0.85rem' }}>
        {adult || child ? (
          <div style={{ display: 'grid', gap: 4 }}>
            {adult && (
              <TicketRow
                label="Adult"
                band={config.agePolicy?.adultFromAge ? `Above ${config.agePolicy.adultFromAge} years` : null}
                price={adult}
              />
            )}
            {/* A missing child rate means "no child rate exists", which is
                not the same as free - so it is omitted, not shown as 0. */}
            {child && (
              <TicketRow
                label="Child"
                band={config.agePolicy?.childUnderAge ? `Below ${config.agePolicy.childUnderAge} years` : null}
                price={child}
              />
            )}
          </div>
        ) : (
          <span style={{ color: 'var(--color-text-muted)' }}>No per-ticket pricing configured</span>
        )}
      </div>

      {config.includes && config.includes.length > 0 && (
        <ul style={{ listStyle: 'none', padding: 0, margin: '10px 0 0', display: 'grid', gap: 2 }}>
          {config.includes.map((item) => (
            <li key={item} style={{ fontSize: '0.78rem', color: 'var(--color-text-secondary)' }}>
              <span style={{ color: 'var(--color-good)', marginRight: 6 }}>+</span>
              {item}
            </li>
          ))}
        </ul>
      )}

      <div style={{ marginTop: 12 }}>
        <Link className="btn btn-secondary btn-sm" to="/booking-types">Edit</Link>
      </div>
    </div>
  );
}

function AddonCard({ product }: { product: BookingType }) {
  const config = parseProductConfig(product.configJson);
  const currency = config.pricing?.currency ?? 'LKR';
  // An add-on is normally one flat price; adult is where a single price is
  // stored, so it is the primary, with child as a fallback.
  // 0 here is a real, published price - the free 3km transfer - so it reads
  // as "Free" rather than "LKR 0", which looks like missing data.
  const raw = config.pricing?.adult ?? config.pricing?.child;
  const price = raw === 0 ? 'Free' : money(raw, currency);

  return (
    <div
      className="card"
      style={{ padding: '10px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}
    >
      <div style={{ minWidth: 0 }}>
        <div style={{ fontWeight: 600, fontSize: '0.88rem' }}>
          {config.icon && <span style={{ marginRight: 6 }}>{config.icon}</span>}
          {product.name}
        </div>
        <div style={{ fontSize: '0.76rem', color: 'var(--color-text-muted)' }}>
          {product.bookingUnit}
          {product.status !== 'Active' && ' · hidden'}
        </div>
      </div>
      <strong style={{ fontSize: '0.88rem', whiteSpace: 'nowrap' }}>
        {price ?? <span style={{ color: 'var(--color-text-muted)', fontWeight: 400 }}>No price</span>}
      </strong>
    </div>
  );
}

export function PackagesAndTours({
  products,
  loading,
}: {
  products: BookingType[];
  loading: boolean;
}) {
  return (
    <section style={{ marginTop: 28 }}>
      <div className="page-header" style={{ marginBottom: 12 }}>
        <div>
          <h2 className="page-title" style={{ fontSize: '1.15rem' }}>Packages &amp; Tours</h2>
          <p className="page-subtitle">The trips you sell, with adult and child pricing.</p>
        </div>
        <Link className="btn btn-primary btn-sm" to="/booking-types">New tour</Link>
      </div>

      {loading ? (
        <div className="card"><div className="loading-row"><span className="spinner spinner-dark" /> Loading products…</div></div>
      ) : products.length === 0 ? (
        <div className="card" style={{ padding: 24, color: 'var(--color-text-muted)' }}>
          No tours or packages yet. Create one under Booking Types and it will appear here.
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: 12 }}>
          {products.map((p) => <TourCard key={p.id} product={p} />)}
        </div>
      )}
    </section>
  );
}

export function ServicesAndAddons({
  products,
  loading,
}: {
  products: BookingType[];
  loading: boolean;
}) {
  return (
    <section style={{ marginTop: 28 }}>
      <div className="page-header" style={{ marginBottom: 12 }}>
        <div>
          <h2 className="page-title" style={{ fontSize: '1.15rem' }}>Services &amp; Add-ons</h2>
          <p className="page-subtitle">Extras guests attach to a booking — pickup, photos, gear.</p>
        </div>
        <Link className="btn btn-secondary btn-sm" to="/booking-types">Manage</Link>
      </div>

      {loading ? (
        <div className="card"><div className="loading-row"><span className="spinner spinner-dark" /> Loading services…</div></div>
      ) : products.length === 0 ? (
        <div className="card" style={{ padding: 20, color: 'var(--color-text-muted)', fontSize: '0.88rem' }}>
          No add-ons yet. Tag a booking type with <code>"category": "addon"</code> in its config to list it here.
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: 10 }}>
          {products.map((p) => <AddonCard key={p.id} product={p} />)}
        </div>
      )}
    </section>
  );
}
