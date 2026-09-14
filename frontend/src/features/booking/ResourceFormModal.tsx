import { useState } from 'react';
import Modal from '../../shared/components/Modal';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import { useCreateResourceMutation, useGetStaffUsersQuery, useUpdateResourceMutation } from '../../api/bookingApi';
import { RESOURCE_CATEGORIES, type Resource, type ResourceCategory } from './types';

// Known custom-attribute keys with dedicated inputs below; anything else
// typed into "Other details (JSON)" is preserved alongside them. Keeps the
// form usable for a non-technical owner while staying open-ended enough
// for docs/tourism-business-template.md's full schema (season, pickup,
// certifications, ...).
const KNOWN_ATTR_KEYS = ['rating', 'pricing', 'includes'];

function parseCustomAttributes(json?: string | null) {
  if (!json) return { rating: '', adultPrice: '', childPrice: '', includes: '', rest: '' };
  try {
    const obj = JSON.parse(json) as Record<string, unknown>;
    const pricing = (obj.pricing ?? {}) as { adult?: number; child?: number };
    const includes = Array.isArray(obj.includes) ? (obj.includes as string[]).join(', ') : '';
    const rest = Object.fromEntries(Object.entries(obj).filter(([k]) => !KNOWN_ATTR_KEYS.includes(k)));
    return {
      rating: obj.rating != null ? String(obj.rating) : '',
      adultPrice: pricing.adult != null ? String(pricing.adult) : '',
      childPrice: pricing.child != null ? String(pricing.child) : '',
      includes,
      rest: Object.keys(rest).length ? JSON.stringify(rest, null, 2) : '',
    };
  } catch {
    return { rating: '', adultPrice: '', childPrice: '', includes: '', rest: json };
  }
}

function buildCustomAttributes(
  rating: string,
  adultPrice: string,
  childPrice: string,
  includes: string,
  rest: string,
): string | undefined {
  let obj: Record<string, unknown> = {};
  if (rest.trim()) {
    try {
      obj = JSON.parse(rest);
    } catch {
      throw new Error('"Other details" must be valid JSON.');
    }
  }
  if (rating) obj.rating = Number(rating);
  if (adultPrice || childPrice) {
    obj.pricing = {
      currency: 'LKR',
      ...(adultPrice ? { adult: Number(adultPrice) } : {}),
      ...(childPrice ? { child: Number(childPrice) } : {}),
    };
  }
  if (includes.trim()) obj.includes = includes.split(',').map((s) => s.trim()).filter(Boolean);
  return Object.keys(obj).length ? JSON.stringify(obj) : undefined;
}

export default function ResourceFormModal({
  tenantId,
  resource,
  onClose,
}: {
  tenantId: string;
  resource?: Resource | null;
  onClose: () => void;
}) {
  const { show } = useToast();
  const [createResource, { isLoading: creating }] = useCreateResourceMutation();
  const [updateResource, { isLoading: updating }] = useUpdateResourceMutation();
  const { data: staff } = useGetStaffUsersQuery({ tenantId }, { skip: !tenantId });

  const [name, setName] = useState(resource?.name ?? '');
  const [code, setCode] = useState(resource?.code ?? '');
  const [category, setCategory] = useState<ResourceCategory>(resource?.category ?? 'Room');
  const [capacity, setCapacity] = useState(resource?.capacity?.toString() ?? '');
  const [hourlyRate, setHourlyRate] = useState(resource?.hourlyRate?.toString() ?? '');
  const [description, setDescription] = useState(resource?.description ?? '');
  const [specialty, setSpecialty] = useState(resource?.specialty ?? '');
  const [linkedUserId, setLinkedUserId] = useState(resource?.linkedUserId ?? '');
  const initialAttrs = parseCustomAttributes(resource?.customAttributes);
  const [rating, setRating] = useState(initialAttrs.rating);
  const [adultPrice, setAdultPrice] = useState(initialAttrs.adultPrice);
  const [childPrice, setChildPrice] = useState(initialAttrs.childPrice);
  const [includes, setIncludes] = useState(initialAttrs.includes);
  const [otherAttrs, setOtherAttrs] = useState(initialAttrs.rest);
  const [error, setError] = useState<string | null>(null);

  const isLoading = creating || updating;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    let customAttributes: string | undefined;
    try {
      customAttributes = buildCustomAttributes(rating, adultPrice, childPrice, includes, otherAttrs);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Invalid custom attributes.');
      return;
    }
    try {
      if (resource) {
        await updateResource({
          id: resource.id,
          body: {
            name,
            category,
            description: description || undefined,
            capacity: capacity ? Number(capacity) : undefined,
            hourlyRate: hourlyRate ? Number(hourlyRate) : undefined,
            specialty: specialty || undefined,
            linkedUserId: linkedUserId || undefined,
            customAttributes,
          },
        }).unwrap();
        show('Resource updated.', 'success');
      } else {
        await createResource({
          tenantId,
          name,
          code: code || undefined,
          category,
          description: description || undefined,
          capacity: capacity ? Number(capacity) : undefined,
          hourlyRate: hourlyRate ? Number(hourlyRate) : undefined,
          specialty: specialty || undefined,
          linkedUserId: linkedUserId || undefined,
          customAttributes,
        }).unwrap();
        show('Resource created.', 'success');
      }
      onClose();
    } catch (err) {
      setError(apiErrorMessage(err, 'Could not save resource.'));
    }
  };

  return (
    <Modal
      title={resource ? 'Edit resource' : 'New resource'}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary" onClick={onClose} type="button">Cancel</button>
          <button className="btn btn-primary" onClick={handleSubmit} disabled={isLoading}>
            {isLoading ? <span className="spinner" /> : resource ? 'Save changes' : 'Create resource'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit}>
        {error && <div className="banner banner-critical">{error}</div>}
        <div className="form-grid">
          <div className="field field-full">
            <label>Name</label>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          {!resource && (
            <div className="field">
              <label>Code</label>
              <input className="input" value={code} onChange={(e) => setCode(e.target.value)} placeholder="Optional, e.g. RM-101" />
            </div>
          )}
          <div className="field">
            <label>Category</label>
            <select className="input" value={category} onChange={(e) => setCategory(e.target.value as ResourceCategory)}>
              {RESOURCE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
          <div className="field">
            <label>Capacity</label>
            <input className="input" type="number" min={0} value={capacity} onChange={(e) => setCapacity(e.target.value)} />
          </div>
          <div className="field">
            <label>Hourly rate</label>
            <input className="input" type="number" min={0} step="0.01" value={hourlyRate} onChange={(e) => setHourlyRate(e.target.value)} />
          </div>
          <div className="field">
            <label>Specialty</label>
            <input
              className="input"
              value={specialty}
              onChange={(e) => setSpecialty(e.target.value)}
              placeholder="e.g. Cardiology, Whale and Dolphin Watching"
            />
          </div>
          {category === 'Staff' && (
            <div className="field">
              <label>Linked staff login</label>
              <select className="input" value={linkedUserId} onChange={(e) => setLinkedUserId(e.target.value)}>
                <option value="">None</option>
                {staff?.map((s) => (
                  <option key={s.id} value={s.id}>{s.fullName} ({s.role})</option>
                ))}
              </select>
            </div>
          )}
          <div className="field field-full">
            <label>Description</label>
            <textarea className="input" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>

          <div className="field field-full" style={{ borderTop: '1px solid var(--color-border)', paddingTop: 12, marginTop: 4 }}>
            <label style={{ fontWeight: 600 }}>Additional details</label>
            <p style={{ fontSize: 12, opacity: 0.7, margin: '2px 0 8px' }}>
              Optional - rating, per-person pricing, and what's included. Useful for tourism, restaurant, and other
              businesses where a single hourly rate doesn't describe the offer.
            </p>
          </div>
          <div className="field">
            <label>Rating (0-5)</label>
            <input className="input" type="number" min={0} max={5} step="0.1" value={rating} onChange={(e) => setRating(e.target.value)} />
          </div>
          <div className="field">
            <label>Adult price (LKR)</label>
            <input className="input" type="number" min={0} step="0.01" value={adultPrice} onChange={(e) => setAdultPrice(e.target.value)} />
          </div>
          <div className="field">
            <label>Child price (LKR)</label>
            <input className="input" type="number" min={0} step="0.01" value={childPrice} onChange={(e) => setChildPrice(e.target.value)} />
          </div>
          <div className="field field-full">
            <label>What's included</label>
            <input
              className="input"
              value={includes}
              onChange={(e) => setIncludes(e.target.value)}
              placeholder="Comma-separated, e.g. breakfast, life jacket, insurance, WiFi"
            />
          </div>
          <div className="field field-full">
            <label>Other details (JSON, optional)</label>
            <textarea
              className="input"
              rows={3}
              value={otherAttrs}
              onChange={(e) => setOtherAttrs(e.target.value)}
              placeholder='e.g. {"season": {"months": ["Nov","Dec","Jan"], "weatherDependent": true}}'
              style={{ fontFamily: 'monospace', fontSize: 12 }}
            />
          </div>
        </div>
      </form>
    </Modal>
  );
}
