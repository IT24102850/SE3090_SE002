import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react';
import type { BaseQueryFn, FetchArgs, FetchBaseQueryError } from '@reduxjs/toolkit/query/react';
import { API_BASE_URL } from '../../api/apiBaseUrl';
import { clearPlatformSession, getPlatformToken } from './platformSession';

/* The platform console's own API slice. Separate from bookingApi so the
 * owner's token (sessionStorage, MFA-minted, session-bound) is never mixed
 * with a tenant login's, and so a 401 here sends the browser to the
 * platform sign-in rather than the tenant one. */

// ── Types ───────────────────────────────────────────────────────────

export interface PlatformLoginResult {
  status: 'ok' | 'mfaRequired' | 'mfaSetupRequired';
  message?: string;
  accessToken?: string;
  expiresAt?: string;
  idleTimeoutMinutes?: number;
  user?: { id: string; email: string; fullName: string; role: string };
  setupToken?: string;
  secret?: string;
  otpauthUri?: string;
}

export interface PlatformMe {
  id: string; email: string; fullName: string; role: string;
  mfaEnabledAt: string | null; lastLoginAt: string | null; lastLoginIp: string | null; passwordChangedAt: string | null;
  session: { id: string; createdAt: string; expiresAt: string; idleTimeoutMinutes: number };
}

export interface PlatformSessionRow {
  id: string; ipAddress: string; userAgent: string; createdAt: string; lastSeenAt: string; expiresAt: string;
  revokedAt: string | null; revokedReason: string | null; isCurrent: boolean; isLive: boolean;
}

export interface AuditRow {
  id: string; createdAt: string; actorEmail: string; action: string; targetType: string | null; targetId?: string | null;
  targetLabel: string | null; detail: string | null; succeeded: boolean; ipAddress: string; userAgent?: string;
}

export interface PlatformOverview {
  generatedAt: string;
  tenants: {
    total: number; active: number; suspended: number; new30d: number;
    byType: { businessType: string; count: number; active: number }[];
    perWeek: { weekStart: string; count: number }[];
  };
  users: { total: number; new30d: number; byRole: { role: string; count: number }[] };
  bookings: {
    total: number; today: number; last7d: number; last30d: number; previous30d: number; upcoming: number;
    perDay: { date: string; count: number }[];
  };
  topTenants: { id: string; name: string; businessType: string; isActive: boolean; bookings30d: number }[];
  recentAudit: AuditRow[];
  security: {
    mfaEnabledAt: string | null; lastLoginAt: string | null; lastLoginIp: string | null; passwordChangedAt: string | null;
    liveSessions: number; failedLogins24h: number; lockedUntil: string | null;
  };
  system: { environment: string; startedAt: string; uptimeSeconds: number; appliedMigrations: number; pendingMigrations: number; runtime: string };
}

export interface PlatformTenantRow {
  id: string; name: string; businessType: string; subType: string | null; isActive: boolean; createdAt: string;
  contactEmail: string | null; logoUrl: string | null; userCount: number; branchCount: number; bookingCount: number;
  bookings30d: number; lastBookingAt: string | null; adminEmail: string | null;
}

export interface PlatformTenantDetail {
  id: string; name: string; businessType: string; subType: string | null; isActive: boolean; createdAt: string; updatedAt: string;
  contactEmail: string | null; contactPhone: string | null; website: string | null; logoUrl: string | null; shortTagline: string | null;
  users: { id: string; fullName: string; email: string; role: string; isActive: boolean; isApproved: boolean; createdAt: string }[];
  branches: { id: string; name: string; address: string; isActive: boolean }[];
  bookingsByStatus: { status: string; count: number }[];
  resources: number; bookingTypes: number; bookings30d: number;
  audit: { id: string; createdAt: string; actorEmail: string; action: string; detail: string | null; succeeded: boolean }[];
}

export interface PlatformUserRow {
  id: string; fullName: string; email: string; phone: string; role: string; isActive: boolean; isApproved: boolean; createdAt: string;
  tenantId: string; tenantName: string; tenantActive: boolean; tenantBusinessType: string;
  /** A customer identity in the hidden pool tenant; memberships are folded into membershipCount. */
  isGlobalCustomer: boolean; membershipCount: number;
}

export interface Paged<T> { items: T[]; total: number; page: number; pageSize: number; totalPages: number }

// ── Base query ──────────────────────────────────────────────────────

const rawBaseQuery = fetchBaseQuery({
  baseUrl: API_BASE_URL,
  prepareHeaders: (headers) => {
    const token = getPlatformToken();
    if (token) headers.set('Authorization', `Bearer ${token}`);
    return headers;
  },
});

const baseQuery: BaseQueryFn<string | FetchArgs, unknown, FetchBaseQueryError> = async (args, api, extra) => {
  const result = await rawBaseQuery(args, api, extra);
  const url = typeof args === 'string' ? args : args.url;
  // A 401 on anything but the sign-in calls means the session is gone
  // (revoked, idle, expired) - drop the token and go back to the door.
  if (result.error?.status === 401 && !url.startsWith('platform/auth/login') && !url.startsWith('platform/auth/mfa')) {
    clearPlatformSession();
    if (!window.location.pathname.startsWith('/platform/login')) {
      window.location.assign('/platform/login?reason=expired');
    }
  }
  return result;
};

const withOtp = (otp?: string) => (otp ? { 'X-Platform-Otp': otp } : undefined);


/* ── Revenue: Unify's own subscription business ───────────────────── */

export interface RevenueOverview {
  generatedAt: string;
  currency: string;
  mrr: number;
  arr: number;
  arpa: number;
  collected30d: number;
  addOnRevenue30d: number;
  tenants: {
    total: number; paying: number; free: number; trialing: number; pastDue: number;
    cancelling: number; complimentary: number; paidConversionRate: number | null;
  };
  funnel: {
    trialsStarted30d: number; trialsConverted30d: number; trialsExpired30d: number;
    trialConversionRate: number | null;
    newPaid30d: number; churned30d: number; churnRate: number | null;
  };
  planMix: { planCode: string; count: number; paying: number; mrr: number }[];
  termMix: { period: string; label: string; count: number }[];
  recentEvents: {
    id: string; createdAt: string; eventType: string; fromPlanCode: string | null; toPlanCode: string | null;
    period: string | null; currency: string | null; amount: number | null; actorEmail: string | null;
    detail: string | null; tenantId: string; tenantName: string;
  }[];
}

export interface RevenueSubscriptionRow {
  id: string; tenantId: string; tenantName: string; businessType: string;
  planCode: string; tier: number; status: string; period: string; currency: string; amount: number;
  currentPeriodStart: string; currentPeriodEnd: string | null; trialEndsAt: string | null; graceEndsAt: string | null;
  autoRenew: boolean; cancelAtPeriodEnd: boolean; isComplimentary: boolean; extraSeats: number;
  lastPaymentAt: string | null; startedAt: string | null; openInvoices: number;
}

export interface RevenueInvoiceRow {
  id: string; number: string; kind: string; planCode: string | null; period: string | null;
  currency: string; total: number; status: string; issuedAt: string; dueAt: string; paidAt: string | null;
  tenantId: string; tenantName: string; provider: string | null;
}


/* ── Platform Operations Copilot ───────────────────────────────────── */

export interface CopilotPlanStep {
  order: number;
  action: string;
  assigned_agent: string;
  description: string;
}

export interface CopilotTenantRisk {
  tenant_id: string;
  tenant_name: string;
  plan_code: string;
  status: string;
  risk_score: number;
  risk_factors: string[];
  monthly_value: number;
  open_invoices: number;
}

export interface CopilotIntervention {
  tenant_id: string;
  tenant_name: string;
  kind: string;
  extend_days: number | null;
  comp_plan_code: string | null;
  comp_months: number | null;
  rationale: string;
  estimated_cost: number;
  protected_value: number;
  confidence: number;
}

export interface CopilotVerdict {
  tenant_id: string;
  kind: string;
  accepted: boolean;
  reason: string | null;
  adjusted_from: string | null;
}

export interface CopilotRunSummary {
  id: string;
  traceId: string;
  objective: string;
  status: string;
  approvalStatus: string;
  modelDriven: boolean;
  estimatedCost: number;
  currency: string;
  createdAt: string;
  completedAt: string | null;
  decidedByEmail: string | null;
}

export interface CopilotRun extends CopilotRunSummary {
  decidedAt: string | null;
  decisionReason: string | null;
  errorLog: string | null;
  plan: { plan: CopilotPlanStep[]; assigned_agents: string[]; interpreted_goal: string; confidence_score: number } | null;
  analysis: { at_risk: CopilotTenantRisk[]; criteria_used: string[]; platform_summary: string } | null;
  proposals: { interventions: CopilotIntervention[]; reasoning: string } | null;
  validation: {
    is_allowed: boolean;
    requires_human_approval: boolean;
    accepted: CopilotIntervention[];
    verdicts: CopilotVerdict[];
    rejection_reason: string | null;
    validation_notes: string[];
    total_estimated_cost: number;
  } | null;
  observability: { tool_calls: string | null; llm_calls: string | null; agent_steps: string | null } | null;
  outcome: { tenantId: string; tenantName: string; kind: string; applied: boolean; detail: string }[] | null;
}

export const platformApi = createApi({
  reducerPath: 'platformApi',
  baseQuery,
  tagTypes: ['Overview', 'Tenants', 'Tenant', 'Users', 'Audit', 'Sessions', 'Me', 'Revenue', 'Copilot'],
  endpoints: (builder) => ({
    // auth
    login: builder.mutation<PlatformLoginResult, { email: string; password: string; code?: string }>({
      query: (body) => ({ url: 'platform/auth/login', method: 'POST', body }),
    }),
    enrolMfa: builder.mutation<PlatformLoginResult, { setupToken: string; code: string }>({
      query: (body) => ({ url: 'platform/auth/mfa/enrol', method: 'POST', body }),
    }),
    me: builder.query<PlatformMe, void>({ query: () => 'platform/auth/me', providesTags: ['Me'] }),
    logout: builder.mutation<{ message: string }, void>({
      query: () => ({ url: 'platform/auth/logout', method: 'POST' }),
    }),
    sessions: builder.query<PlatformSessionRow[], void>({ query: () => 'platform/auth/sessions', providesTags: ['Sessions'] }),
    revokeSession: builder.mutation<{ message: string }, string>({
      query: (id) => ({ url: `platform/auth/sessions/${id}/revoke`, method: 'POST' }),
      invalidatesTags: ['Sessions', 'Audit', 'Overview'],
    }),
    revokeOtherSessions: builder.mutation<{ revoked: number }, void>({
      query: () => ({ url: 'platform/auth/sessions/revoke-others', method: 'POST' }),
      invalidatesTags: ['Sessions', 'Audit', 'Overview'],
    }),
    changePassword: builder.mutation<{ message: string }, { currentPassword: string; newPassword: string; code: string }>({
      query: (body) => ({ url: 'platform/auth/change-password', method: 'POST', body }),
      invalidatesTags: ['Me', 'Sessions', 'Audit', 'Overview'],
    }),

    // data
    overview: builder.query<PlatformOverview, void>({ query: () => 'platform/overview', providesTags: ['Overview'] }),
    tenants: builder.query<Paged<PlatformTenantRow> & { businessTypes: string[] }, { search?: string; status?: string; businessType?: string; page?: number; pageSize?: number }>({
      query: (params) => ({ url: 'platform/tenants', params }),
      providesTags: ['Tenants'],
    }),
    tenant: builder.query<PlatformTenantDetail, string>({
      query: (id) => `platform/tenants/${id}`,
      providesTags: (_r, _e, id) => [{ type: 'Tenant', id }],
    }),
    setTenantActive: builder.mutation<{ id: string; isActive: boolean; message: string }, { id: string; active: boolean; reason?: string; otp?: string }>({
      query: ({ id, active, reason, otp }) => ({
        url: `platform/tenants/${id}/${active ? 'reactivate' : 'suspend'}`,
        method: 'POST',
        body: { reason },
        headers: withOtp(otp),
      }),
      invalidatesTags: (_r, _e, { id }) => ['Tenants', 'Overview', 'Audit', 'Users', { type: 'Tenant', id }],
    }),
    users: builder.query<Paged<PlatformUserRow>, { search?: string; role?: string; tenantId?: string; status?: string; page?: number; pageSize?: number }>({
      query: (params) => ({ url: 'platform/users', params }),
      providesTags: ['Users'],
    }),
    setUserActive: builder.mutation<{ id: string; isActive: boolean; message: string }, { id: string; active: boolean; reason?: string; otp?: string }>({
      query: ({ id, active, reason, otp }) => ({
        url: `platform/users/${id}/${active ? 'activate' : 'deactivate'}`,
        method: 'POST',
        body: { reason },
        headers: withOtp(otp),
      }),
      invalidatesTags: ['Users', 'Overview', 'Audit', 'Tenant'],
    }),
    resetUserPassword: builder.mutation<{ id: string; temporaryPassword: string; message: string }, { id: string; reason?: string; otp?: string }>({
      query: ({ id, reason, otp }) => ({
        url: `platform/users/${id}/reset-password`,
        method: 'POST',
        body: { reason },
        headers: withOtp(otp),
      }),
      invalidatesTags: ['Audit', 'Overview'],
    }),
    audit: builder.query<Paged<AuditRow> & { actions: string[] }, { action?: string; succeeded?: boolean; search?: string; page?: number; pageSize?: number }>({
      query: (params) => ({ url: 'platform/audit', params }),
      providesTags: ['Audit'],
    }),

    // revenue
    revenue: builder.query<RevenueOverview, void>({ query: () => 'platform/revenue', providesTags: ['Revenue'] }),

    // copilot
    copilotRuns: builder.query<CopilotRunSummary[], void>({
      query: () => 'platform/copilot',
      providesTags: ['Copilot'],
    }),
    copilotRun: builder.query<CopilotRun, string>({
      query: (id) => `platform/copilot/${id}`,
      providesTags: ['Copilot'],
    }),
    startCopilot: builder.mutation<CopilotRun, { objective: string; maxInterventions: number; maxCompMonths: number; currency: string }>({
      query: (body) => ({ url: 'platform/copilot', method: 'POST', body }),
      invalidatesTags: ['Copilot', 'Audit'],
    }),
    approveCopilot: builder.mutation<CopilotRun, { id: string; tenantIds: string[]; reason?: string; otp?: string }>({
      query: ({ id, otp, ...body }) => ({
        url: `platform/copilot/${id}/approve`,
        method: 'POST',
        body,
        headers: withOtp(otp),
      }),
      invalidatesTags: ['Copilot', 'Revenue', 'Audit', 'Tenants'],
    }),
    rejectCopilot: builder.mutation<CopilotRun, { id: string; reason?: string }>({
      query: ({ id, ...body }) => ({ url: `platform/copilot/${id}/reject`, method: 'POST', body }),
      invalidatesTags: ['Copilot', 'Audit'],
    }),
    reviseCopilot: builder.mutation<CopilotRun, { id: string; reason?: string }>({
      query: ({ id, ...body }) => ({ url: `platform/copilot/${id}/revise`, method: 'POST', body }),
      invalidatesTags: ['Copilot', 'Audit'],
    }),
    revenueSubscriptions: builder.query<Paged<RevenueSubscriptionRow>, { plan?: string; status?: string; page?: number; pageSize?: number }>({
      query: (params) => ({ url: 'platform/revenue/subscriptions', params }),
      providesTags: ['Revenue'],
    }),
    revenueInvoices: builder.query<Paged<RevenueInvoiceRow>, { status?: string; page?: number; pageSize?: number }>({
      query: (params) => ({ url: 'platform/revenue/invoices', params }),
      providesTags: ['Revenue'],
    }),
    compSubscription: builder.mutation<{ message: string }, { tenantId: string; planCode: string; period?: string; months: number; reason: string; otp?: string }>({
      query: ({ tenantId, otp, ...body }) => ({
        url: `platform/revenue/subscriptions/${tenantId}/comp`,
        method: 'POST',
        body,
        headers: withOtp(otp),
      }),
      invalidatesTags: ['Revenue', 'Audit', 'Overview'],
    }),
    extendSubscription: builder.mutation<{ currentPeriodEnd: string; message: string }, { tenantId: string; days: number; reason: string; otp?: string }>({
      query: ({ tenantId, otp, ...body }) => ({
        url: `platform/revenue/subscriptions/${tenantId}/extend`,
        method: 'POST',
        body,
        headers: withOtp(otp),
      }),
      invalidatesTags: ['Revenue', 'Audit'],
    }),
  }),
});

export const {
  useLoginMutation,
  useEnrolMfaMutation,
  useMeQuery,
  useLogoutMutation,
  useSessionsQuery,
  useRevokeSessionMutation,
  useRevokeOtherSessionsMutation,
  useChangePasswordMutation,
  useOverviewQuery,
  useTenantsQuery,
  useTenantQuery,
  useSetTenantActiveMutation,
  useUsersQuery,
  useSetUserActiveMutation,
  useResetUserPasswordMutation,
  useAuditQuery,
  useRevenueQuery,
  useRevenueSubscriptionsQuery,
  useRevenueInvoicesQuery,
  useCompSubscriptionMutation,
  useExtendSubscriptionMutation,
  useCopilotRunsQuery,
  useCopilotRunQuery,
  useStartCopilotMutation,
  useApproveCopilotMutation,
  useRejectCopilotMutation,
  useReviseCopilotMutation,
} = platformApi;

/** Pulls the server's message out of an RTK Query error, with a fallback. */
export function errorMessage(error: unknown, fallback = 'Something went wrong.'): string {
  const e = error as { data?: { message?: string }; status?: number | string } | undefined;
  if (e?.data?.message) return e.data.message;
  if (e?.status === 429) return 'Too many attempts. Wait a minute and try again.';
  if (e?.status === 'FETCH_ERROR') return 'Cannot reach the server.';
  return fallback;
}

/** True when a protected action was refused for want of a fresh code. */
export function needsOtp(error: unknown): boolean {
  const e = error as { status?: number; data?: { status?: string } } | undefined;
  return e?.status === 428 || e?.data?.status === 'otpRequired';
}
