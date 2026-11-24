import api from '../../api/axiosConfig';

/* Typed client for the marketing & social API (backend Controllers/Marketing).
 * Plain axios over the shared instance (JWT + refresh); the tenant always
 * comes from the token. */

export type Platform = 'Facebook' | 'Instagram' | 'TikTok';

export interface SocialAccount {
  id: string;
  platform: Platform;
  externalId: string;
  parentExternalId: string | null;
  displayName: string;
  handle: string | null;
  avatarUrl: string | null;
  status: 'Connected' | 'NeedsReconnect' | 'Disconnected';
  lastError: string | null;
  isSandbox: boolean;
  defaultPrivacy: string | null;
  tokenExpiresAt: string | null;
  lastSyncedAt: string | null;
  createdAt: string;
  canMessage: boolean;
}

export interface SocialStatus {
  meta: { configured: boolean; redirectUri: string; scopes: string[] };
  tiktok: { configured: boolean; redirectUri: string; scopes: string[] };
  webhook: { url: string; verifyTokenConfigured: boolean };
}

export type MediaType = 'None' | 'Image' | 'Video';
export type PostStatus = 'Draft' | 'Scheduled' | 'Publishing' | 'Published' | 'PartiallyPublished' | 'Failed' | 'Cancelled';
export type TargetStatus = 'Pending' | 'Processing' | 'Published' | 'Simulated' | 'Failed' | 'Cancelled';

export interface PostTarget {
  id: string;
  accountId: string;
  platform: Platform;
  accountName: string;
  isSandbox: boolean;
  status: TargetStatus;
  permalinkUrl: string | null;
  error: string | null;
  attempts: number;
  publishedAt: string | null;
  nextAttemptAt: string | null;
}

export interface SocialPost {
  id: string;
  caption: string;
  mediaType: MediaType;
  mediaUrl: string | null;
  linkUrl: string | null;
  scheduledAt: string | null;
  status: PostStatus;
  createdAt: string;
  updatedAt: string;
  editable: boolean;
  targets: PostTarget[];
}

export interface UpsertPost {
  caption: string;
  mediaType: MediaType;
  mediaUrl: string | null;
  linkUrl: string | null;
  scheduledAt: string | null;
  accountIds: string[];
  asDraft: boolean;
}

export interface Conversation {
  id: string;
  accountId: string;
  platform: Platform;
  accountName: string;
  isSandbox: boolean;
  participantId: string;
  participantName: string | null;
  lastMessagePreview: string | null;
  lastMessageAt: string;
  lastInboundAt: string | null;
  unreadCount: number;
  isArchived: boolean;
  linkedBookingId: string | null;
  canReply: boolean;
  replyWindowEndsAt: string | null;
}

export interface InboxMessage {
  id: string;
  direction: 'Inbound' | 'Outbound';
  text: string;
  attachmentUrl: string | null;
  sentAt: string;
  sentByUserId: string | null;
  error: string | null;
}

export interface MarketingSettings {
  conversionTrackingEnabled: boolean;
  metaPixelId: string | null;
  hasMetaCapiToken: boolean;
  metaCapiTokenHint: string | null;
  metaTestEventCode: string | null;
  metaAdAccountId: string | null;
  hasMetaAdsToken: boolean;
  metaAdsTokenExpiresAt: string | null;
  tikTokPixelCode: string | null;
  hasTikTokEventsToken: boolean;
  tikTokEventsTokenHint: string | null;
  tikTokTestEventCode: string | null;
  tikTokAdvertiserId: string | null;
  hasTikTokAdsToken: boolean;
  metaTrackingActive: boolean;
  tikTokTrackingActive: boolean;
}

/* For tokens: undefined = leave as is, '' = clear, value = replace. */
export interface UpdateMarketingSettings {
  conversionTrackingEnabled?: boolean;
  metaPixelId?: string;
  metaCapiToken?: string;
  metaTestEventCode?: string;
  metaAdAccountId?: string;
  metaAdsToken?: string;
  tikTokPixelCode?: string;
  tikTokEventsToken?: string;
  tikTokTestEventCode?: string;
  tikTokAdvertiserId?: string;
  tikTokAdsToken?: string;
}

export interface ConversionEventRow {
  id: string;
  bookingId: string;
  platform: 'Facebook' | 'TikTok';
  eventName: string;
  platformEventName: string;
  status: 'Pending' | 'Sent' | 'Failed' | 'Skipped';
  eventTime: string;
  value: number | null;
  currency: string | null;
  attempts: number;
  sentAt: string | null;
  nextAttemptAt: string | null;
  lastError: string | null;
  isTest: boolean;
  createdAt: string;
}

export interface ConversionEventPage {
  summary: { platform: string; status: string; count: number }[];
  total: number;
  page: number;
  pageSize: number;
  items: ConversionEventRow[];
}

export interface ChannelRow { channel: string; bookings: number; converted: number; lost: number; revenue: number; revenueShare: number }
export interface AttributionReport {
  from: string; to: string;
  totalBookings: number; totalRevenue: number;
  socialBookings: number; socialRevenue: number;
  channels: ChannelRow[];
  daily: { date: string; channel: string; bookings: number }[];
}

export interface CampaignRow {
  platform: string; campaignId: string | null; campaign: string;
  spend: number | null; impressions: number | null; clicks: number | null;
  ctr: number | null; cpc: number | null;
  bookings: number; converted: number; revenue: number;
  costPerBooking: number | null; roas: number | null;
  matchedToAdAccount: boolean;
}
export interface CampaignReport {
  from: string; to: string;
  totalSpend: number; attributedBookings: number; attributedRevenue: number; blendedRoas: number | null;
  campaigns: CampaignRow[];
  warnings: string[];
}

const range = (from?: string, to?: string) => ({ params: { from: from || undefined, to: to || undefined } });

export const socialApi = {
  // Accounts
  status: () => api.get<SocialStatus>('/social/status').then((r) => r.data),
  accounts: () => api.get<SocialAccount[]>('/social/accounts').then((r) => r.data),
  connect: (provider: 'meta' | 'tiktok') =>
    api.post<{ url: string }>(`/social/accounts/connect/${provider}`, { returnOrigin: window.location.origin }).then((r) => r.data),
  addSandbox: (platform: Platform, displayName?: string) =>
    api.post<SocialAccount>('/social/accounts/sandbox', { platform, displayName }).then((r) => r.data),
  updateAccount: (id: string, body: { defaultPrivacy?: string }) =>
    api.patch<SocialAccount>(`/social/accounts/${id}`, body).then((r) => r.data),
  refreshAccount: (id: string) => api.post<SocialAccount>(`/social/accounts/${id}/refresh`).then((r) => r.data),
  disconnect: (id: string) => api.delete(`/social/accounts/${id}`),

  // Posts
  posts: (params: { status?: string; page?: number; pageSize?: number } = {}) =>
    api.get<{ items: SocialPost[]; total: number; page: number; pageSize: number }>('/social/posts', { params }).then((r) => r.data),
  createPost: (body: UpsertPost) => api.post<SocialPost>('/social/posts', body).then((r) => r.data),
  updatePost: (id: string, body: UpsertPost) => api.put<SocialPost>(`/social/posts/${id}`, body).then((r) => r.data),
  cancelPost: (id: string) => api.post<SocialPost>(`/social/posts/${id}/cancel`).then((r) => r.data),
  retryPost: (id: string) => api.post<SocialPost>(`/social/posts/${id}/retry`).then((r) => r.data),
  deletePost: (id: string) => api.delete(`/social/posts/${id}`),
  uploadImage: (file: File) => {
    const form = new FormData();
    form.append('file', file);
    form.append('purpose', 'social');
    return api.post<{ url: string }>('/media/upload', form, { headers: { 'Content-Type': 'multipart/form-data' } }).then((r) => r.data);
  },

  // Inbox
  conversations: (params: { accountId?: string; archived?: boolean; search?: string } = {}) =>
    api.get<Conversation[]>('/social/inbox/conversations', { params }).then((r) => r.data),
  unreadCount: () => api.get<{ count: number }>('/social/inbox/unread-count').then((r) => r.data.count),
  messages: (id: string) =>
    api.get<{ conversation: Conversation; messages: InboxMessage[] }>(`/social/inbox/conversations/${id}/messages`).then((r) => r.data),
  reply: (id: string, text: string) => api.post<InboxMessage>(`/social/inbox/conversations/${id}/reply`, { text }).then((r) => r.data),
  archive: (id: string, archived: boolean) => api.post(`/social/inbox/conversations/${id}/archive`, { archived }),
  simulateIncoming: (accountId: string, participantName: string, text: string) =>
    api.post<{ conversationId: string }>('/social/inbox/sandbox/incoming', { accountId, participantName, text }).then((r) => r.data),

  // Ads
  settings: () => api.get<MarketingSettings>('/marketing/settings').then((r) => r.data),
  updateSettings: (body: UpdateMarketingSettings) => api.put<MarketingSettings>('/marketing/settings', body).then((r) => r.data),
  metaAdAccounts: () => api.get<{ id: string; name: string; currency: string | null }[]>('/marketing/meta/ad-accounts').then((r) => r.data),
  testEvent: (platform: 'meta' | 'tiktok') =>
    api.post<{ ok: boolean; message: string }>(`/marketing/settings/test/${platform}`).then((r) => r.data),
  events: (params: { status?: string; platform?: string; page?: number } = {}) =>
    api.get<ConversionEventPage>('/marketing/events', { params }).then((r) => r.data),
  retryEvent: (id: string) => api.post(`/marketing/events/${id}/retry`),
  attribution: (from?: string, to?: string) => api.get<AttributionReport>('/marketing/attribution', range(from, to)).then((r) => r.data),
  campaigns: (from?: string, to?: string) => api.get<CampaignReport>('/marketing/campaigns', range(from, to)).then((r) => r.data),
};
