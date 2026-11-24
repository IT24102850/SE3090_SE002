import type { MediaType, Platform } from './socialApi';

/* Client-side mirror of backend SocialPostRules, so the composer can warn
 * before the user presses Publish. The server checks again regardless. */
export const CAPTION_LIMIT: Record<Platform, number> = {
  Facebook: 10000,
  Instagram: 2200,
  TikTok: 2200,
};

export function isPublicHttps(url: string | null | undefined): boolean {
  if (!url) return false;
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && u.hostname !== 'localhost' && u.hostname !== '127.0.0.1';
  } catch {
    return false;
  }
}

export function postProblem(platform: Platform, caption: string, mediaType: MediaType, mediaUrl: string | null): string | null {
  const hasMedia = mediaType === 'Image' || mediaType === 'Video';
  if (hasMedia && !isPublicHttps(mediaUrl)) return 'Media must be a public https:// link.';
  if (caption.length > CAPTION_LIMIT[platform]) return `Caption is over ${CAPTION_LIMIT[platform].toLocaleString()} characters.`;
  switch (platform) {
    case 'Facebook':
      return !hasMedia && !caption.trim() ? 'Add text or media.' : null;
    case 'Instagram': {
      if (!hasMedia) return 'Instagram needs an image or a video.';
      const tags = caption.split(/\s+/).filter((w) => w.startsWith('#') && w.length > 1).length;
      return tags > 30 ? 'Instagram allows at most 30 hashtags.' : null;
    }
    case 'TikTok':
      return !hasMedia ? 'TikTok needs a video or a photo.' : null;
    default:
      return null;
  }
}

/* What the caption will look like where links are not clickable. */
export function captionWithLink(caption: string, link: string | null): string {
  if (!link || caption.includes(link)) return caption;
  return `${caption.trimEnd()}\n\n${link}`;
}

/* datetime-local value <-> ISO, in the user's own time zone. */
export function toLocalInput(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function fromLocalInput(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
