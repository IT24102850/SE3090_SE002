import api from '../../api/axiosConfig';

/* Typed client for the billing & payments API (backend component 3).
 * Plain axios over the shared instance, which already attaches the JWT and
 * handles 401s; the tenant always comes from the token, never the client. */

// ── Invoices ─────────────────────────────────────────────────────────────

export interface InvoiceItem {
  id: string;
  description: string;
  quantity: number;
  unitPrice: number;
  amount: number;
  category: string;
}

export interface Payment {
  id: string;
  invoiceId: string | null;
  amount: number;
  method: string;
  transactionRef: string | null;
  gatewayResponse: string | null;
  paidAt: string | null;
  createdAt: string;
  status: 'Pending' | 'Succeeded' | 'Failed' | 'Refunded';
  provider: string | null;
  payerLabel: string | null;
}

export interface ValidationIssue {
  code: string;
  severity: 'info' | 'warning' | 'error';
  message: string;
}

export interface Invoice {
  id: string;
  tenantId: string;
  customerId: string;
  bookingId: string | null;
  invoiceNumber: string;
  totalAmount: number;
  discount: number;
  tax: number;
  finalAmount: number;
  status: 'Draft' | 'Issued' | 'PartiallyPaid' | 'Paid' | 'Overdue' | 'Cancelled';
  dueDate: string;
  currency: string;
  createdAt: string;
  items: InvoiceItem[];
  payments: Payment[];
  branchId: string | null;
  subscriptionId: string | null;
  templateId: string | null;
  discountCode: string | null;
  notes: string | null;
  scheduleGroup: string | null;
  scheduleLabel: string | null;
  amountPaid: number;
  balanceDue: number;
  isOverdue: boolean;
  customerName: string | null;
  validationIssues?: ValidationIssue[] | null;
}

export interface Paged<T> {
  items: T[];
  page: number;
  pageSize: number;
  totalCount: number;
  totalPages: number;
}

export interface InvoiceQuery {
  page?: number;
  pageSize?: number;
  status?: string;
  customerId?: string;
  from?: string;
  to?: string;
  search?: string;
}

export interface CreateInvoiceItem {
  description: string;
  quantity: number;
  unitPrice: number;
  category?: string;
}

export interface CreateInvoiceRequest {
  customerId: string;
  dueDate: string;
  currency: string;
  items: CreateInvoiceItem[];
  discount?: number;
  tax?: number;
  discountPercent?: number | null;
  taxRatePercent?: number | null;
  discountCode?: string | null;
  notes?: string | null;
  bookingId?: string | null;
  templateId?: string | null;
  invoiceNumber?: string | null;
}

export interface InvoiceValidationResult {
  isValid: boolean;
  requiresReview: boolean;
  subtotal: number;
  discountPercent: number;
  taxPercent: number;
  finalAmount: number;
  issues: ValidationIssue[];
}

export interface Receipt {
  receiptNumber: string;
  invoiceId: string;
  invoiceNumber: string;
  customerId: string;
  dueDate: string;
  currency: string;
  totalAmount: number;
  discount: number;
  tax: number;
  finalAmount: number;
  totalPaid: number;
  balanceDue: number;
  paymentStatus: string;
  issuedAt: string;
  items: InvoiceItem[];
  payments: Payment[];
  businessName: string | null;
  customerName: string | null;
  customerEmail: string | null;
  notes: string | null;
  template: InvoiceTemplate | null;
}

export interface DeliveryResult {
  channel: string;
  recipient: string;
  delivered: boolean;
  simulated: boolean;
  providerMessageId: string | null;
  error: string | null;
}

export interface AdjustResult {
  applied: boolean;
  requiresApproval: boolean;
  approvalWorkflowId: string | null;
  invoice: Invoice;
  message: string;
}

export interface SchedulePart {
  label: string;
  amount?: number | null;
  percent?: number | null;
  dueDate: string;
}

// ── Checkout ─────────────────────────────────────────────────────────────

export interface CheckoutResponse {
  paymentId: string;
  invoiceId: string;
  provider: 'Stripe' | 'PayPal' | 'Manual';
  status: Payment['status'];
  amount: number;
  currency: string;
  clientSecret: string | null;
  redirectUrl: string | null;
  publicKey: string | null;
  externalReference: string | null;
  simulated: boolean;
}

export interface AvailableProviders {
  providers: { provider: 'Stripe' | 'PayPal'; name: string; publicKey: string | null; isTestMode: boolean; currency: string }[];
  sandboxAvailable: boolean;
}

// ── Subscriptions ────────────────────────────────────────────────────────

export interface Subscription {
  id: string;
  tenantId: string;
  customerId: string;
  planName: string;
  amount: number;
  billingCycle: string;
  startDate: string;
  endDate: string;
  autoRenew: boolean;
  status: 'Active' | 'Frozen' | 'PendingCancel' | 'Cancelled' | 'Expired';
  createdAt: string;
  branchId: string | null;
  paymentStatus: string;
  nextBillingAt: string | null;
  lastPaymentAt: string | null;
  notes: string | null;
  customerName: string | null;
}

export interface PlanOption {
  planName: string;
  amount: number;
  billingCycle: string;
  activeMembers: number;
}

export interface RenewalEntry {
  subscriptionId: string;
  customerId: string;
  customerName: string | null;
  planName: string;
  amount: number;
  billingCycle: string;
  renewalDate: string;
  autoRenew: boolean;
  status: string;
  paymentStatus: string;
}

export interface CancelSubscriptionResult {
  applied: boolean;
  requiresApproval: boolean;
  approvalWorkflowId: string | null;
  subscription: Subscription;
  message: string;
}

// ── Insurance claims ─────────────────────────────────────────────────────

export type ClaimStatus = 'Submitted' | 'UnderReview' | 'Approved' | 'Rejected';

export interface InsuranceClaim {
  id: string;
  invoiceId: string | null;
  invoiceNumber: string | null;
  provider: string;
  policyNumber: string;
  claimAmount: number;
  status: ClaimStatus;
  submittedAt: string | null;
  approvedAt: string | null;
  rejectionReason: string | null;
  createdAt: string;
  reviewStartedAt: string | null;
  notes: string | null;
  documents: { url: string; fileName: string; uploadedAt: string }[] | null;
  customerId: string | null;
  currency: string | null;
  requiresAdminApproval: boolean;
  pendingApprovalWorkflowId: string | null;
}

export interface ClaimStatusResult {
  applied: boolean;
  requiresApproval: boolean;
  approvalWorkflowId: string | null;
  claim: InsuranceClaim;
  message: string;
}

// ── Reports ──────────────────────────────────────────────────────────────

export interface AmountByLabel { label: string; amount: number; count: number }

export interface BillingDashboard {
  from: string;
  to: string;
  currency: string;
  totalInvoiced: number;
  totalCollected: number;
  totalOutstanding: number;
  overdueAmount: number;
  overdueCount: number;
  activeSubscriptions: number;
  monthlyRecurringRevenue: number;
  pendingClaims: number;
  pendingClaimsAmount: number;
  pendingApprovals: number;
  revenueSeries: { date: string; invoiced: number; collected: number }[];
  statusBreakdown: AmountByLabel[];
  methodBreakdown: AmountByLabel[];
}

export interface OutstandingReport {
  agingDays: number;
  totalOutstanding: number;
  count: number;
  buckets: { label: string; minDays: number; maxDays: number | null; amount: number; count: number }[];
  items: {
    invoiceId: string;
    invoiceNumber: string;
    customerId: string;
    customerName: string | null;
    dueDate: string;
    daysOverdue: number;
    finalAmount: number;
    balanceDue: number;
    currency: string;
    status: string;
  }[];
}

export interface DailyRevenue {
  date: string;
  totalCollected: number;
  paymentCount: number;
  totalInvoiced: number;
  invoiceCount: number;
  averagePayment: number;
  byMethod: AmountByLabel[];
  byHour: AmountByLabel[];
  byCurrency: AmountByLabel[];
}

// ── Dynamic forms ────────────────────────────────────────────────────────

export interface JsonSchemaField {
  type: 'string' | 'number' | 'integer' | 'boolean' | 'array' | 'object';
  title?: string;
  description?: string;
  enum?: (string | number)[];
  minLength?: number;
  maxLength?: number;
  minimum?: number;
  maximum?: number;
  pattern?: string;
  format?: string;
  default?: unknown;
}

export interface JsonSchema {
  type?: 'object';
  title?: string;
  properties: Record<string, JsonSchemaField>;
  required?: string[];
}

export interface DynamicForm {
  id: string;
  formType: string;
  schema: JsonSchema;
  uiSchema: Record<string, { 'ui:widget'?: string; 'ui:placeholder'?: string; 'ui:order'?: number }> | null;
  validationRules: Record<string, unknown> | null;
  submissionCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface FormValidationResponse {
  isValid: boolean;
  errors: { field: string; message: string }[];
}

// ── Settings ─────────────────────────────────────────────────────────────

export interface PaymentGateway {
  id: string;
  name: string;
  provider: 'Stripe' | 'PayPal' | 'Manual';
  currency: string;
  isActive: boolean;
  isTestMode: boolean;
  publicKey: string | null;
  hasApiKey: boolean;
  apiKeyHint: string | null;
  hasWebhookSecret: boolean;
  webhookUrl: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface UpsertGatewayRequest {
  name: string;
  provider: string;
  currency: string;
  isActive: boolean;
  isTestMode: boolean;
  publicKey?: string | null;
  apiKey?: string | null;
  webhookSecret?: string | null;
}

export interface CommissionRule {
  id: string;
  name: string;
  role: string | null;
  ruleType: 'Percentage' | 'Fixed';
  rate: number;
  fixedAmount: number | null;
  minAmount: number | null;
  maxAmount: number | null;
  description: string | null;
  isActive: boolean;
  effectiveFrom: string | null;
  effectiveTo: string | null;
}

export interface CommissionSplit {
  dealAmount: number;
  lines: { ruleId: string; ruleName: string; role: string | null; ruleType: string; rate: number; amount: number; clamped: boolean }[];
  totalCommission: number;
  netToBusiness: number;
}

export type TemplateBlockType =
  | 'header' | 'businessInfo' | 'invoiceMeta' | 'customerInfo' | 'items' | 'totals' | 'payments' | 'notes' | 'footer';

export interface TemplateBlock {
  id: string;
  type: TemplateBlockType;
  label: string;
  visible: boolean;
}

export interface InvoiceTemplate {
  id: string;
  name: string;
  isDefault: boolean;
  layout: TemplateBlock[];
  accentColor: string;
  headerText: string | null;
  footerText: string | null;
  updatedAt: string;
}

// ── Billing agent ────────────────────────────────────────────────────────

export interface ThresholdConfig {
  maxDiscountPercent: number;
  adjustmentApprovalAmount: number;
  claimApprovalAmount: number;
  minTaxPercent: number;
  maxTaxPercent: number;
  revenueDropPercent: number;
  priceDeviationPercent: number;
  duplicateWindowMinutes: number;
  highValueInvoiceAmount: number;
}

export interface Anomaly {
  id: string;
  type: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  entityType: string;
  entityId: string | null;
  entityLabel: string | null;
  description: string;
  amount: number | null;
  evidence: Record<string, unknown>;
}

export interface Insight { type: string; title: string; detail: string; value: number | null }

export interface RecommendedAction {
  id: string;
  actionType: string;
  entityType: string;
  entityId: string | null;
  description: string;
  amount: number | null;
  requiresApproval: boolean;
  approvalReason: string | null;
  parameters: Record<string, unknown>;
}

export interface BillingAnalysis {
  workflowId: string;
  analysisType: string;
  dataRange: { from: string; to: string };
  anomalies: Anomaly[];
  insights: Insight[];
  recommendedActions: RecommendedAction[];
  confidenceScore: number;
  toolCalls: { tool: string; summary: string; itemsExamined: number; durationMs: number }[];
  approvalWorkflowIds: string[];
}

export interface BillingWorkflow {
  id: string;
  objective: string;
  kind: 'analysis' | 'approval';
  actionType: string | null;
  status: string;
  approvalStatus: string;
  amount: number | null;
  entityType: string | null;
  entityId: string | null;
  reason: string | null;
  approvedBy: string | null;
  approvedAt: string | null;
  createdAt: string;
  completedAt: string | null;
  anomalyCount: number;
  confidenceScore: number | null;
  finalOutcome: string | null;
  errorLog: string | null;
  planJson: string | null;
  toolResultsJson: string | null;
  validationResults: string | null;
}

export interface CustomerOption { id: string; fullName: string; email: string }

// ── Calls ────────────────────────────────────────────────────────────────

const clean = <T extends object>(params: T) =>
  Object.fromEntries(Object.entries(params).filter(([, v]) => v !== undefined && v !== null && v !== '')) as Partial<T>;

export const billingApi = {
  // invoices
  listInvoices: (q: InvoiceQuery = {}) => api.get<Paged<Invoice>>('/invoices', { params: clean(q) }).then((r) => r.data),
  myInvoices: (status?: string) => api.get<Paged<Invoice>>('/invoices/mine', { params: clean({ status }) }).then((r) => r.data),
  getInvoice: (id: string) => api.get<Invoice>(`/invoices/${id}`).then((r) => r.data),
  createInvoice: (body: CreateInvoiceRequest) => api.post<Invoice>('/invoices', body).then((r) => r.data),
  validateInvoice: (body: CreateInvoiceRequest) => api.post<InvoiceValidationResult>('/invoices/validate', body).then((r) => r.data),
  createSchedule: (body: { customerId: string; description: string; totalAmount: number; currency: string; parts: SchedulePart[]; category?: string; taxRatePercent?: number | null }) =>
    api.post<{ scheduleGroup: string; totalAmount: number; currency: string; invoices: Invoice[] }>('/invoices/schedule', body).then((r) => r.data),
  adjustInvoice: (id: string, body: { discount?: number | null; tax?: number | null; reason: string }) =>
    api.put<AdjustResult>(`/invoices/${id}/adjust`, body).then((r) => r.data),
  cancelInvoice: (id: string, reason?: string) => api.put<Invoice>(`/invoices/${id}/cancel`, { reason }).then((r) => r.data),
  recordPayment: (id: string, body: { amount: number; method: string; transactionRef?: string; payerLabel?: string }) =>
    api.put<{ message: string; payment: Payment; invoice: Invoice }>(`/invoices/${id}/pay`, body).then((r) => r.data),
  splitPay: (id: string, shares: { amount: number; method: string; payerLabel?: string }[]) =>
    api.put<Invoice>(`/invoices/${id}/split-pay`, { shares }).then((r) => r.data),
  receipt: (id: string) => api.get<Receipt>(`/invoices/${id}/receipt`).then((r) => r.data),
  receiptPdf: (id: string) => api.get<Blob>(`/invoices/${id}/receipt.pdf`, { responseType: 'blob' }).then((r) => r.data),
  send: (id: string, channel: string, to?: string) => api.post<DeliveryResult>(`/invoices/${id}/send`, { channel, to }).then((r) => r.data),
  remind: (id: string, channel: string, to?: string) => api.post<DeliveryResult>(`/invoices/${id}/remind`, { channel, to }).then((r) => r.data),

  // checkout
  availableProviders: () => api.get<AvailableProviders>('/payment-gateways/available').then((r) => r.data),
  checkout: (id: string, body: { provider?: string | null; method: string; amount?: number | null; returnUrl?: string | null }) =>
    api.post<CheckoutResponse>(`/invoices/${id}/checkout`, body).then((r) => r.data),
  confirmPayment: (paymentId: string, simulateFailure = false) =>
    api.post<{ payment: Payment; invoice: Invoice }>('/payments/confirm', { paymentId, simulateFailure }).then((r) => r.data),

  // subscriptions
  listSubscriptions: (q: { status?: string; customerId?: string; page?: number; pageSize?: number } = {}) =>
    api.get<Paged<Subscription>>('/subscriptions', { params: clean(q) }).then((r) => r.data),
  createSubscription: (body: { customerId: string; planName: string; amount: number; billingCycle: string; startDate: string; endDate: string; autoRenew: boolean; generateInvoice: boolean; currency: string; notes?: string }) =>
    api.post<Subscription>('/subscriptions', body).then((r) => r.data),
  cancelSubscription: (id: string, body: { reason?: string; refundAmount?: number }) =>
    api.put<CancelSubscriptionResult>(`/subscriptions/${id}/cancel`, body).then((r) => r.data),
  changePlan: (id: string, body: { planName: string; amount: number; billingCycle?: string }) =>
    api.put<Subscription>(`/subscriptions/${id}/change-plan`, body).then((r) => r.data),
  planOptions: () => api.get<PlanOption[]>('/subscriptions/plans').then((r) => r.data),
  renewals: (from: string, to: string) => api.get<RenewalEntry[]>('/subscriptions/renewals', { params: { from, to } }).then((r) => r.data),
  subscriptionInvoices: (id: string) => api.get<Paged<Invoice>>(`/subscriptions/${id}/invoices`).then((r) => r.data),

  // claims
  listClaims: (status?: string, pageSize = 100) =>
    api.get<Paged<InsuranceClaim>>('/insurance-claims', { params: clean({ status, pageSize }) }).then((r) => r.data),
  createClaim: (body: { invoiceId: string; provider: string; policyNumber: string; claimAmount: number; notes?: string }) =>
    api.post<InsuranceClaim>('/insurance-claims', body).then((r) => r.data),
  updateClaimStatus: (id: string, body: { status: ClaimStatus; rejectionReason?: string; notes?: string }) =>
    api.put<ClaimStatusResult>(`/insurance-claims/${id}/status`, body).then((r) => r.data),
  uploadClaimDocument: (id: string, file: File) => {
    const form = new FormData();
    form.append('file', file);
    return api.post<InsuranceClaim>(`/insurance-claims/${id}/documents`, form, { headers: { 'Content-Type': 'multipart/form-data' } }).then((r) => r.data);
  },

  // reports
  dashboard: (from: string, to: string) => api.get<BillingDashboard>('/billing/dashboard', { params: { from, to } }).then((r) => r.data),
  outstanding: (agingDays = 0) => api.get<OutstandingReport>('/reports/outstanding-payments', { params: { agingDays } }).then((r) => r.data),
  dailyRevenue: (date: string) => api.get<DailyRevenue>('/reports/daily-revenue', { params: { date } }).then((r) => r.data),

  // dynamic forms
  listForms: () => api.get<DynamicForm[]>('/dynamic-forms').then((r) => r.data),
  getForm: (formType: string) => api.get<DynamicForm>(`/dynamic-forms/${encodeURIComponent(formType)}`).then((r) => r.data),
  saveForm: (formType: string, body: { schema: JsonSchema; uiSchema?: unknown; validationRules?: unknown }) =>
    api.put<DynamicForm>(`/dynamic-forms/${encodeURIComponent(formType)}`, body).then((r) => r.data),
  deleteForm: (formType: string) => api.delete(`/dynamic-forms/${encodeURIComponent(formType)}`),
  validateForm: (formType: string, data: Record<string, unknown>) =>
    api.post<FormValidationResponse>(`/dynamic-forms/${encodeURIComponent(formType)}/validate`, data, { validateStatus: (s) => s === 200 || s === 400 })
      .then((r) => r.data),
  submitForm: (formType: string, entityId: string, data: Record<string, unknown>) =>
    api.post(`/dynamic-forms/${encodeURIComponent(formType)}/submit`, { entityId, data }).then((r) => r.data),

  // gateways
  listGateways: () => api.get<PaymentGateway[]>('/payment-gateways').then((r) => r.data),
  createGateway: (body: UpsertGatewayRequest) => api.post<PaymentGateway>('/payment-gateways', body).then((r) => r.data),
  updateGateway: (id: string, body: UpsertGatewayRequest) => api.put<PaymentGateway>(`/payment-gateways/${id}`, body).then((r) => r.data),
  deleteGateway: (id: string) => api.delete(`/payment-gateways/${id}`),
  testGateway: (id: string) => api.post<{ ok: boolean; simulated: boolean; message: string }>(`/payment-gateways/${id}/test`).then((r) => r.data),

  // commission
  listCommissionRules: () => api.get<CommissionRule[]>('/commission-rules').then((r) => r.data),
  saveCommissionRule: (id: string | null, body: Omit<CommissionRule, 'id'>) =>
    (id ? api.put<CommissionRule>(`/commission-rules/${id}`, body) : api.post<CommissionRule>('/commission-rules', body)).then((r) => r.data),
  deleteCommissionRule: (id: string) => api.delete(`/commission-rules/${id}`),
  calculateCommission: (dealAmount: number, roles?: string[]) =>
    api.post<CommissionSplit>('/commission-rules/calculate', { dealAmount, roles }).then((r) => r.data),

  // templates
  listTemplates: () => api.get<InvoiceTemplate[]>('/invoice-templates').then((r) => r.data),
  saveTemplate: (id: string | null, body: Omit<InvoiceTemplate, 'id' | 'updatedAt'>) =>
    (id ? api.put<InvoiceTemplate>(`/invoice-templates/${id}`, body) : api.post<InvoiceTemplate>('/invoice-templates', body)).then((r) => r.data),
  deleteTemplate: (id: string) => api.delete(`/invoice-templates/${id}`),

  // agent
  analyze: (body: { analysisType: string; dataRange?: { from: string; to: string }; thresholds?: Partial<ThresholdConfig>; dealAmount?: number }) =>
    api.post<BillingAnalysis>('/billing-agent/analyze', body).then((r) => r.data),
  agentTools: () =>
    api.get<{ tools: string[]; analysisTypes: Record<string, string[]>; defaultThresholds: ThresholdConfig }>('/billing-agent/tools').then((r) => r.data),
  workflows: (q: { kind?: string; status?: string; take?: number } = {}) =>
    api.get<BillingWorkflow[]>('/billing-agent/workflows', { params: clean(q) }).then((r) => r.data),
  approveWorkflow: (id: string) => api.post<{ message: string }>(`/billing-agent/workflows/${id}/approve`).then((r) => r.data),
  rejectWorkflow: (id: string, reason?: string) => api.post<{ message: string }>(`/billing-agent/workflows/${id}/reject`, { reason }).then((r) => r.data),

  // people - the tenant's customers, for pickers
  customers: (search?: string) =>
    api.get<CustomerOption[]>('/billing/customers', { params: clean({ search, take: 200 }) }).then((r) => r.data),
};

/** The server's `{ message }` for a failed call, or a fallback. */
export function errorMessage(err: unknown, fallback = 'Something went wrong.'): string {
  const e = err as { response?: { data?: { message?: string; errors?: Record<string, string[]> | { message: string }[]; title?: string } }; message?: string };
  const data = e?.response?.data;
  if (data?.message) return data.message;
  if (data?.errors && !Array.isArray(data.errors)) {
    const first = Object.values(data.errors)[0];
    if (first?.[0]) return first[0];
  }
  if (data?.title) return data.title;
  return fallback;
}
