import { useEffect, useState } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState } from '../../store/store';
import { updateCurrentUser } from '../../store/authSlice';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import { useUploadMediaMutation, useUpdateMyProfileMutation } from '../../api/bookingApi';

// Self-service profile (any authenticated role) - separate from
// BusinessProfilePage.tsx, which is the tenant's own public listing, not a
// user's personal account. Mirrors the same "upload, then attach the URL"
// split used there: a failed upload must never clear an already-saved photo.
export default function MyProfilePage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch();
  const { show } = useToast();

  const [uploadMedia] = useUploadMediaMutation();
  const [updateProfile, { isLoading: saving }] = useUpdateMyProfileMutation();

  const [fullName, setFullName] = useState(user?.fullName ?? '');
  const [profilePictureUrl, setProfilePictureUrl] = useState<string | null>(user?.profilePictureUrl ?? null);
  const [dirty, setDirty] = useState(false);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    setFullName(user?.fullName ?? '');
    setProfilePictureUrl(user?.profilePictureUrl ?? null);
    setDirty(false);
  }, [user?.fullName, user?.profilePictureUrl]);

  const handlePickFile = async (file: File) => {
    setUploading(true);
    try {
      const result = await uploadMedia({ file, purpose: 'avatar' }).unwrap();
      setProfilePictureUrl(result.url);
      setDirty(true);
      show('Photo uploaded — remember to save.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not upload photo.'), 'error');
    } finally {
      setUploading(false);
    }
  };

  const handleSave = async () => {
    try {
      const result = await updateProfile({
        fullName,
        profilePictureUrl: profilePictureUrl ?? undefined,
      }).unwrap();
      dispatch(updateCurrentUser({ fullName: result.fullName, profilePictureUrl: result.profilePictureUrl }));
      setDirty(false);
      show('Profile saved.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not save profile.'), 'error');
    }
  };

  const initials = (fullName || user?.email || '?')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join('');

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">My Profile</h1>
          <p className="page-subtitle">Your photo and personal details for this account.</p>
        </div>
        <button className="btn btn-primary" onClick={handleSave} disabled={!dirty || saving || uploading}>
          {saving ? <span className="spinner" /> : 'Save changes'}
        </button>
      </div>

      <div className="card card-pad" style={{ maxWidth: 480 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 20, marginBottom: 24 }}>
          <div
            style={{
              position: 'relative',
              width: 88,
              height: 88,
              borderRadius: '50%',
              overflow: 'hidden',
              flexShrink: 0,
              border: '2px dashed var(--color-border-strong)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              background: 'var(--color-surface-muted)',
              fontSize: 26,
              fontWeight: 700,
              color: 'var(--color-text-muted)',
            }}
          >
            {profilePictureUrl && (
              <img src={profilePictureUrl} alt="Your profile" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            )}
            {!profilePictureUrl && !uploading && initials}
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
                <span className="spinner" />
              </div>
            )}
          </div>
          <label className="btn btn-secondary btn-sm" style={{ cursor: 'pointer' }}>
            {uploading ? 'Uploading…' : profilePictureUrl ? 'Replace photo' : 'Upload photo'}
            <input
              type="file"
              accept="image/jpeg,image/png,image/webp"
              hidden
              disabled={uploading}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) handlePickFile(f);
                e.target.value = '';
              }}
            />
          </label>
        </div>

        <div className="field">
          <label>Full name</label>
          <input
            className="input"
            value={fullName}
            onChange={(e) => {
              setFullName(e.target.value);
              setDirty(true);
            }}
          />
        </div>
        <div className="field">
          <label>Email</label>
          <input className="input" value={user?.email ?? ''} disabled />
        </div>
        <div className="field">
          <label>Role</label>
          <input className="input" value={user?.role ?? ''} disabled />
        </div>
      </div>
    </div>
  );
}
