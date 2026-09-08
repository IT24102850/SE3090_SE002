import { useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import {
  useGetTenantProfileQuery,
  useUpdateTenantProfileMutation,
  useSetTenantLogoMutation,
  useSetTenantCoverImageMutation,
  useAddGalleryImageMutation,
  useRemoveGalleryImageMutation,
  useReorderGalleryImagesMutation,
  useUploadMediaMutation,
} from '../../api/bookingApi';
import { BusinessHourEntry, DAYS_OF_WEEK } from '../booking/types';

// Shared, business-type-agnostic Business Profile editor (Admin/Manager) -
// the "TripAdvisor listing" shell. Deliberately a SEPARATE page from
// BusinessSettingsPage.tsx (operational policy: name/cutoffs/sub-type) -
// this one is the public-facing listing content only. Nothing here is
// Tourism/sub-type-specific.

const SUGGESTED_AMENITIES = ['Free WiFi', 'Parking', 'Beginner Friendly', 'Equipment Rental', 'Air Conditioning', 'Wheelchair Accessible'];

function defaultHours(): BusinessHourEntry[] {
  return DAYS_OF_WEEK.map((d) => ({ dayOfWeek: d, openTime: '09:00', closeTime: '17:00', isClosed: d === 'Sunday' }));
}

const chipStyle: React.CSSProperties = {
  display: 'inline-flex', alignItems: 'center', gap: 6, padding: '4px 10px',
  background: 'var(--color-primary-soft)', color: 'var(--color-primary)', borderRadius: 20, fontSize: 12.5, fontWeight: 600,
};
const chipCloseStyle: React.CSSProperties = { background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', fontSize: 14, lineHeight: 1, padding: 0 };
const arrowBtnStyle: React.CSSProperties = { background: 'rgba(0,0,0,0.6)', color: '#fff', border: 'none', borderRadius: 4, width: 22, height: 20, cursor: 'pointer', fontSize: 11 };

export default function BusinessProfilePage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data: profile, isLoading } = useGetTenantProfileQuery({ tenantId }, { skip: !tenantId });
  const [updateProfile, { isLoading: savingProfile }] = useUpdateTenantProfileMutation();
  const [setLogo] = useSetTenantLogoMutation();
  const [setCoverImage] = useSetTenantCoverImageMutation();
  const [uploadMedia] = useUploadMediaMutation();

  const [logoUrl, setLogoUrl] = useState<string | null>(null);
  const [coverImageUrl, setCoverImageUrl] = useState<string | null>(null);
  const [shortTagline, setShortTagline] = useState('');
  const [description, setDescription] = useState('');
  const [amenities, setAmenities] = useState<string[]>([]);
  const [contactPhone, setContactPhone] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [website, setWebsite] = useState('');
  const [socialLinks, setSocialLinks] = useState<Record<string, string>>({});
  const [businessHours, setBusinessHours] = useState<BusinessHourEntry[]>(defaultHours());

  // Only the sections that actually changed get written on Save - gallery
  // add/remove/reorder apply immediately instead (they're their own REST
  // actions, not part of the profile PUT body - see the plan).
  const [dirty, setDirty] = useState({ profile: false, logo: false, cover: false });
  const [uploadingLogo, setUploadingLogo] = useState(false);
  const [uploadingCover, setUploadingCover] = useState(false);

  useEffect(() => {
    if (!profile) return;
    setLogoUrl(profile.logoUrl ?? null);
    setCoverImageUrl(profile.coverImageUrl ?? null);
    setShortTagline(profile.shortTagline ?? '');
    setDescription(profile.description ?? '');
    setAmenities(profile.amenities ?? []);
    setContactPhone(profile.contactPhone ?? '');
    setContactEmail(profile.contactEmail ?? '');
    setWebsite(profile.website ?? '');
    setSocialLinks(profile.socialLinks ?? {});
    setBusinessHours(profile.businessHours?.length ? profile.businessHours : defaultHours());
    setDirty({ profile: false, logo: false, cover: false });
  }, [profile]);

  const hoursError = businessHours.find((h) => !h.isClosed && h.openTime && h.closeTime && h.openTime >= h.closeTime);

  const markProfileDirty = () => setDirty((d) => ({ ...d, profile: true }));

  const handleUpload = async (
    file: File,
    purpose: 'logo' | 'cover',
    setUploading: (v: boolean) => void,
    setUrl: (v: string) => void,
    markDirty: () => void,
  ) => {
    setUploading(true);
    try {
      const result = await uploadMedia({ file, purpose }).unwrap();
      setUrl(result.url);
      markDirty();
      show('Image uploaded — remember to save.', 'success');
    } catch (err) {
      // Deliberately does NOT touch logoUrl/coverImageUrl state here - a
      // failed upload must never clear an already-saved image.
      show(apiErrorMessage(err, 'Could not upload image.'), 'error');
    } finally {
      setUploading(false);
    }
  };

  const addAmenity = (value: string) => {
    const trimmed = value.trim();
    if (!trimmed) return;
    if (amenities.some((a) => a.toLowerCase() === trimmed.toLowerCase())) return; // no duplicates
    setAmenities((prev) => [...prev, trimmed]);
    markProfileDirty();
  };
  const removeAmenity = (value: string) => {
    setAmenities((prev) => prev.filter((a) => a !== value));
    markProfileDirty();
  };

  const updateHour = (day: string, patch: Partial<BusinessHourEntry>) => {
    setBusinessHours((prev) => prev.map((h) => (h.dayOfWeek === day ? { ...h, ...patch } : h)));
    markProfileDirty();
  };
  const copyMondayToWeekdays = () => {
    const monday = businessHours.find((h) => h.dayOfWeek === 'Monday');
    if (!monday) return;
    setBusinessHours((prev) =>
      prev.map((h) =>
        ['Tuesday', 'Wednesday', 'Thursday', 'Friday'].includes(h.dayOfWeek)
          ? { ...h, openTime: monday.openTime, closeTime: monday.closeTime, isClosed: monday.isClosed }
          : h,
      ),
    );
    markProfileDirty();
  };

  const handleSave = async () => {
    if (hoursError) {
      show(`${hoursError.dayOfWeek}: open time must be before close time.`, 'error');
      return;
    }
    try {
      if (dirty.logo && logoUrl) await setLogo({ tenantId, imageUrl: logoUrl }).unwrap();
      if (dirty.cover && coverImageUrl) await setCoverImage({ tenantId, imageUrl: coverImageUrl }).unwrap();
      if (dirty.profile) {
        await updateProfile({
          tenantId,
          body: { description, shortTagline, amenities, contactPhone, contactEmail, website, socialLinks, businessHours },
        }).unwrap();
      }
      setDirty({ profile: false, logo: false, cover: false });
      show('Business profile saved.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not save profile.'), 'error');
    }
  };

  const anyDirty = dirty.profile || dirty.logo || dirty.cover;
  const anyUploading = uploadingLogo || uploadingCover;

  if (isLoading) {
    return <div className="card"><div className="loading-row"><span className="spinner spinner-dark" /> Loading…</div></div>;
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Business Profile</h1>
          <p className="page-subtitle">How customers see your business — logo, photos, description, and hours.</p>
        </div>
        <button className="btn btn-primary" onClick={handleSave} disabled={!anyDirty || savingProfile || anyUploading}>
          {savingProfile ? <span className="spinner" /> : 'Save changes'}
        </button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 340px', gap: 24, alignItems: 'start' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <div className="card card-pad">
            <h3 style={{ marginTop: 0 }}>Logo & Cover image</h3>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
              <UploadZone
                label="Logo"
                imageUrl={logoUrl}
                uploading={uploadingLogo}
                round
                onFile={(f) => handleUpload(f, 'logo', setUploadingLogo, setLogoUrl, () => setDirty((d) => ({ ...d, logo: true })))}
              />
              <UploadZone
                label="Cover image"
                imageUrl={coverImageUrl}
                uploading={uploadingCover}
                onFile={(f) => handleUpload(f, 'cover', setUploadingCover, setCoverImageUrl, () => setDirty((d) => ({ ...d, cover: true })))}
              />
            </div>
          </div>

          <GallerySection tenantId={tenantId} galleryImageUrls={profile?.galleryImageUrls ?? []} />

          <div className="card card-pad">
            <h3 style={{ marginTop: 0 }}>About</h3>
            <div className="field">
              <label>Tagline ({shortTagline.length}/100)</label>
              <input
                className="input"
                maxLength={100}
                value={shortTagline}
                onChange={(e) => {
                  setShortTagline(e.target.value);
                  markProfileDirty();
                }}
                placeholder="e.g. PADI 5-Star Dive Center"
              />
            </div>
            <div className="field">
              <label>Description ({description.length}/5000)</label>
              <textarea
                className="input"
                rows={6}
                maxLength={5000}
                value={description}
                onChange={(e) => {
                  setDescription(e.target.value);
                  markProfileDirty();
                }}
              />
            </div>
          </div>

          <div className="card card-pad">
            <h3 style={{ marginTop: 0 }}>Amenities</h3>
            <AmenityInput amenities={amenities} onAdd={addAmenity} onRemove={removeAmenity} />
          </div>

          <div className="card card-pad">
            <h3 style={{ marginTop: 0 }}>Contact & Hours</h3>
            <div className="form-grid">
              <div className="field">
                <label>Phone</label>
                <input
                  className="input"
                  value={contactPhone}
                  onChange={(e) => {
                    setContactPhone(e.target.value);
                    markProfileDirty();
                  }}
                />
              </div>
              <div className="field">
                <label>Email</label>
                <input
                  className="input"
                  value={contactEmail}
                  onChange={(e) => {
                    setContactEmail(e.target.value);
                    markProfileDirty();
                  }}
                />
              </div>
              <div className="field">
                <label>Website</label>
                <input
                  className="input"
                  value={website}
                  onChange={(e) => {
                    setWebsite(e.target.value);
                    markProfileDirty();
                  }}
                />
              </div>
              <div className="field">
                <label>Instagram</label>
                <input
                  className="input"
                  value={socialLinks.instagram ?? ''}
                  onChange={(e) => {
                    setSocialLinks((s) => ({ ...s, instagram: e.target.value }));
                    markProfileDirty();
                  }}
                />
              </div>
              <div className="field">
                <label>Facebook</label>
                <input
                  className="input"
                  value={socialLinks.facebook ?? ''}
                  onChange={(e) => {
                    setSocialLinks((s) => ({ ...s, facebook: e.target.value }));
                    markProfileDirty();
                  }}
                />
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', margin: '16px 0 10px' }}>
              <h4 style={{ margin: 0 }}>Business hours</h4>
              <button type="button" className="btn btn-secondary btn-sm" onClick={copyMondayToWeekdays}>
                Copy Monday to all weekdays
              </button>
            </div>
            {businessHours.map((h) => {
              const rowError = !h.isClosed && h.openTime && h.closeTime && h.openTime >= h.closeTime;
              return (
                <div key={h.dayOfWeek} style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6, fontSize: 13 }}>
                  <span style={{ width: 90 }}>{h.dayOfWeek}</span>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <input type="checkbox" checked={h.isClosed} onChange={(e) => updateHour(h.dayOfWeek, { isClosed: e.target.checked })} />
                    Closed
                  </label>
                  <input
                    className="input"
                    type="time"
                    style={{ padding: '4px 8px' }}
                    value={h.openTime ?? '09:00'}
                    disabled={h.isClosed}
                    onChange={(e) => updateHour(h.dayOfWeek, { openTime: e.target.value })}
                  />
                  <span>–</span>
                  <input
                    className="input"
                    type="time"
                    style={{ padding: '4px 8px' }}
                    value={h.closeTime ?? '17:00'}
                    disabled={h.isClosed}
                    onChange={(e) => updateHour(h.dayOfWeek, { closeTime: e.target.value })}
                  />
                  {rowError && <span style={{ color: 'var(--color-critical)', fontSize: 12 }}>Open time must be before close time</span>}
                </div>
              );
            })}
          </div>
        </div>

        <PreviewPanel
          name={profile?.name ?? ''}
          logoUrl={logoUrl}
          coverImageUrl={coverImageUrl}
          shortTagline={shortTagline}
          description={description}
          amenities={amenities}
          galleryImageUrls={profile?.galleryImageUrls ?? []}
        />
      </div>
    </div>
  );
}

function UploadZone({
  label,
  imageUrl,
  uploading,
  round,
  onFile,
}: {
  label: string;
  imageUrl: string | null;
  uploading: boolean;
  round?: boolean;
  onFile: (f: File) => void;
}) {
  return (
    <div>
      <label style={{ fontSize: 13, fontWeight: 600, display: 'block', marginBottom: 6 }}>{label}</label>
      <div
        style={{
          position: 'relative',
          height: 140,
          borderRadius: round ? '50%' : 12,
          width: round ? 140 : '100%',
          border: '2px dashed var(--color-border-strong)',
          overflow: 'hidden',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'var(--color-surface-muted)',
        }}
      >
        {imageUrl && <img src={imageUrl} alt={label} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />}
        {uploading && (
          <div
            style={{
              position: 'absolute',
              inset: 0,
              background: 'rgba(0,0,0,0.5)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <span className="spinner" data-testid="upload-spinner" />
          </div>
        )}
        {!imageUrl && !uploading && <span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>No image</span>}
      </div>
      <label className="btn btn-secondary btn-sm" style={{ marginTop: 8, cursor: 'pointer', display: 'inline-block' }}>
        {uploading ? 'Uploading…' : imageUrl ? 'Replace' : 'Upload'}
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          hidden
          disabled={uploading}
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) onFile(f);
            e.target.value = '';
          }}
        />
      </label>
    </div>
  );
}

function GallerySection({ tenantId, galleryImageUrls }: { tenantId: string; galleryImageUrls: string[] }) {
  const { show } = useToast();
  const [uploadMedia] = useUploadMediaMutation();
  const [addGalleryImage] = useAddGalleryImageMutation();
  const [removeGalleryImage] = useRemoveGalleryImageMutation();
  const [reorderGalleryImages] = useReorderGalleryImagesMutation();
  const [uploading, setUploading] = useState(false);

  const handleAddPhotos = async (files: FileList) => {
    setUploading(true);
    try {
      for (const file of Array.from(files)) {
        const result = await uploadMedia({ file, purpose: 'gallery' }).unwrap();
        await addGalleryImage({ tenantId, imageUrl: result.url }).unwrap();
      }
      show('Photos added.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not add photo.'), 'error');
    } finally {
      setUploading(false);
    }
  };

  const handleRemove = async (index: number) => {
    try {
      await removeGalleryImage({ tenantId, index }).unwrap();
    } catch (err) {
      show(apiErrorMessage(err, 'Could not remove photo.'), 'error');
    }
  };

  // Up/down arrows chosen over drag-and-drop: no drag library exists in
  // this project's dependencies today, and arrows are fully deterministic
  // and easy to test without adding one.
  const handleMove = async (index: number, direction: -1 | 1) => {
    const newIndex = index + direction;
    if (newIndex < 0 || newIndex >= galleryImageUrls.length) return;
    const reordered = [...galleryImageUrls];
    [reordered[index], reordered[newIndex]] = [reordered[newIndex], reordered[index]];
    try {
      await reorderGalleryImages({ tenantId, orderedUrls: reordered }).unwrap();
    } catch (err) {
      show(apiErrorMessage(err, 'Could not reorder photos.'), 'error');
    }
  };

  return (
    <div className="card card-pad">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <h3 style={{ margin: 0 }}>Gallery</h3>
        <label className="btn btn-secondary btn-sm" style={{ cursor: 'pointer' }}>
          {uploading ? <span className="spinner" /> : 'Add photos'}
          <input
            type="file"
            accept="image/jpeg,image/png,image/webp"
            multiple
            hidden
            disabled={uploading}
            onChange={(e) => e.target.files && handleAddPhotos(e.target.files)}
          />
        </label>
      </div>
      {galleryImageUrls.length === 0 ? (
        <p style={{ color: 'var(--color-text-muted)', fontSize: 13 }}>No photos yet.</p>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))', gap: 10 }}>
          {galleryImageUrls.map((url, i) => (
            <div key={url + i} style={{ position: 'relative', borderRadius: 10, overflow: 'hidden', aspectRatio: '1' }}>
              <img src={url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              <button
                type="button"
                onClick={() => handleRemove(i)}
                aria-label="Remove photo"
                style={{
                  position: 'absolute',
                  top: 4,
                  right: 4,
                  background: 'rgba(0,0,0,0.6)',
                  color: '#fff',
                  border: 'none',
                  borderRadius: '50%',
                  width: 22,
                  height: 22,
                  cursor: 'pointer',
                }}
              >
                ×
              </button>
              <div style={{ position: 'absolute', bottom: 4, left: 4, display: 'flex', gap: 4 }}>
                <button type="button" aria-label="Move up" disabled={i === 0} onClick={() => handleMove(i, -1)} style={arrowBtnStyle}>
                  ↑
                </button>
                <button
                  type="button"
                  aria-label="Move down"
                  disabled={i === galleryImageUrls.length - 1}
                  onClick={() => handleMove(i, 1)}
                  style={arrowBtnStyle}
                >
                  ↓
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function AmenityInput({
  amenities,
  onAdd,
  onRemove,
}: {
  amenities: string[];
  onAdd: (v: string) => void;
  onRemove: (v: string) => void;
}) {
  const [value, setValue] = useState('');
  return (
    <div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginBottom: 10 }}>
        {amenities.map((a) => (
          <span key={a} style={chipStyle}>
            {a}
            <button type="button" onClick={() => onRemove(a)} style={chipCloseStyle} aria-label={`Remove ${a}`}>
              ×
            </button>
          </span>
        ))}
      </div>
      <input
        className="input"
        value={value}
        placeholder="Type an amenity and press Enter…"
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            onAdd(value);
            setValue('');
          }
        }}
      />
      <div style={{ marginTop: 8, display: 'flex', flexWrap: 'wrap', gap: 6 }}>
        {SUGGESTED_AMENITIES.filter((s) => !amenities.includes(s)).map((s) => (
          <button key={s} type="button" className="btn btn-ghost btn-sm" onClick={() => onAdd(s)}>
            + {s}
          </button>
        ))}
      </div>
    </div>
  );
}

function PreviewPanel({
  name,
  logoUrl,
  coverImageUrl,
  shortTagline,
  description,
  amenities,
  galleryImageUrls,
}: {
  name: string;
  logoUrl: string | null;
  coverImageUrl: string | null;
  shortTagline: string;
  description: string;
  amenities: string[];
  galleryImageUrls: string[];
}) {
  return (
    <div className="card" style={{ position: 'sticky', top: 20, overflow: 'hidden' }}>
      <div
        style={{
          height: 120,
          background: coverImageUrl ? `url(${coverImageUrl}) center/cover` : 'linear-gradient(135deg, #8B5CF6, #E040FB)',
          position: 'relative',
        }}
      >
        <div
          style={{
            position: 'absolute',
            bottom: -24,
            left: 16,
            width: 56,
            height: 56,
            borderRadius: '50%',
            border: '3px solid var(--color-surface)',
            background: logoUrl ? `url(${logoUrl}) center/cover` : 'var(--color-surface-muted)',
            boxShadow: '0 2px 6px rgba(0,0,0,0.2)',
          }}
        />
      </div>
      <div style={{ padding: '32px 16px 16px' }}>
        <div style={{ fontWeight: 700, fontSize: 15 }}>{name || 'Your business'}</div>
        {shortTagline && <div style={{ fontSize: 12.5, color: 'var(--color-text-secondary)', marginTop: 2 }}>{shortTagline}</div>}

        {galleryImageUrls.length > 0 && (
          <div style={{ display: 'flex', gap: 6, overflowX: 'auto', marginTop: 14 }}>
            {galleryImageUrls.slice(0, 5).map((url, i) => (
              <img key={i} src={url} alt="" style={{ width: 56, height: 56, borderRadius: 8, objectFit: 'cover', flexShrink: 0 }} />
            ))}
          </div>
        )}

        {description && (
          <p style={{ fontSize: 12.5, marginTop: 14, lineHeight: 1.5 }}>
            {description.slice(0, 200)}
            {description.length > 200 ? '…' : ''}
          </p>
        )}

        {amenities.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 10 }}>
            {amenities.map((a) => (
              <span key={a} style={{ ...chipStyle, fontSize: 11, padding: '3px 8px' }}>
                {a}
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
