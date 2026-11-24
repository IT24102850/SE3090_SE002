import { describe, expect, it } from 'vitest';
import { buildBookingLink, collectAttribution } from '../embed/attribution';
import { captionWithLink, fromLocalInput, postProblem, toLocalInput } from './postRules';

describe('collectAttribution', () => {
  it('reads UTM tags and click ids from a direct link, and strips widget-only params from the landing URL', () => {
    const a = collectAttribution(
      'https://app.example/embed/book/t1?utm_source=instagram&utm_medium=paid_social&utm_campaign=120001&fbclid=IwAR1&accent=0d3b66#x',
      'https://l.instagram.com/',
      false,
    );
    expect(a).toMatchObject({ utmSource: 'instagram', utmMedium: 'paid_social', utmCampaign: '120001', fbclid: 'IwAR1', referrer: 'https://l.instagram.com/' });
    expect(a.landingUrl).toBe('https://app.example/embed/book/t1?utm_source=instagram&utm_medium=paid_social&utm_campaign=120001&fbclid=IwAR1');
  });

  it('in an iframe, uses the landing page and referrer embed.js forwarded, not the iframe’s own', () => {
    const a = collectAttribution(
      'https://app.example/embed/book/t1?utm_source=tiktok&ttclid=E1&fbp=fb.1.2.3&landing=https%3A%2F%2Fsite.example%2Ftours%3Futm_source%3Dtiktok&ref=https%3A%2F%2Fwww.tiktok.com%2F',
      'https://site.example/tours',
      true,
    );
    expect(a.landingUrl).toBe('https://site.example/tours?utm_source=tiktok');
    expect(a.referrer).toBe('https://www.tiktok.com/');
    expect(a.ttclid).toBe('E1');
    expect(a.fbp).toBe('fb.1.2.3');
  });

  it('picks up the inbox conversation id', () => {
    expect(collectAttribution('https://app.example/embed/book/t1?conv=abc', '', false).conversationId).toBe('abc');
  });

  it('survives a malformed URL', () => {
    expect(collectAttribution('not a url', '', false)).toEqual({});
  });
});

describe('buildBookingLink', () => {
  it('builds a tracked link with the conversation id', () => {
    const link = buildBookingLink({ origin: 'https://app.example', tenantId: 't 1', source: 'instagram', medium: 'dm', campaign: ' inbox ', conversationId: 'c1' });
    expect(link).toBe('https://app.example/embed/book/t%201?utm_source=instagram&utm_medium=dm&utm_campaign=inbox&conv=c1');
  });

  it('leaves out empty campaign and content', () => {
    expect(buildBookingLink({ origin: 'https://app.example', tenantId: 't', source: 'facebook', medium: 'social', campaign: '  ' }))
      .toBe('https://app.example/embed/book/t?utm_source=facebook&utm_medium=social');
  });
});

describe('postProblem', () => {
  it('requires media on Instagram and TikTok but not Facebook', () => {
    expect(postProblem('Instagram', 'Hi', 'None', null)).toMatch(/image or a video/);
    expect(postProblem('TikTok', 'Hi', 'None', null)).toMatch(/video or a photo/);
    expect(postProblem('Facebook', 'Hi', 'None', null)).toBeNull();
    expect(postProblem('Facebook', '  ', 'None', null)).toMatch(/text or media/);
  });

  it('refuses non-public media links', () => {
    expect(postProblem('Instagram', '', 'Image', 'http://cdn.example/x.jpg')).toMatch(/https/);
    expect(postProblem('Instagram', '', 'Image', 'https://localhost/x.jpg')).toMatch(/https/);
    expect(postProblem('Instagram', '', 'Image', 'https://cdn.example/x.jpg')).toBeNull();
  });

  it('enforces per-platform caption limits and the hashtag cap', () => {
    const long = 'x'.repeat(2201);
    expect(postProblem('Instagram', long, 'Image', 'https://cdn.example/x.jpg')).toMatch(/2,?200/);
    expect(postProblem('Facebook', long, 'None', null)).toBeNull();
    const tags = Array.from({ length: 31 }, (_, i) => `#t${i}`).join(' ');
    expect(postProblem('Instagram', tags, 'Image', 'https://cdn.example/x.jpg')).toMatch(/30 hashtags/);
  });
});

describe('caption helpers', () => {
  it('appends the link once', () => {
    expect(captionWithLink('Hello ', 'https://x.example')).toBe('Hello\n\nhttps://x.example');
    expect(captionWithLink('See https://x.example', 'https://x.example')).toBe('See https://x.example');
    expect(captionWithLink('Hello', null)).toBe('Hello');
  });

  it('round-trips datetime-local values', () => {
    const iso = new Date(2026, 11, 5, 9, 30).toISOString();
    expect(fromLocalInput(toLocalInput(iso))).toBe(iso);
    expect(fromLocalInput('')).toBeNull();
  });
});
