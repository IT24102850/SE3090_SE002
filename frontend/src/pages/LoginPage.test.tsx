import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import axios from 'axios';
import { Provider } from 'react-redux';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../store/authSlice';
import { ToastProvider } from '../shared/components/Toast';
import LoginPage from './LoginPage';

/* The sign-in form: client-side validation, the API call it makes, and the
 * three outcomes a user can see - signed in, wrong password, server down.
 * axios is mocked at the network boundary, so the thunk, the reducer and the
 * page all run for real. */

vi.mock('axios', async () => {
  const actual = await vi.importActual<typeof import('axios')>('axios');
  return { ...actual, default: { ...actual.default, post: vi.fn() } };
});
const post = vi.mocked(axios.post);

function renderLogin() {
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: { auth: { user: null, token: null, isAuthenticated: false, loading: false, error: null } },
  });
  render(
    <Provider store={store}>
      <ToastProvider>
        <MemoryRouter initialEntries={['/login']}>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/dashboard" element={<h1>Dashboard</h1>} />
          </Routes>
        </MemoryRouter>
      </ToastProvider>
    </Provider>,
  );
  return store;
}

function fillAndSubmit(email: string, password: string) {
  fireEvent.change(screen.getByLabelText('Email address'), { target: { value: email } });
  fireEvent.change(screen.getByLabelText('Password'), { target: { value: password } });
  fireEvent.click(screen.getByRole('button', { name: /sign in/i }));
}

describe('LoginPage', () => {
  beforeEach(() => {
    post.mockReset();
    localStorage.clear();
  });
  afterEach(() => localStorage.clear());

  it('blocks submission and explains why when the fields are empty', async () => {
    renderLogin();

    fillAndSubmit('', '');

    expect(await screen.findByText('Please enter both your email address and password.')).toBeInTheDocument();
    expect(post).not.toHaveBeenCalled();
  });

  it('posts trimmed credentials to /auth/login and opens the dashboard', async () => {
    post.mockResolvedValue({
      data: {
        accessToken: 'jwt-token',
        user: { id: 'u1', email: 'admin@test.local', fullName: 'Ada Admin', role: 'Admin', tenantId: 't1' },
      },
    });
    const store = renderLogin();

    fillAndSubmit('  admin@test.local  ', 'Secret123!');

    expect(await screen.findByRole('heading', { name: 'Dashboard' })).toBeInTheDocument();
    expect(post).toHaveBeenCalledWith(expect.stringMatching(/\/auth\/login$/), {
      email: 'admin@test.local',
      password: 'Secret123!',
    });
    expect(store.getState().auth.isAuthenticated).toBe(true);
    expect(localStorage.getItem('token')).toBe('jwt-token');
  });

  it("shows the server's message when the credentials are rejected", async () => {
    post.mockRejectedValue(
      Object.assign(new axios.AxiosError('Unauthorized'), {
        response: { status: 401, data: { message: 'Invalid email or password' } },
      }),
    );
    const store = renderLogin();

    fillAndSubmit('admin@test.local', 'wrong');

    await waitFor(() => expect(store.getState().auth.error).toBe('Invalid email or password'));
    expect((await screen.findAllByText('Invalid email or password')).length).toBeGreaterThan(0);
    expect(store.getState().auth.isAuthenticated).toBe(false);
    expect(localStorage.getItem('token')).toBeNull();
  });

  it('says the server is unreachable rather than blaming the password', async () => {
    post.mockRejectedValue(new axios.AxiosError('Network Error'));
    const store = renderLogin();

    fillAndSubmit('admin@test.local', 'Secret123!');

    await waitFor(() =>
      expect(store.getState().auth.error).toBe('Cannot reach the server. Check that the backend is running.'),
    );
  });
});
