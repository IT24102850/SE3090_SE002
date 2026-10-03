import { configureStore } from '@reduxjs/toolkit';
import { render, screen, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { bookingApi } from '../../api/bookingApi';
import authReducer from '../../store/authSlice';
import { ToastProvider } from '../../shared/components/Toast';
import DashboardRouter from './DashboardRouter';
import WhaleWatchingDashboard from './WhaleWatchingDashboard';
import { getSubtypeConfig } from './subtypes/subtypeRegistry';

/* Renders the real components against a stubbed fetch, so the assertions are
 * about what an operator actually sees, not about mocked internals. */

const TENANT_ID = '11111111-1111-1111-1111-111111111111';

const DEPARTURE = {
  id: 'dep-1',
  resourceId: 'res-1',
  vesselName: 'Sea Guardian',
  bookingTypeId: 'bt-1',
  bookingTypeName: 'Whale Watching Tour',
  scheduledDeparture: `${new Date().toISOString().slice(0, 10)}T06:30:00Z`,
  scheduledReturn: `${new Date().toISOString().slice(0, 10)}T10:30:00Z`,
  durationMinutes: 240,
  status: 'Scheduled',
  captainUserId: null,
  crew: JSON.stringify([{ name: 'Capt. Sunil Fernando', role: 'Captain' }]),
  safetyChecklist: null,
  safetyChecklistComplete: false,
  capacity: 120,
  paxBooked: 42,
  seatsRemaining: 78,
  occupancyPercent: 35,
  nearCapacity: false,
  ticketMix: { Adult: 34, Child: 8 },
  bookingCount: 14,
  checkedInCount: 3,
  waiverCompletionPercent: 64.3,
  revenue: 287000,
  sightingCount: 0,
  cancellationReason: null,
  latestWeather: null,
};

const KPIS = {
  asOf: new Date().toISOString(),
  seasonStart: new Date().toISOString(),
  departuresToday: 4,
  departuresTodayByStatus: { Scheduled: 4 },
  paxBookedToday: 42,
  capacityToday: 400,
  occupancyTodayPercent: 10.5,
  sightingSuccessRate: 78.6,
  departuresSailedSeasonToDate: 56,
  departuresWithSightingSeasonToDate: 44,
  revenueToday: 287000,
  weatherCancelledThisMonth: 2,
  waiverCompletionPercent: 64.3,
  checkedInToday: 3,
  forwardDays: 7,
  nextDaysOccupancyPercent: 31.2,
  nextDaysPax: 312,
  nextDaysCapacity: 1000,
};

/** Routes a request path to a canned payload; anything unrouted returns an
 *  empty object so an unrelated query cannot fail the test. */
function stubFetch(overrides: Record<string, unknown> = {}) {
  return vi.fn(async (input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input.toString();
    const routes: Record<string, unknown> = {
      '/departures/board': { from: '', to: '', today: [DEPARTURE], upcoming: [DEPARTURE] },
      '/reports/excursions/kpis': KPIS,
      '/departures/weather': { latest: null, items: [] },
      '/departures/safety': { vessels: [], sharedEquipment: [], expiredCount: 0, expiringSoonCount: 0 },
      '/sightings/analytics': {
        from: '', to: '', departuresSailed: 56, departuresWithSighting: 44,
        successRate: 78.6, totalSightings: 61, totalIndividuals: 210,
        speciesFrequency: [{ species: 'BlueWhale', sightings: 22, individuals: 30 }],
        monthly: [],
      },
      '/sightings/vocabulary': { species: ['BlueWhale'], behaviours: ['Breaching'] },
      ...overrides,
    };

    const match = Object.keys(routes).find((key) => url.includes(key));
    return new Response(JSON.stringify(match ? routes[match] : {}), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  });
}

function renderWith(ui: React.ReactElement) {
  const store = configureStore({
    reducer: { auth: authReducer, [bookingApi.reducerPath]: bookingApi.reducer },
    middleware: (gdm) => gdm().concat(bookingApi.middleware),
    preloadedState: {
      auth: {
        user: {
          id: 'u-1', email: 'ops@example.com', fullName: 'Ops',
          role: 'Admin' as const, tenantId: TENANT_ID,
        },
        token: 'test-token',
        isAuthenticated: true,
        loading: false,
        error: null,
      },
    },
  });

  return render(
    <Provider store={store}>
      <ToastProvider>
        <MemoryRouter>{ui}</MemoryRouter>
      </ToastProvider>
    </Provider>,
  );
}

beforeEach(() => {
  localStorage.setItem('token', 'test-token');
  vi.stubGlobal('fetch', stubFetch());
});

afterEach(() => {
  vi.unstubAllGlobals();
  localStorage.clear();
});

describe('WhaleWatchingDashboard', () => {
  const config = getSubtypeConfig('whaleWatching');

  it('leads with the departure board, not a calendar', async () => {
    renderWith(<WhaleWatchingDashboard config={config} tenant={{
      id: TENANT_ID, name: 'Mirissa Jetliner', businessType: 'Tourism',
      subType: 'Whale / dolphin watching', isActive: true,
      rescheduleCutoffHours: 4, cancellationCutoffHours: 2,
    }} />);

    expect(await screen.findByText('Mirissa Jetliner')).toBeInTheDocument();
    expect(await screen.findByText('Sea Guardian')).toBeInTheDocument();
    expect(screen.getByText(/Manage today's departures/i)).toBeInTheDocument();
  });

  it('shows pax against licensed capacity and the ticket mix', async () => {
    renderWith(<WhaleWatchingDashboard config={config} />);

    expect(await screen.findByText(/42 \/ 120 pax/)).toBeInTheDocument();
    expect(screen.getByText(/78 seats left/)).toBeInTheDocument();
    expect(screen.getByText(/34 adult.*8 child/)).toBeInTheDocument();
  });

  it('renders the whale-watching KPI cards', async () => {
    renderWith(<WhaleWatchingDashboard config={config} />);

    expect(await screen.findByText('Departures today')).toBeInTheDocument();
    expect(screen.getByText('Sighting success')).toBeInTheDocument();
    expect(screen.getByText('Weather-cancelled')).toBeInTheDocument();
    expect(screen.getByText('Waiver completion')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText('78.6%')).toBeInTheDocument());
    // Pax reads against the capacity it is measured on.
    expect(screen.getByText('42 / 400')).toBeInTheDocument();
  });

  it('offers the per-departure operational actions', async () => {
    renderWith(<WhaleWatchingDashboard config={config} />);

    expect(await screen.findByText('Open manifest')).toBeInTheDocument();
    expect(screen.getByText('Start boarding')).toBeInTheDocument();
    expect(screen.getByText('Log sighting')).toBeInTheDocument();
    expect(screen.getByText('Cancel — weather')).toBeInTheDocument();
  });

  it('flags a departure whose safety checklist is incomplete', async () => {
    renderWith(<WhaleWatchingDashboard config={config} />);

    expect(await screen.findByText(/Safety checklist ⚠/)).toBeInTheDocument();
  });

  it('renders the weather console and the sightings analytics', async () => {
    renderWith(<WhaleWatchingDashboard config={config} />);

    expect(await screen.findByText('Weather & sea state')).toBeInTheDocument();
    expect(await screen.findByText('Sightings')).toBeInTheDocument();
    expect(await screen.findByText(/44 of 56 departures that sailed/)).toBeInTheDocument();
  });
});

describe('DashboardRouter', () => {
  it('renders the departure board for a whale-watching tenant', async () => {
    vi.stubGlobal('fetch', stubFetch({
      '/tenant?': {
        id: TENANT_ID, name: 'Mirissa Jetliner', businessType: 'Tourism',
        subType: 'Whale / dolphin watching', isActive: true,
        rescheduleCutoffHours: 4, cancellationCutoffHours: 2,
      },
    }));

    renderWith(<DashboardRouter />);

    expect(await screen.findByText('Sea Guardian')).toBeInTheDocument();
    expect(screen.getByText('Open manifest')).toBeInTheDocument();
  });

  it('renders the unchanged generic dashboard for a tenant with no sub-type', async () => {
    vi.stubGlobal('fetch', stubFetch({
      '/tenant?': {
        id: TENANT_ID, name: 'City Dental', businessType: 'Clinic',
        subType: null, isActive: true,
        rescheduleCutoffHours: 2, cancellationCutoffHours: 1,
      },
      '/bookings': { items: [], total: 0, page: 1, pageSize: 20, totalPages: 0 },
      '/resources': { items: [], total: 0, page: 1, pageSize: 20, totalPages: 0 },
    }));

    renderWith(<DashboardRouter />);

    // The generic dashboard's month calendar, and none of the departure ops.
    expect(await screen.findByText('City Dental')).toBeInTheDocument();
    expect(screen.queryByText('Open manifest')).not.toBeInTheDocument();
    expect(screen.queryByText('Weather & sea state')).not.toBeInTheDocument();
  });

  it('renders the generic dashboard for an unrecognised sub-type', async () => {
    vi.stubGlobal('fetch', stubFetch({
      '/tenant?': {
        id: TENANT_ID, name: 'Something New', businessType: 'Tourism',
        subType: 'Hot air ballooning', isActive: true,
        rescheduleCutoffHours: 2, cancellationCutoffHours: 1,
      },
      '/bookings': { items: [], total: 0, page: 1, pageSize: 20, totalPages: 0 },
      '/resources': { items: [], total: 0, page: 1, pageSize: 20, totalPages: 0 },
    }));

    renderWith(<DashboardRouter />);

    expect(await screen.findByText('Something New')).toBeInTheDocument();
    expect(screen.queryByText('Open manifest')).not.toBeInTheDocument();
  });
});
