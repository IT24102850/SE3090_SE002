import { render, screen, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { BookingEvent } from './types';

/* The timeline turns stored events into sentences a person can read. The
 * RTK Query hook is mocked so these test the rendering rules - including the
 * reschedule window format the server sends - not the network. */

const useGetBookingHistoryQuery = vi.fn();
vi.mock('../../api/bookingApi', () => ({
  useGetBookingHistoryQuery: (id: string) => useGetBookingHistoryQuery(id),
}));

const { default: BookingHistoryTimeline } = await import('./BookingHistoryTimeline');

function event(partial: Partial<BookingEvent>): BookingEvent {
  return {
    id: Math.random().toString(36).slice(2),
    type: 'StatusChanged',
    from: null,
    to: null,
    actorUserId: null,
    actorName: null,
    actorRole: null,
    reason: null,
    at: '2026-11-03T09:00:00Z',
    ...partial,
  };
}

const renderWith = (state: Record<string, unknown>) => {
  useGetBookingHistoryQuery.mockReturnValue(state);
  return render(<BookingHistoryTimeline bookingId="b1" />);
};

describe('BookingHistoryTimeline', () => {
  it('shows a loading state', () => {
    renderWith({ isLoading: true });

    expect(screen.getByText('Loading history…')).toBeInTheDocument();
  });

  it('shows an error state', () => {
    renderWith({ isError: true });

    expect(screen.getByRole('alert')).toHaveTextContent('History could not be loaded.');
  });

  it('shows an empty state rather than a bare list', () => {
    renderWith({ data: [] });

    expect(screen.getByText('No changes recorded yet.')).toBeInTheDocument();
  });

  it('names the person who made each change', () => {
    renderWith({
      data: [event({ type: 'Created', to: 'Pending', actorName: 'Ada Admin', actorRole: 'Admin' })],
    });

    const list = screen.getByRole('list', { name: 'Booking history' });
    expect(within(list).getByText('Booking created as Pending')).toBeInTheDocument();
    expect(within(list).getByText('by Ada Admin (Admin)')).toBeInTheDocument();
  });

  it('attributes a background change to System', () => {
    renderWith({
      data: [event({ type: 'StatusChanged', from: 'PendingPayment', to: 'Expired', actorRole: 'System' })],
    });

    expect(screen.getByText('by System')).toBeInTheDocument();
    expect(screen.getByText('Status changed from PendingPayment to Expired')).toBeInTheDocument();
  });

  it('reads a reschedule window as two readable times', () => {
    renderWith({
      data: [event({
        type: 'Rescheduled',
        from: '2026-11-03T09:00:00Z/2026-11-03T10:00:00Z',
        to: '2026-11-04T09:00:00Z/2026-11-04T10:00:00Z',
      })],
    });

    // The row begins with its own timestamp column, so this is not anchored.
    const text = screen.getByRole('listitem').textContent ?? '';
    expect(text).toMatch(/Moved from .+ – .+ to .+ – .+/);
    // The raw stored format must not leak into the UI.
    expect(text).not.toContain('/2026-11-03T10:00:00Z');
  });

  it('shows a cancellation reason when there is one', () => {
    renderWith({
      data: [event({ type: 'StatusChanged', from: 'Confirmed', to: 'Cancelled', reason: 'Customer called' })],
    });

    expect(screen.getByText('Reason: Customer called')).toBeInTheDocument();
  });

  it('renders the whole timeline in order', () => {
    renderWith({
      data: [
        event({ type: 'Created', to: 'Pending' }),
        event({ type: 'StatusChanged', from: 'Pending', to: 'Confirmed' }),
        event({ type: 'ResourceChanged', from: 'Room 1', to: 'Room 2' }),
      ],
    });

    const items = screen.getAllByRole('listitem').map((li) => li.textContent);
    expect(items).toHaveLength(3);
    expect(items[2]).toContain('Reassigned from Room 1 to Room 2');
  });
});
