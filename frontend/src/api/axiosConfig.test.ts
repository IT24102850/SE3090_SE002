import type { AxiosAdapter, InternalAxiosRequestConfig } from 'axios';
import { AxiosError } from 'axios';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import api from './axiosConfig';

/* The shared API client every screen uses to reach ASP.NET Core. The adapter
 * is replaced so each test sees exactly the request that would have gone on
 * the wire, and can answer it with any status. */

let lastRequest: InternalAxiosRequestConfig | undefined;

function respondWith(status: number, data: unknown = {}): AxiosAdapter {
  return async (config) => {
    lastRequest = config;
    const response = { data, status, statusText: String(status), headers: {}, config };
    if (status >= 400) {
      throw new AxiosError(`Request failed with status code ${status}`, undefined, config, undefined, response);
    }
    return response;
  };
}

describe('axiosConfig API client', () => {
  const originalLocation = window.location;

  beforeEach(() => {
    lastRequest = undefined;
    localStorage.clear();
    Object.defineProperty(window, 'location', { configurable: true, value: { ...originalLocation, href: '/' } });
  });

  afterEach(() => {
    Object.defineProperty(window, 'location', { configurable: true, value: originalLocation });
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it('sends JSON to the configured API base URL', async () => {
    api.defaults.adapter = respondWith(200, [{ id: 'b1' }]);

    const response = await api.get('/bookings');

    expect(response.data).toEqual([{ id: 'b1' }]);
    expect(lastRequest?.baseURL).toMatch(/\/api$/);
    expect(lastRequest?.url).toBe('/bookings');
    expect(lastRequest?.headers['Content-Type']).toBe('application/json');
  });

  it('attaches the stored JWT as a bearer token', async () => {
    localStorage.setItem('token', 'jwt-123');
    api.defaults.adapter = respondWith(200);

    await api.get('/auth/me');

    expect(lastRequest?.headers.Authorization).toBe('Bearer jwt-123');
  });

  it('sends no Authorization header when signed out', async () => {
    api.defaults.adapter = respondWith(200);

    await api.get('/tenants/public');

    expect(lastRequest?.headers.Authorization).toBeUndefined();
  });

  it('signs the user out and returns to /login on a 401', async () => {
    localStorage.setItem('token', 'expired');
    localStorage.setItem('user', '{"id":"u1"}');
    api.defaults.adapter = respondWith(401, { message: 'Token expired' });

    await expect(api.get('/bookings')).rejects.toMatchObject({ response: { status: 401 } });

    expect(localStorage.getItem('token')).toBeNull();
    expect(localStorage.getItem('user')).toBeNull();
    expect(window.location.href).toBe('/login');
  });

  it('passes other errors through to the caller with the session intact', async () => {
    localStorage.setItem('token', 'still-valid');
    api.defaults.adapter = respondWith(403, { title: 'Forbidden' });

    await expect(api.post('/agent/workflow/x/approve')).rejects.toMatchObject({ response: { status: 403 } });

    expect(localStorage.getItem('token')).toBe('still-valid');
    expect(window.location.href).toBe('/');
  });
});
