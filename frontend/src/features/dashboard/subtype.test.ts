import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { TOURISM_SUB_TYPES } from '../booking/types';
import {
  WHALE_WATCHING_SUBTYPE,
  getTenantSubtype,
  isWhaleWatching,
  resetSubtypeCache,
} from './subtype';

const TENANT_ID = '11111111-1111-1111-1111-111111111111';

function stubTenant(body: unknown, status = 200) {
  return vi.fn(async () =>
    new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } }),
  );
}

beforeEach(() => {
  resetSubtypeCache();
  localStorage.setItem('token', 'test-token');
  localStorage.setItem('user', JSON.stringify({ tenantId: TENANT_ID }));
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  localStorage.clear();
  resetSubtypeCache();
});

describe('WHALE_WATCHING_SUBTYPE', () => {
  it('is the exact string from TOURISM_SUB_TYPES', () => {
    expect(WHALE_WATCHING_SUBTYPE).toBe('Whale / dolphin watching');
    expect(TOURISM_SUB_TYPES).toContain(WHALE_WATCHING_SUBTYPE);
  });

  it('has the spaces around the slash', () => {
    // The single most likely typo, and it fails silently.
    expect(WHALE_WATCHING_SUBTYPE).not.toBe('Whale/dolphin watching');
  });
});

describe('getTenantSubtype', () => {
  it('returns the tenant sub-type', async () => {
    vi.stubGlobal('fetch', stubTenant({ subType: 'Whale / dolphin watching' }));
    await expect(getTenantSubtype()).resolves.toBe(WHALE_WATCHING_SUBTYPE);
  });

  it('reads /tenant, not the profile endpoint', async () => {
    // The business-profile projection does not carry SubType at all, so
    // resolving from it would return undefined for every tenant.
    const fetchMock = stubTenant({ subType: 'Whale / dolphin watching' });
    vi.stubGlobal('fetch', fetchMock);
    await getTenantSubtype();

    const url = String(fetchMock.mock.calls[0][0]);
    expect(url).toContain('/tenant?tenantId=');
    expect(url).not.toContain('/profile');
  });

  it('caches, so concurrent callers share one request', async () => {
    const fetchMock = stubTenant({ subType: 'Whale / dolphin watching' });
    vi.stubGlobal('fetch', fetchMock);

    const [a, b, c] = await Promise.all([getTenantSubtype(), getTenantSubtype(), getTenantSubtype()]);

    expect([a, b, c]).toEqual([WHALE_WATCHING_SUBTYPE, WHALE_WATCHING_SUBTYPE, WHALE_WATCHING_SUBTYPE]);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await getTenantSubtype();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('re-fetches after resetSubtypeCache', async () => {
    // The logout path: without this the next tenant inherits the previous
    // tenant's dashboard until a hard refresh.
    const fetchMock = stubTenant({ subType: 'Whale / dolphin watching' });
    vi.stubGlobal('fetch', fetchMock);

    await getTenantSubtype();
    resetSubtypeCache();
    await getTenantSubtype();

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('returns null for a tenant with no sub-type', async () => {
    vi.stubGlobal('fetch', stubTenant({ subType: null }));
    await expect(getTenantSubtype()).resolves.toBeNull();
  });

  it('returns null rather than throwing on a network error', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('offline'); }));
    await expect(getTenantSubtype()).resolves.toBeNull();
  });

  it('returns null on a non-200 response', async () => {
    vi.stubGlobal('fetch', stubTenant({ message: 'nope' }, 403));
    await expect(getTenantSubtype()).resolves.toBeNull();
  });

  it('returns null when nobody is logged in', async () => {
    localStorage.clear();
    const fetchMock = stubTenant({ subType: 'Whale / dolphin watching' });
    vi.stubGlobal('fetch', fetchMock);

    await expect(getTenantSubtype()).resolves.toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('warns in development about a sub-type matching no known value', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.stubGlobal('fetch', stubTenant({ subType: 'Whale/dolphin watching' }));

    const result = await getTenantSubtype();

    // Returned as-is - the caller decides - but flagged, because a typo
    // here is otherwise indistinguishable from having no sub-type.
    expect(result).toBe('Whale/dolphin watching');
    expect(isWhaleWatching(result)).toBe(false);
    if (import.meta.env.DEV) expect(warn).toHaveBeenCalled();
  });
});

describe('isWhaleWatching', () => {
  it('matches only the exact sub-type', () => {
    expect(isWhaleWatching(WHALE_WATCHING_SUBTYPE)).toBe(true);
    expect(isWhaleWatching('Water sports / diving')).toBe(false);
    expect(isWhaleWatching('whale / dolphin watching')).toBe(false);
    expect(isWhaleWatching(null)).toBe(false);
    expect(isWhaleWatching(undefined)).toBe(false);
  });
});
