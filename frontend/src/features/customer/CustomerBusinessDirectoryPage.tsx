import { useMemo, useState } from 'react';
import { useDispatch } from 'react-redux';
import { useNavigate } from 'react-router-dom';
import {
  bookingApi,
  useGetPublicCustomerBusinessesQuery,
  useJoinCustomerBusinessMutation,
  type PublicCustomerBusiness,
} from '../../api/bookingApi';
import { switchBusinessSession } from '../../store/authSlice';
import BusinessAvatar from '../../shared/components/BusinessAvatar';
import { businessDescriptor, businessHeroImage } from '../../shared/businessImagery';
import './customer.css';

const businessPreview: Record<string, string> = {
  Clinic: 'Find care, explore available services, and choose an appointment that suits you.',
  Restaurant: 'Explore dining options and find the right experience for your visit.',
  Gym: 'Discover facilities and sessions, then plan a visit at your convenience.',
  School: 'Explore learning services and find the right program for your needs.',
  RealEstate: 'Explore property services and connect with the team about your next move.',
  Tourism: 'Discover experiences and find a tour or activity for your next trip.',
};

export default function CustomerBusinessDirectoryPage() {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const { data: businesses = [], isLoading, isError, refetch } = useGetPublicCustomerBusinessesQuery();
  const [joinBusiness, { isLoading: isJoining }] = useJoinCustomerBusinessMutation();
  const [query, setQuery] = useState('');
  const [selectedType, setSelectedType] = useState('All');
  const [selected, setSelected] = useState<PublicCustomerBusiness | null>(null);
  const [error, setError] = useState('');

  const types = useMemo(() => ['All', ...new Set(businesses.map((business) => business.businessType))], [businesses]);
  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase();
    return businesses.filter((business) => {
      const matchesType = selectedType === 'All' || business.businessType === selectedType;
      const matchesQuery = !term || `${business.name} ${business.businessType} ${business.subType ?? ''}`.toLowerCase().includes(term);
      return matchesType && matchesQuery;
    });
  }, [businesses, query, selectedType]);

  async function bookBusiness(business: PublicCustomerBusiness) {
    setError('');
    try {
      const session = await joinBusiness(business.id).unwrap();
      dispatch(switchBusinessSession(session));
      dispatch(bookingApi.util.resetApiState());
      setSelected(null);
      navigate('/book');
    } catch {
      setError('Could not connect to this business. Please try again.');
    }
  }

  return (
    <div className="cust-page cust-business-directory">
      <section className="cust-directory-hero">
        <div>
          <span className="cust-section-kicker">CUSTOMER SPACE</span>
          <h1>Find a business</h1>
          <p>Explore available businesses, services, and experiences. Choose one to start the Flutter-style booking flow.</p>
        </div>
        <span className="cust-directory-count">{filtered.length} {filtered.length === 1 ? 'business' : 'businesses'}</span>
      </section>

      <section className="cust-directory-controls" aria-label="Business search and filters">
        <label className="cust-directory-search">
          <span aria-hidden="true">⌕</span>
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search by business or type…" />
          {query && <button type="button" onClick={() => setQuery('')} aria-label="Clear search">×</button>}
        </label>
        <label className="cust-directory-filter">
          <span aria-hidden="true">☷</span>
          <select value={selectedType} onChange={(event) => setSelectedType(event.target.value)} aria-label="Filter by business type">
            {types.map((type) => <option key={type} value={type}>{type}</option>)}
          </select>
        </label>
      </section>

      {error && <div className="cust-error" role="alert">{error}</div>}
      {isLoading && <div className="loading-row"><span className="spinner spinner-dark" /></div>}
      {isError && (
        <div className="cust-empty card">
          Could not load businesses. <button className="btn btn-secondary btn-sm" type="button" onClick={() => void refetch()}>Try again</button>
        </div>
      )}
      {!isLoading && !isError && businesses.length === 0 && (
        <div className="cust-empty card">No businesses are available for booking right now. Check back soon.</div>
      )}
      {!isLoading && !isError && businesses.length > 0 && filtered.length === 0 && (
        <div className="cust-empty card">No businesses match “{query || selectedType}”.</div>
      )}

      <div className="cust-business-directory-grid">
        {filtered.map((business) => {
          const image = businessHeroImage({ businessType: business.businessType, subType: business.subType, coverImageUrl: business.coverImageUrl });
          return (
            <button key={business.id} type="button" className="cust-business-tile" onClick={() => setSelected(business)}>
              <span className="cust-business-tile-media">
                <img src={image} alt="" loading="lazy" />
              </span>
              <span className="cust-business-tile-content">
                <BusinessAvatar name={business.name} src={business.logoUrl} size={44} />
                <span>
                  <strong>{business.name}</strong>
                  <small>{businessDescriptor({ businessType: business.businessType, subType: business.subType })}</small>
                </span>
              </span>
            </button>
          );
        })}
      </div>

      {selected && (
        <div className="cust-directory-modal-backdrop" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && setSelected(null)}>
          <section className="cust-directory-modal" role="dialog" aria-modal="true" aria-labelledby="business-preview-title">
            <button className="cust-modal-close" type="button" onClick={() => setSelected(null)} aria-label="Close business preview">×</button>
            <BusinessAvatar name={selected.name} src={selected.logoUrl} size={58} />
            <span className="cust-section-kicker">{businessDescriptor({ businessType: selected.businessType, subType: selected.subType })}</span>
            <h2 id="business-preview-title">{selected.name}</h2>
            <p>{businessPreview[selected.businessType] ?? 'Explore what this business offers, choose a service, and book when you are ready.'}</p>
            <div className="cust-preview-steps">
              <span><b>1</b> Explore services and options</span>
              <span><b>2</b> Choose what works for you</span>
              <span><b>3</b> Book when you are ready</span>
            </div>
            <button className="btn btn-primary" type="button" disabled={isJoining} onClick={() => void bookBusiness(selected)}>
              {isJoining ? 'Connecting…' : 'Book this business'}
            </button>
          </section>
        </div>
      )}
    </div>
  );
}
