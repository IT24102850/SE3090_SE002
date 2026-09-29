import api from '../../api/axiosConfig';

/* Typed client for Unify's own subscription - what a tenant admin pays US,
 * as opposed to features/billing, which is what a tenant charges their own
 * customers. Two different ledgers; keeping the clients apart keeps the two
 * from being confused on screen. */

export type BillingPeriod = 'Monthly' | 'SemiAnnual' | 'Annual';

export type SubscriptionStatus = 'Trialing' | 'Active' | 'PastDue' | 'Expired' | 'Cancelling';

export interface PlanPrice {
  id: string;
  period: BillingPeriod;
  periodLabel: string;
  currency: string;
  amount: number;
  monthlyEquivalent: number;
  savingsPercent: number;
  isBestValue: boolean;
  /** The same months bought one at a time - the struck-through anchor. */
  comparedAtAmount: number;
}

export interface Plan {
  id: string;
  code: string;
  name: string;
  tier: number;
  tagline: string;
  highlights: string[];
  isMostPopular: boolean;
  trialDays: number;
  maxBranches: number | null;
  maxStaffSeats: number | null;
  maxBookingsPerMonth: number | null;
  aiRunsPerMonth: number | null;
  smsPerMonth: number | null;
  spotlightsPerMonth: number;
  supportResponseHours: number | null;
  features: string[];
  prices: PlanPrice[];
}

export interface AddOn {
  id: string;
  code: string;
  name: string;
  tagline: string;
  category: string;
  creditType: string;
  quantity: number;
  expiryDays: number;
  amount: number;
  currency: string;
  comparedAtAmount: number;
  savingsPercent: number;
  isBestValue: boolean;
  minimumTier: number;
  availableOnCurrentPlan: boolean;
}

export interface Promotion {
  code: string;
  name: string;
  kind: 'Intro' | 'WinBack' | 'Loyalty' | 'Campaign';
  percentOff: number | null;
  amountOff: number | null;
  currency: string | null;
  planCode: string | null;
  period: BillingPeriod | null;
  terms: number;
  endsAt: string | null;
  description: string;
}

export interface PricingCatalog {
  currency: string;
  currencies: string[];
  plans: Plan[];
  addOns: AddOn[];
  featuredOffer: Promotion | null;
}

export interface UsageMeter {
  metric: string;
  label: string;
  used: number;
  limit: number | null;
  credits: number;
}

export interface Subscription {
  tenantId: string;
  planCode: string;
  planName: string;
  tier: number;
  status: SubscriptionStatus;
  hasAccess: boolean;
  period: BillingPeriod;
  periodLabel: string;
  currency: string;
  amount: number;
  currentPeriodStart: string;
  currentPeriodEnd: string | null;
  trialEndsAt: string | null;
  trialAvailable: boolean;
  trialDays: number;
  autoRenew: boolean;
  cancelAtPeriodEnd: boolean;
  graceEndsAt: string | null;
  extraSeats: number;
  isComplimentary: boolean;
  promotionCode: string | null;
  features: string[];
  usage: UsageMeter[];
  credits: Record<string, number>;
  lastPaymentAt: string | null;
}

export interface InvoiceLine {
  description: string;
  quantity: number;
  unitAmount: number;
  amount: number;
}

export interface PlatformInvoice {
  id: string;
  number: string;
  kind: 'Subscription' | 'AddOn';
  planCode: string | null;
  period: BillingPeriod | null;
  currency: string;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  status: 'Draft' | 'Issued' | 'Paid' | 'Failed' | 'Cancelled' | 'Refunded';
  promotionCode: string | null;
  issuedAt: string;
  dueAt: string;
  paidAt: string | null;
  periodStart: string | null;
  periodEnd: string | null;
  lines: InvoiceLine[];
}

export interface Quote {
  planCode: string;
  planName: string;
  period: BillingPeriod;
  periodLabel: string;
  currency: string;
  listAmount: number;
  discount: number;
  prorationCredit: number;
  total: number;
  renewalAmount: number;
  promotionCode: string | null;
  promotionMessage: string | null;
  periodStart: string;
  periodEnd: string;
  lines: InvoiceLine[];
}

export interface CheckoutResult {
  paymentId: string;
  invoiceId: string;
  invoiceNumber: string;
  provider: string;
  status: 'Pending' | 'Succeeded' | 'Failed' | 'Refunded';
  amount: number;
  currency: string;
  redirectUrl: string | null;
  clientSecret: string | null;
  publicKey: string | null;
  simulated: boolean;
  settlementCurrency: string | null;
  settlementAmount: number | null;
  exchangeRate: number | null;
  /** True when nothing needed paying and the plan is already live. */
  completed: boolean;
}

export interface ProviderOption {
  provider: string;
  live: boolean;
  label: string;
}

export interface Entitlements {
  plan: string;
  planName: string;
  tier: number;
  status: SubscriptionStatus;
  hasAccess: boolean;
  isTrialing: boolean;
  trialEndsAt: string | null;
  currentPeriodEnd: string | null;
  graceEndsAt: string | null;
  cancelAtPeriodEnd: boolean;
  features: string[];
  limits: {
    maxBranches: number | null;
    maxStaffSeats: number | null;
    maxResources: number | null;
    maxBookingsPerMonth: number | null;
    aiRunsPerMonth: number | null;
    smsPerMonth: number | null;
  };
  credits: Record<string, number>;
}

/** The body of every 402 the API returns - see PlanGate on the backend. */
export interface Paywall {
  reason: 'feature' | 'cap' | 'quota';
  feature: string | null;
  metric: string | null;
  used: number | null;
  limit: number | null;
  currentPlan: string;
  requiredPlan: string | null;
  requiredPlanName: string | null;
  addOnCode: string | null;
  upgradeUrl: string;
}

export const subscriptionApi = {
  catalog: (currency?: string) =>
    api.get<PricingCatalog>('/subscription/plans', { params: currency ? { currency } : undefined }).then((r) => r.data),

  providers: () =>
    api.get<{ providers: ProviderOption[]; defaultProvider: string; defaultCurrency: string }>('/subscription/providers')
      .then((r) => r.data),

  current: () => api.get<Subscription>('/subscription').then((r) => r.data),

  entitlements: () => api.get<Entitlements>('/subscription/entitlements').then((r) => r.data),

  invoices: () => api.get<PlatformInvoice[]>('/subscription/invoices').then((r) => r.data),

  quote: (body: { planCode: string; period?: BillingPeriod; currency?: string; promotionCode?: string }) =>
    api.post<Quote>('/subscription/quote', body).then((r) => r.data),

  checkout: (body: {
    planCode: string;
    period?: BillingPeriod;
    currency?: string;
    promotionCode?: string;
    provider?: string;
    returnUrl?: string;
  }) => api.post<CheckoutResult>('/subscription/checkout', body).then((r) => r.data),

  buyAddOn: (body: { addOnCode: string; quantity?: number; currency?: string; provider?: string; returnUrl?: string }) =>
    api.post<CheckoutResult>('/subscription/addons/checkout', body).then((r) => r.data),

  payInvoice: (invoiceId: string, body: { provider?: string; returnUrl?: string }) =>
    api.post<CheckoutResult>(`/subscription/invoices/${invoiceId}/pay`, body).then((r) => r.data),

  confirm: (paymentId: string, simulateFailure = false) =>
    api.post<PlatformInvoice>('/subscription/confirm', { paymentId, simulateFailure }).then((r) => r.data),

  startTrial: (planCode?: string) =>
    api.post<Subscription>('/subscription/trial', { planCode }).then((r) => r.data),

  cancel: (reason?: string, immediate = false) =>
    api.post<Subscription>('/subscription/cancel', { reason, immediate }).then((r) => r.data),

  resume: () => api.post<Subscription>('/subscription/resume').then((r) => r.data),

  validatePromotion: (body: { code: string; planCode: string; period?: BillingPeriod; currency?: string }) =>
    api.post<{ valid: boolean; message: string; quote: Quote }>('/subscription/promotions/validate', body).then((r) => r.data),
};

/** Reads a 402 body off a rejected request, or null if it was not a paywall. */
export function paywallOf(err: unknown): Paywall | null {
  const e = err as { response?: { status?: number; data?: { paywall?: Paywall } } };
  if (e?.response?.status !== 402) return null;
  return e.response.data?.paywall ?? null;
}

/** "3 / 60" style caps, where null means unlimited. */
export function limitLabel(limit: number | null): string {
  return limit === null ? 'Unlimited' : limit.toLocaleString();
}

export const CREDIT_LABELS: Record<string, string> = {
  spotlight: 'Spotlights',
  'ai-run': 'AI credits',
  sms: 'Message credits',
  seat: 'Extra seats',
};
