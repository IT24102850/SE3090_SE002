import { TOURISM_SUB_TYPES } from '../booking/types';

/* Tenant sub-type resolution for callers that are not React components, or
 * that need the answer before any RTK Query hook has run.
 *
 * The registry in ./subtypes/ is still the source of truth for what each
 * sub-type *means*; this module only answers "which one is this tenant?"
 * and caches it, because the sidebar and the dashboard router both need it
 * on first paint and neither should trigger its own request. */

/** Copied from TOURISM_SUB_TYPES rather than retyped, so a change to the
 *  registration dropdown cannot silently desynchronise this constant.
 *  Index 2 is asserted below - a reorder there is caught at module load,
 *  not by a tenant quietly getting the wrong dashboard months later. */
export const WHALE_WATCHING_SUBTYPE = TOURISM_SUB_TYPES[2];

if (WHALE_WATCHING_SUBTYPE !== 'Whale / dolphin watching') {
  // Deliberately loud: every whale-watching tenant falls back to the generic
  // dashboard if this constant drifts, and nothing else would report it.
  throw new Error(
    `WHALE_WATCHING_SUBTYPE resolved to "${WHALE_WATCHING_SUBTYPE}" - TOURISM_SUB_TYPES has been reordered. ` +
    'Fix the index in features/dashboard/subtype.ts.',
  );
}

const API_BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:5298/api';

/** Resolved value, and the in-flight promise so concurrent callers on first
 *  paint share one request rather than racing. */
let cached: string | null | undefined;
let inFlight: Promise<string | null> | null = null;

/** Clears the memoised sub-type. Must be called on logout, otherwise the
 *  next tenant to log in on this browser inherits the previous tenant's
 *  dashboard until a hard refresh. */
export function resetSubtypeCache(): void {
  cached = undefined;
  inFlight = null;
}

/**
 * The current tenant's `Tenant.SubType`, or null.
 *
 * Reads GET /api/tenant, not the business-profile endpoint: the profile
 * response is the public "listing" projection and does not carry SubType at
 * all, so resolving from it would return undefined for every tenant and drop
 * everybody onto the generic dashboard.
 *
 * Returns null - never throws - on any failure (no token, network error,
 * non-200, malformed body). A tenant whose sub-type cannot be determined
 * gets the generic dashboard, which is the correct degraded behaviour.
 */
export async function getTenantSubtype(): Promise<string | null> {
  if (cached !== undefined) return cached;
  if (inFlight) return inFlight;

  inFlight = (async (): Promise<string | null> => {
    try {
      const token = localStorage.getItem('token');
      const raw = localStorage.getItem('user');
      if (!token || !raw) return null;

      const tenantId = (JSON.parse(raw) as { tenantId?: string })?.tenantId;
      if (!tenantId) return null;

      const response = await fetch(
        `${API_BASE_URL}/tenant?tenantId=${encodeURIComponent(tenantId)}`,
        { headers: { Authorization: `Bearer ${token}` } },
      );
      if (!response.ok) return null;

      const subType = ((await response.json()) as { subType?: string | null })?.subType ?? null;
      if (subType && import.meta.env.DEV && !TOURISM_SUB_TYPES.includes(subType)) {
        // A typo'd sub-type is indistinguishable from "no sub-type" at
        // runtime, so say so in development rather than failing silently.
        console.warn(
          `[subtype] Tenant.SubType "${subType}" matches no entry in TOURISM_SUB_TYPES. ` +
          'This tenant will get the generic dashboard.',
        );
      }
      return subType;
    } catch {
      return null;
    }
  })();

  const result = await inFlight;
  cached = result;
  inFlight = null;
  return result;
}

/** True when this tenant runs whale-watching departures. */
export function isWhaleWatching(subType: string | null | undefined): boolean {
  return subType === WHALE_WATCHING_SUBTYPE;
}
