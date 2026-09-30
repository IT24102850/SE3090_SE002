import { configureStore } from '@reduxjs/toolkit';
import { render, screen } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import authReducer, { type User } from '../store/authSlice';
import ProtectedRoute from './ProtectedRoute';

/* The route guard every protected screen sits behind: signed-out visitors go
 * to /login, a signed-in user without the role goes to /unauthorized, and
 * only the right role sees the page. */

function renderAt(user: User | null, allowedRoles?: string[]) {
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: {
      auth: { user, token: user ? 'token' : null, isAuthenticated: !!user, loading: false, error: null },
    },
  });
  return render(
    <Provider store={store}>
      <MemoryRouter initialEntries={['/admin']}>
        <Routes>
          <Route
            path="/admin"
            element={
              <ProtectedRoute allowedRoles={allowedRoles}>
                <h1>Admin area</h1>
              </ProtectedRoute>
            }
          />
          <Route path="/login" element={<h1>Login page</h1>} />
          <Route path="/unauthorized" element={<h1>Not allowed</h1>} />
        </Routes>
      </MemoryRouter>
    </Provider>,
  );
}

const userWithRole = (role: User['role']): User => ({
  id: 'u1', email: `${role}@test.local`, fullName: `Test ${role}`, role, tenantId: 't1',
});

describe('ProtectedRoute', () => {
  it('redirects a signed-out visitor to the login page', () => {
    renderAt(null, ['Admin']);

    expect(screen.getByRole('heading', { name: 'Login page' })).toBeInTheDocument();
    expect(screen.queryByText('Admin area')).not.toBeInTheDocument();
  });

  it('sends a signed-in user without the role to /unauthorized', () => {
    renderAt(userWithRole('Customer'), ['Admin', 'Manager']);

    expect(screen.getByRole('heading', { name: 'Not allowed' })).toBeInTheDocument();
    expect(screen.queryByText('Admin area')).not.toBeInTheDocument();
  });

  it('renders the page for a user holding an allowed role', () => {
    renderAt(userWithRole('Manager'), ['Admin', 'Manager']);

    expect(screen.getByRole('heading', { name: 'Admin area' })).toBeInTheDocument();
  });

  it('lets any signed-in user through when no roles are required', () => {
    renderAt(userWithRole('Staff'));

    expect(screen.getByRole('heading', { name: 'Admin area' })).toBeInTheDocument();
  });
});
