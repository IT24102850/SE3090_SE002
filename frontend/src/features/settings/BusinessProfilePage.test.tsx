// Written against Vitest + React Testing Library conventions but UNVERIFIED:
// npm registry access was blocked (403 Forbidden) in the environment these
// were authored in, so `npm install` for vitest/@testing-library/* could
// never actually run here, and neither could this file. Run once registry
// access is restored.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import authReducer from '../../store/authSlice';
import { bookingApi } from '../../api/bookingApi';
import { ToastProvider } from '../../shared/components/Toast';
import BusinessProfilePage from './BusinessProfilePage';

const TENANT_ID = 'tenant-1';

function renderPage() {
  const store = configureStore({
    reducer: { auth: authReducer, [bookingApi.reducerPath]: bookingApi.reducer },
    middleware: (getDefault) => getDefault().concat(bookingApi.middleware),
    preloadedState: {
      auth: {
        user: { id: 'user-1', tenantId: TENANT_ID, role: 'Admin', fullName: 'Test Admin', email: 'a@b.com' },
        token: 'fake-token',
        isAuthenticated: true,
      } as any,
    },
  });
  return render(
    <Provider store={store}>
      <ToastProvider>
        <BusinessProfilePage />
      </ToastProvider>
    </Provider>,
  );
}

const baseProfile = {
  tenantId: TENANT_ID,
  name: 'Weligama Bay Dive Center',
  businessType: 'Tourism',
  logoUrl: 'https://example.com/logo.jpg',
  coverImageUrl: null,
  galleryImageUrls: [],
  description: '',
  shortTagline: '',
  amenities: [],
  contactPhone: '',
  contactEmail: '',
  website: '',
  socialLinks: {},
  businessHours: [],
  averageRating: null,
  reviewCount: 0,
  address: null,
};

describe('BusinessProfilePage', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const url = input.toString();
        if (url.includes('/profile') && !url.includes('/media')) {
          return new Response(JSON.stringify(baseProfile), { status: 200 });
        }
        return new Response(JSON.stringify({}), { status: 200 });
      }),
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('shows upload progress and a failed upload does not clear the already-saved logo', async () => {
    (global.fetch as any).mockImplementation(async (input: RequestInfo | URL) => {
      const url = input.toString();
      if (url.includes('/media/upload')) {
        return new Response(JSON.stringify({ message: 'Image upload failed: network error' }), { status: 502 });
      }
      if (url.includes('/profile')) {
        return new Response(JSON.stringify(baseProfile), { status: 200 });
      }
      return new Response(JSON.stringify({}), { status: 200 });
    });

    renderPage();
    await screen.findByText('Business Profile');

    // The already-saved logo must be visible before we even try a failed upload.
    const logoImg = (await screen.findByAltText('Logo')) as HTMLImageElement;
    expect(logoImg.src).toBe('https://example.com/logo.jpg');

    const logoSection = logoImg.closest('div')!.parentElement!;
    const fileInput = within(logoSection).getByLabelText(/replace|upload/i, { selector: 'input' }) as HTMLInputElement;
    const file = new File(['x'], 'new-logo.jpg', { type: 'image/jpeg' });

    await userEvent.upload(fileInput, file);

    // Progress indicator shown while the upload is in flight.
    expect(within(logoSection).queryByTestId('upload-spinner')).toBeTruthy();

    await waitFor(() => expect(screen.getByText(/could not upload image/i)).toBeInTheDocument());

    // The original, already-saved logo must still be there - not cleared by the failed upload.
    const logoImgAfter = screen.getByAltText('Logo') as HTMLImageElement;
    expect(logoImgAfter.src).toBe('https://example.com/logo.jpg');
  });

  it('blocks saving business hours when openTime is after closeTime', async () => {
    renderPage();
    await screen.findByText('Business hours');

    const mondayRow = screen.getByText('Monday').closest('div')!;
    const timeInputs = within(mondayRow).getAllByDisplayValue(/\d{2}:\d{2}/) as HTMLInputElement[];
    fireEvent.change(timeInputs[0], { target: { value: '18:00' } }); // open
    fireEvent.change(timeInputs[1], { target: { value: '08:00' } }); // close, before open

    expect(screen.getByText(/open time must be before close time/i)).toBeInTheDocument();

    const saveButton = screen.getByRole('button', { name: /save changes/i });
    fireEvent.click(saveButton);

    // The invalid state must be caught client-side and surfaced, not silently sent.
    await waitFor(() => expect(screen.getByText(/open time must be before close time/i)).toBeInTheDocument());
  });

  it('amenities chip input rejects a duplicate entry', async () => {
    renderPage();
    const input = await screen.findByPlaceholderText(/type an amenity/i);

    await userEvent.type(input, 'Free WiFi{enter}');
    expect(screen.getAllByText('Free WiFi')).toHaveLength(1);

    await userEvent.type(input, 'Free WiFi{enter}');
    // Still exactly one chip - the duplicate was silently rejected, not added twice.
    expect(screen.getAllByText('Free WiFi')).toHaveLength(1);

    await userEvent.type(input, '  free wifi  {enter}'); // case/whitespace variant
    expect(screen.getAllByText(/free wifi/i)).toHaveLength(1);
  });
});
