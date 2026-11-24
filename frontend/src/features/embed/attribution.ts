/* Where a booking-page visitor came from, as the booking API expects it
 * (backend Services/Marketing/AttributionResolver.cs).
 *
 * Two ways in:
 *  - a direct link (Instagram bio, a Facebook post, an ad, a DM from the
 *    inbox): the tags are on this page's own URL and document.referrer is
 *    the social site;
 *  - the widget iframe on a business's own site: embed.js copies the host
 *    page's tags, its referrer and its pixel cookies onto the iframe URL
 *    (landing=, ref=, fbp=, fbc=, ttp=), because the iframe cannot read
 *    the host page's URL or cookies itself.
 */

export interface AttributionInput {
  utmSource?: string;
  utmMedium?: string;
  utmCampaign?: string;
  utmContent?: string;
  utmTerm?: string;
  fbclid?: string;
  fbc?: string;
  fbp?: string;
  ttclid?: string;
  ttp?: string;
  landingUrl?: string;
  referrer?: string;
  conversationId?: string;
}

const KEYS: Array<[keyof AttributionInput, string]> = [
  ['utmSource', 'utm_source'],
  ['utmMedium', 'utm_medium'],
  ['utmCampaign', 'utm_campaign'],
  ['utmContent', 'utm_content'],
  ['utmTerm', 'utm_term'],
  ['fbclid', 'fbclid'],
  ['ttclid', 'ttclid'],
  ['fbp', 'fbp'],
  ['fbc', 'fbc'],
  ['ttp', 'ttp'],
  ['conversationId', 'conv'],
];

/* Parameters that only steer the widget's look; stripped from the landing
 * URL we report so ad platforms see the page the visitor actually saw. */
const WIDGET_PARAMS = ['accent', 'theme', 'whatsapp', 'landing', 'ref', 'fbp', 'fbc', 'ttp'];

const clip = (v: string | null | undefined, max: number) => {
  const t = v?.trim();
  return t ? t.slice(0, max) : undefined;
};

export function collectAttribution(href: string, documentReferrer: string, inIframe: boolean): AttributionInput {
  let url: URL;
  try {
    url = new URL(href);
  } catch {
    return {};
  }
  const p = url.searchParams;
  const out: AttributionInput = {};
  for (const [field, key] of KEYS) {
    const value = clip(p.get(key), field === 'fbc' ? 600 : 500);
    if (value) out[field] = value;
  }

  const landing = clip(p.get('landing'), 2048);
  if (landing) {
    out.landingUrl = landing;
  } else if (!inIframe) {
    const clean = new URL(url.toString());
    WIDGET_PARAMS.forEach((k) => clean.searchParams.delete(k));
    clean.hash = '';
    out.landingUrl = clean.toString().slice(0, 2048);
  }

  // In an iframe document.referrer is just the host page; the host page's
  // own referrer is what embed.js forwarded as ref=.
  const referrer = inIframe ? clip(p.get('ref'), 2048) : clip(documentReferrer, 2048);
  if (referrer) out.referrer = referrer;
  return out;
}

export type SocialChannel = 'instagram' | 'facebook' | 'tiktok';

export interface BookingLinkOptions {
  origin: string;
  tenantId: string;
  source: SocialChannel | string;
  medium: string;
  campaign?: string;
  content?: string;
  conversationId?: string;
}

/* The tracked booking link a business shares on social media. */
export function buildBookingLink(o: BookingLinkOptions): string {
  const url = new URL(`/embed/book/${encodeURIComponent(o.tenantId)}`, o.origin);
  url.searchParams.set('utm_source', o.source);
  url.searchParams.set('utm_medium', o.medium);
  if (o.campaign?.trim()) url.searchParams.set('utm_campaign', o.campaign.trim());
  if (o.content?.trim()) url.searchParams.set('utm_content', o.content.trim());
  if (o.conversationId) url.searchParams.set('conv', o.conversationId);
  return url.toString();
}

/* The URL-parameter template pasted into the ad platform's "URL
 * parameters" box, so every ad click carries its own campaign id and the
 * campaign report can join spend to bookings exactly. */
export const AD_URL_TEMPLATES = {
  meta: 'utm_source={{site_source_name}}&utm_medium=paid_social&utm_campaign={{campaign.id}}&utm_content={{ad.id}}',
  tiktok: 'utm_source=tiktok&utm_medium=paid_social&utm_campaign=__CAMPAIGN_ID__&utm_content=__CID__',
} as const;
