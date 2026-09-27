import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { useGetBranchesQuery, useGetTenantProfileQuery, useGetTenantQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { businessDescriptor, businessHeroImage } from '../../shared/businessImagery';
import BusinessAvatar from '../../shared/components/BusinessAvatar';
import './customer.css';

/* The business page a customer sees - the web twin of the Flutter
 * BusinessDetailScreen's header: cover, logo, tagline, description,
 * opening hours with today highlighted, amenities, gallery, branches and
 * contact links. Read-only; the business edits it under Settings. */

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const SOCIAL_LABEL: Record<string, string> = { facebook: 'Facebook', instagram: 'Instagram', whatsapp: 'WhatsApp', youtube: 'YouTube', tiktok: 'TikTok', twitter: 'X / Twitter', linkedin: 'LinkedIn', tripadvisor: 'Tripadvisor', ubereats: 'Uber Eats', pickme: 'PickMe Food' };

export default function BusinessInfoPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const { data: profile, isLoading } = useGetTenantProfileQuery({ tenantId }, { skip: !tenantId });
  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const todayName = DAYS[new Date().getDay()];
  const heroImage = businessHeroImage({ businessType: tenant?.businessType, subType: tenant?.subType, coverImageUrl: profile?.coverImageUrl });
  const hours = profile ? [...profile.businessHours].sort((a, b) => ((DAYS.indexOf(a.dayOfWeek) + 6) % 7) - ((DAYS.indexOf(b.dayOfWeek) + 6) % 7)) : [];

  return (
    <div className="cust-page">
      <section className="hero" style={{ marginBottom: 0 }}>
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div className="hero-identity">
              <BusinessAvatar name={tenant?.name} src={profile?.logoUrl} size={72} />
              <div>
                <p className="hero-eyebrow">{businessDescriptor({ businessType: tenant?.businessType, subType: tenant?.subType })}</p>
                <h1 className="hero-title">{tenant?.name ?? '…'}</h1>
                {profile?.shortTagline && <p className="hero-sub">{profile.shortTagline}</p>}
                {profile?.averageRating ? <p className="hero-sub">★ {profile.averageRating.toFixed(1)} · {profile.reviewCount} reviews</p> : null}
              </div>
            </div>
            <div className="cust-hero-actions"><Link className="btn btn-primary" to="/book">Book now</Link></div>
          </div>
        </div>
      </section>

      {isLoading ? (
        <div className="loading-row"><span className="spinner spinner-dark" /></div>
      ) : (
        <div className="cust-business">
          <div style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
            <section className="card chart-card">
              <p className="chart-title">About</p>
              <p style={{ margin: 0, fontSize: '.9rem', lineHeight: 1.6, color: 'var(--color-text-secondary)' }}>{profile?.description || 'The business has not written a description yet.'}</p>
              {(profile?.amenities.length ?? 0) > 0 && (
                <>
                  <p className="cust-subhead" style={{ marginTop: 16 }}>What you get</p>
                  <div className="cust-amenities">{profile!.amenities.map((a) => <span key={a}>{a}</span>)}</div>
                </>
              )}
            </section>
            {(profile?.galleryImageUrls.length ?? 0) > 0 && (
              <section className="card chart-card">
                <p className="chart-title">Gallery</p>
                <div className="cust-gallery">{profile!.galleryImageUrls.map((url) => <img key={url} src={url} alt="" loading="lazy" />)}</div>
              </section>
            )}
          </div>
          <div style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
            <section className="card chart-card">
              <p className="chart-title">Opening hours</p>
              {hours.length === 0 ? <div className="cust-empty">Not published.</div> : (
                <div className="cust-hours">
                  {hours.map((h) => (
                    <div key={h.dayOfWeek} className={h.dayOfWeek === todayName ? 'today' : undefined}>
                      <b>{h.dayOfWeek}{h.dayOfWeek === todayName ? ' · today' : ''}</b>
                      <span>{h.isClosed ? 'Closed' : `${h.openTime} – ${h.closeTime}`}</span>
                    </div>
                  ))}
                </div>
              )}
            </section>
            <section className="card chart-card">
              <p className="chart-title">Contact</p>
              <div className="cust-contact">
                {profile?.contactPhone && <span>📞 <a href={`tel:${profile.contactPhone}`}>{profile.contactPhone}</a></span>}
                {profile?.contactEmail && <span>✉️ <a href={`mailto:${profile.contactEmail}`}>{profile.contactEmail}</a></span>}
                {profile?.website && <span>🌐 <a href={profile.website} target="_blank" rel="noreferrer">{profile.website.replace(/^https?:\/\//, '')}</a></span>}
                {Object.entries(profile?.socialLinks ?? {}).map(([k, url]) => <span key={k}>↗ <a href={url} target="_blank" rel="noreferrer">{SOCIAL_LABEL[k] ?? k}</a></span>)}
                {!profile?.contactPhone && !profile?.contactEmail && !profile?.website && <span className="cust-empty" style={{ padding: 8 }}>No contact details published.</span>}
              </div>
            </section>
            {(branches?.length ?? 0) > 0 && (
              <section className="card chart-card">
                <p className="chart-title">{branches!.length === 1 ? 'Location' : 'Branches'}</p>
                <div className="cust-contact">
                  {branches!.map((b) => <span key={b.id}>📍 <b>{b.name}</b>{b.address ? ` · ${b.address}` : ''}{b.phone ? ` · ${b.phone}` : ''}</span>)}
                </div>
              </section>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
