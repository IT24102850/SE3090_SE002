import { useGetSafetyPanelQuery } from '../../../api/bookingApi';
import type { SafetyGearItem } from '../../booking/types';

/* Safety & compliance: life jackets against licensed capacity, and
 * expiry-dated gear (life raft servicing, flares, extinguishers, EPIRB,
 * first-aid kits).
 *
 * Gear with no expiry date is shown without a date badge rather than
 * flagged: most equipment simply does not expire, and every row that
 * predates the ExpiryDate column has none. Treating null as "expired"
 * would bury the handful of items that genuinely need attention. */

function GearRow({ item }: { item: SafetyGearItem }) {
  return (
    <li
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        gap: 8,
        padding: '5px 0',
        fontSize: '0.83rem',
        borderBottom: '1px solid var(--color-border)',
      }}
    >
      <span>
        {item.name}
        <span style={{ color: 'var(--color-text-muted)' }}> · {item.quantity}</span>
      </span>
      {item.expiryDate ? (
        <span
          className={`badge ${item.isExpired ? 'badge-critical' : item.isExpiringSoon ? 'badge-warning' : 'badge-neutral'}`}
        >
          {item.isExpired ? 'Expired' : item.isExpiringSoon ? 'Expiring' : 'Valid'}{' '}
          {new Date(item.expiryDate).toLocaleDateString()}
        </span>
      ) : (
        <span style={{ color: 'var(--color-text-muted)', fontSize: '0.78rem' }}>no expiry tracked</span>
      )}
    </li>
  );
}

export default function SafetyPanel({ equipmentTerm }: { equipmentTerm: string }) {
  const { data, isLoading } = useGetSafetyPanelQuery({ expiringWithinDays: 60 });

  if (isLoading) {
    return (
      <div className="card">
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading safety data…</div>
      </div>
    );
  }

  const vessels = data?.vessels ?? [];

  return (
    <div className="card chart-card" style={{ padding: 16 }}>
      <p className="chart-title" style={{ margin: 0 }}>{equipmentTerm}</p>
      <p className="chart-subtitle" style={{ margin: '0 0 12px' }}>
        {data?.expiredCount ?? 0} expired · {data?.expiringSoonCount ?? 0} expiring within 60 days
      </p>

      {vessels.length === 0 ? (
        <p style={{ color: 'var(--color-text-muted)', fontSize: '0.85rem' }}>
          No vessels registered yet. Add them as Vehicle-category resources to track safety gear against capacity.
        </p>
      ) : (
        <div style={{ display: 'grid', gap: 14 }}>
          {vessels.map((v) => (
            <div key={v.resourceId}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                <strong style={{ fontSize: '0.92rem' }}>{v.vesselName}</strong>
                <span className={`badge ${v.jacketsSufficient ? 'badge-good' : 'badge-critical'}`}>
                  {v.lifeJacketCount} jackets / {v.licensedCapacity || '—'} pax
                  {!v.jacketsSufficient && ` · ${v.lifeJacketShortfall} short`}
                </span>
              </div>
              {v.equipment.length === 0 ? (
                <p style={{ fontSize: '0.8rem', color: 'var(--color-text-muted)', margin: '4px 0 0' }}>
                  No gear recorded against this vessel. Name equipment items after the vessel to link them.
                </p>
              ) : (
                <ul style={{ listStyle: 'none', padding: 0, margin: '6px 0 0' }}>
                  {v.equipment.map((item) => (
                    <GearRow key={item.equipmentItemId} item={item} />
                  ))}
                </ul>
              )}
            </div>
          ))}
        </div>
      )}

      {(data?.sharedEquipment.length ?? 0) > 0 && (
        <div style={{ marginTop: 16 }}>
          <p className="chart-subtitle" style={{ margin: '0 0 4px' }}>Shared gear</p>
          <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
            {data!.sharedEquipment.map((item) => (
              <GearRow key={item.equipmentItemId} item={item} />
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
