/* The website booking widget when a business has no scheduled departures.
 *
 * It used to price (and record) every booking with the alphabetically first
 * booking type: Mirissa JetLiner's whale-watching visitors saw Coastal Boat
 * Tour prices. Now the visitor picks the tour, or the host page names it. */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import axios from 'axios';
import EmbedBookingPage, { matchService } from './EmbedBookingPage';

vi.mock('axios');
const mocked = axios as unknown as { get: ReturnType<typeof vi.fn>; post: ReturnType<typeof vi.fn>; isAxiosError: () => boolean };

const catalog = {
  tenant: { id: 't1', name: 'Mirissa JetLiner', logoUrl: null, website: null, businessType: 'Tourism', subType: null, contactPhone: '0777728439' },
  bookingTypes: [
    { id: 'coastal', name: 'Coastal Boat Tours', description: '', defaultDurationMinutes: 150, requiresApproval: false, currency: 'LKR', pricing: { adult: 5000, child: 2500, infant: 0 } },
    { id: 'whale', name: 'Whale Watching', description: '', defaultDurationMinutes: 240, requiresApproval: false, currency: 'LKR', pricing: { adult: 7500, child: 4000, infant: 0 } },
    { id: 'pickup', name: 'Hotel Pickup & Drop-off', description: '', defaultDurationMinutes: 45, requiresApproval: false, category: 'addon', currency: 'LKR', pricing: { adult: 0, child: 0, infant: 0 } },
  ],
  departures: [],
  resources: [{ id: 'boat', name: 'Dawn Departure', category: 'Vehicle', description: '' }],
};

const renderAt = (query = '') =>
  render(
    <MemoryRouter initialEntries={[`/embed/book/t1${query}`]}>
      <Routes><Route path="/embed/book/:tenantId" element={<EmbedBookingPage />} /></Routes>
    </MemoryRouter>,
  );

beforeEach(() => {
  mocked.isAxiosError = () => false;
  mocked.get = vi.fn((url: string) =>
    url.endsWith('/catalog') ? Promise.resolve({ data: catalog }) : Promise.resolve({ data: { slots: [] } }));
});

describe('EmbedBookingPage without departures', () => {
  it('asks for a tour instead of pricing with the first booking type', async () => {
    renderAt();
    const tour = await screen.findByRole('combobox', { name: 'Tour' });
    expect(tour).toHaveValue('');
    expect(screen.queryByText(/LKR 5,000 each/)).not.toBeInTheDocument();

    await userEvent.selectOptions(tour, 'whale');
    expect(screen.getByText('LKR 7,500 each')).toBeInTheDocument();
    expect(screen.getByText('LKR 4,000 each')).toBeInTheDocument();
  });

  it('opens on the tour the host page names with data-service', async () => {
    renderAt('?service=Whale%20Watching');
    const tour = await screen.findByRole('combobox', { name: 'Tour' });
    await waitFor(() => expect(tour).toHaveValue('whale'));
    expect(screen.getByText('LKR 7,500 each')).toBeInTheDocument();
  });

  it('checks availability for the chosen tour', async () => {
    renderAt('?service=whale');
    await screen.findByRole('combobox', { name: 'Tour' });
    await userEvent.selectOptions(screen.getByRole('combobox', { name: /^(Choose|Service)$/ }), 'boat');
    const date = document.querySelector('input[type="date"]') as HTMLInputElement;
    await userEvent.type(date, '2030-01-15');
    await waitFor(() =>
      expect(mocked.get).toHaveBeenCalledWith(expect.stringContaining('/bookings/available-slots'),
        expect.objectContaining({ params: expect.objectContaining({ bookingTypeId: 'whale' }) })));
  });

  it('keeps add-ons such as hotel pickup out of the tour list', async () => {
    renderAt();
    const tour = await screen.findByRole('combobox', { name: 'Tour' });
    const labels = [...(tour as HTMLSelectElement).options].map((o) => o.value);
    expect(labels).toEqual(['', 'coastal', 'whale']);
  });

  it('opens on a tour named loosely by the host page (singular, any case)', async () => {
    renderAt('?service=coastal%20boat%20tour');
    const tour = await screen.findByRole('combobox', { name: 'Tour' });
    await waitFor(() => expect(tour).toHaveValue('coastal'));
  });
});

describe('matchService', () => {
  const types = catalog.bookingTypes;
  it('matches by id, exact name, or name ignoring case, punctuation and plural', () => {
    expect(matchService(types, 'whale')?.id).toBe('whale');
    expect(matchService(types, 'Whale Watching')?.id).toBe('whale');
    expect(matchService(types, 'Coastal Boat Tour')?.id).toBe('coastal');
    expect(matchService(types, 'snorkeling')).toBeUndefined();
    expect(matchService(types, '')).toBeUndefined();
  });
});
