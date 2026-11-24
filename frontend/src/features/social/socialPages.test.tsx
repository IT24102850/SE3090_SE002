import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import authReducer from '../../store/authSlice';
import { ToastProvider } from '../../shared/components/Toast';
import { ConfirmationProvider } from '../../shared/components/ConfirmationProvider';
import type { SocialAccount } from './socialApi';

vi.mock('./socialApi', async (orig) => {
  const actual = await orig<typeof import('./socialApi')>();
  return {
    ...actual,
    socialApi: {
      accounts: vi.fn(),
      status: vi.fn(),
      posts: vi.fn(),
      createPost: vi.fn(),
      conversations: vi.fn(),
      messages: vi.fn(),
      reply: vi.fn(),
      settings: vi.fn(),
      attribution: vi.fn(),
      campaigns: vi.fn(),
      events: vi.fn(),
    },
  };
});

import { socialApi } from './socialApi';
import SocialHubPage from './SocialHubPage';
import SocialPublisherPage from './SocialPublisherPage';
import SocialInboxPage from './SocialInboxPage';
import AdsPage from './AdsPage';

const api = socialApi as unknown as Record<string, ReturnType<typeof vi.fn>>;

const account = (over: Partial<SocialAccount> = {}): SocialAccount => ({
  id: 'a1', platform: 'Instagram', externalId: 'ig', parentExternalId: 'p', displayName: 'Mirissa Whales', handle: 'mirissa',
  avatarUrl: null, status: 'Connected', lastError: null, isSandbox: true, defaultPrivacy: null, tokenExpiresAt: null,
  lastSyncedAt: new Date().toISOString(), createdAt: new Date().toISOString(), canMessage: true, ...over,
});

function renderWith(ui: React.ReactNode, role: 'Admin' | 'Manager' | 'Staff' = 'Admin') {
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: {
      auth: { user: { id: 'u1', tenantId: 'tenant-1', role, fullName: 'A', email: 'a@b.com' }, token: 't', isAuthenticated: true } as any,
    },
  });
  return render(
    <Provider store={store}>
      <MemoryRouter>
        <ToastProvider>
          <ConfirmationProvider>{ui}</ConfirmationProvider>
        </ToastProvider>
      </MemoryRouter>
    </Provider>,
  );
}

beforeEach(() => {
  Object.values(api).forEach((fn) => fn.mockReset());
  api.accounts.mockResolvedValue([account(), account({ id: 'a2', platform: 'Facebook', displayName: 'Mirissa Page' })]);
  api.status.mockResolvedValue({
    meta: { configured: false, redirectUri: 'https://api/x', scopes: [] },
    tiktok: { configured: true, redirectUri: 'https://api/y', scopes: [] },
    webhook: { url: 'https://api/w', verifyTokenConfigured: false },
  });
});

describe('social pages render', () => {
  it('hub lists accounts and builds a tracked link for this tenant', async () => {
    renderWith(<SocialHubPage />);
    expect(await screen.findByText('Mirissa Whales')).toBeInTheDocument();
    expect(screen.getByText(/embed\/book\/tenant-1\?utm_source=instagram&utm_medium=social&utm_campaign=bio/)).toBeInTheDocument();
    // Meta is not configured on the server, so its connect button is disabled.
    expect(screen.getByRole('button', { name: 'Continue with Facebook' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Continue with TikTok' })).toBeEnabled();
  });

  it('publisher blocks an Instagram post without media before it reaches the API', async () => {
    api.posts.mockResolvedValue({ items: [], total: 0, page: 1, pageSize: 50 });
    renderWith(<SocialPublisherPage />);
    const pick = await screen.findByRole('button', { name: /Mirissa Whales/ });
    await userEvent.click(pick);
    await userEvent.type(screen.getByLabelText('Caption'), 'Whale season!');
    expect(await screen.findByText(/Instagram needs an image or a video/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Publish now' })).toBeDisabled();
    expect(api.createPost).not.toHaveBeenCalled();
  });

  it('inbox opens a thread and shows the closed reply window', async () => {
    const conv = {
      id: 'c1', accountId: 'a2', platform: 'Facebook', accountName: 'Mirissa Page', isSandbox: false, participantId: 'p',
      participantName: 'Amaya Perera', lastMessagePreview: 'Hi there', lastMessageAt: new Date().toISOString(),
      lastInboundAt: new Date(Date.now() - 30 * 3600_000).toISOString(), unreadCount: 1, isArchived: false, linkedBookingId: null,
      canReply: false, replyWindowEndsAt: new Date(Date.now() - 6 * 3600_000).toISOString(),
    };
    api.conversations.mockResolvedValue([conv]);
    api.messages.mockResolvedValue({ conversation: conv, messages: [{ id: 'm1', direction: 'Inbound', text: 'Hi there', attachmentUrl: null, sentAt: conv.lastMessageAt, sentByUserId: null, error: null }] });
    renderWith(<SocialInboxPage />, 'Staff');
    await userEvent.click(await screen.findByRole('button', { name: /Amaya Perera/ }));
    expect(await screen.findByText(/only lets businesses reply within 24 hours/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Send' })).toBeDisabled();
  });

  it('ads page renders performance with empty data', async () => {
    api.attribution.mockResolvedValue({ from: '', to: '', totalBookings: 0, totalRevenue: 0, socialBookings: 0, socialRevenue: 0, channels: [], daily: [] });
    api.campaigns.mockResolvedValue({ from: '', to: '', totalSpend: 0, attributedBookings: 0, attributedRevenue: 0, blendedRoas: null, campaigns: [], warnings: ['No ad account is connected.'] });
    renderWith(<AdsPage />, 'Manager');
    await waitFor(() => expect(screen.getByText('No ad account is connected.')).toBeInTheDocument());
    expect(screen.getByText(/No bookings in this period/)).toBeInTheDocument();
  });
});
