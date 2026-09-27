import { useEffect, useState } from 'react';

/* The business's own profile picture - the logo uploaded under Settings ->
 * Business Profile - everywhere the business, rather than a person, is the
 * subject: the dashboard heroes of every business type.
 *
 * Mirrors UserAvatar: the logo when there is one, the business's initials
 * on the brand gradient otherwise, and initials again if the image fails
 * to load rather than a broken-image icon. Logos are usually square marks
 * or wordmarks on a white background, so the tile is a white-backed
 * rounded square with the image contained, not a face-style circle crop. */
export default function BusinessAvatar({
  name,
  src,
  size = 56,
  className,
}: {
  name?: string | null;
  src?: string | null;
  size?: number;
  className?: string;
}) {
  const [broken, setBroken] = useState(false);
  useEffect(() => { setBroken(false); }, [src]);

  const initials = (name || '?')
    .trim()
    .split(/\s+/)
    .filter((p) => p && !/^[(&-]/.test(p))
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('') || '?';

  const showLogo = !!src && !broken;

  return (
    <span
      className={`business-avatar${className ? ` ${className}` : ''}`}
      role="img"
      aria-label={name ? `${name} logo` : 'Business logo'}
      style={{ width: size, height: size, fontSize: Math.max(11, Math.round(size * 0.36)) }}
    >
      {showLogo
        ? <img src={src!} alt="" onError={() => setBroken(true)} />
        : initials}
    </span>
  );
}
