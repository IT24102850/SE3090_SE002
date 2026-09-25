import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import type { RootState } from '../store/store';
import { useGetTenantQuery } from '../api/bookingApi';

/* The /admin route was a bare "Admin Panel" heading with nothing behind it.
 *
 * Rather than invent a panel, this is an index of the administration pages
 * that genuinely exist, plus the tenant facts an admin most often needs to
 * read off (the tenant id is what every support question starts with). Every
 * card here links somewhere real - nothing is a placeholder for a screen that
 * has not been built. */

const AREAS = [
  {
    to: '/settings',
    icon: '⚙️',
    title: 'Business settings',
    body: 'Business name, logo, and the reschedule and cancellation cutoff windows that govern every booking.',
  },
  {
    to: '/business-profile',
    icon: '🏪',
    title: 'Business profile',
    body: 'The public listing: cover image, gallery, description, amenities, contact details and opening hours.',
  },
  {
    to: '/staff',
    icon: '🧑‍💼',
    title: 'Staff',
    body: 'Invite managers and staff, assign them to a branch, and deactivate accounts that should no longer sign in.',
  },
  {
    to: '/branches',
    icon: '📍',
    title: 'Branches',
    body: 'Locations bookings and stock are scoped to. Resources and staff each belong to one.',
  },
  {
    to: '/booking-types',
    icon: '🏷️',
    title: 'Products & booking types',
    body: 'What you sell, how long it takes, what it costs, and whether it needs approval before it is confirmed.',
  },
  {
    to: '/resources',
    icon: '🏢',
    title: 'Resources',
    body: 'Rooms, vessels, vehicles, equipment and staff — with their weekly hours and one-off closures.',
  },
];

export default function AdminPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Administration</h1>
          <p className="page-subtitle">Everything that configures how this business works.</p>
        </div>
      </div>

      <div className="stat-grid">
        <div className="stat-tile">
          <div className="stat-tile-label">Business</div>
          <div className="stat-tile-value" style={{ fontSize: '1.1rem' }}>{tenant?.name ?? '—'}</div>
          <div className="stat-tile-sub">{tenant?.businessType ?? ''}</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Sub-type</div>
          <div className="stat-tile-value" style={{ fontSize: '1.1rem' }}>{tenant?.subType ?? 'Not set'}</div>
          <div className="stat-tile-sub">decides your dashboard</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Reschedule cutoff</div>
          <div className="stat-tile-value">
            {tenant ? `${tenant.rescheduleCutoffHours}h` : '—'}
          </div>
          <div className="stat-tile-sub">before start time</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Cancellation cutoff</div>
          <div className="stat-tile-value">
            {tenant ? `${tenant.cancellationCutoffHours}h` : '—'}
          </div>
          <div className="stat-tile-sub">before start time</div>
        </div>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
          gap: 14,
          marginTop: 20,
        }}
      >
        {AREAS.map((area) => (
          <Link
            key={area.to}
            to={area.to}
            className="card"
            style={{ padding: 18, textDecoration: 'none', color: 'inherit', display: 'block' }}
          >
            <div style={{ fontSize: '1.4rem', marginBottom: 8 }}>{area.icon}</div>
            <strong style={{ fontSize: '0.95rem' }}>{area.title}</strong>
            <p style={{ margin: '6px 0 0', fontSize: '0.83rem', color: 'var(--color-text-secondary)', lineHeight: 1.5 }}>
              {area.body}
            </p>
          </Link>
        ))}
      </div>

      {tenantId && (
        <p style={{ marginTop: 20, fontSize: '0.78rem', color: 'var(--color-text-muted)' }}>
          Tenant ID <code>{tenantId}</code> — quote this in any support request.
        </p>
      )}
    </div>
  );
}
