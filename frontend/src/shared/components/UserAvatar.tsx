import { useEffect, useState } from 'react';

/* The signed-in person's avatar, everywhere one is shown: their uploaded
 * photo when they have one, otherwise their initials on the brand gradient.
 *
 * One component rather than two ad-hoc renderings (the sidebar had the photo,
 * the top bar had only a letter), so a person who uploads a photo on their
 * profile sees it in every corner of the app at once. A photo that fails to
 * load (deleted from the CDN, a dead link) falls back to the initials rather
 * than a broken-image icon. */
export default function UserAvatar({
  name,
  email,
  src,
  size = 28,
  className,
}: {
  name?: string | null;
  email?: string | null;
  src?: string | null;
  size?: number;
  className?: string;
}) {
  const [broken, setBroken] = useState(false);
  useEffect(() => { setBroken(false); }, [src]);

  const initials = (name || email || '?')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('') || '?';

  const showPhoto = !!src && !broken;

  return (
    <span
      className={className}
      aria-hidden="true"
      style={{
        width: size, height: size, borderRadius: '50%', overflow: 'hidden', flexShrink: 0,
        display: 'inline-grid', placeItems: 'center',
        fontSize: Math.max(10, Math.round(size * 0.42)), fontWeight: 800, lineHeight: 1,
      }}
    >
      {showPhoto
        ? <img src={src!} alt="" onError={() => setBroken(true)} style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
        : initials}
    </span>
  );
}
