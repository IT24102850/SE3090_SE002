import { configureStore } from '@reduxjs/toolkit';
import { setupListeners } from '@reduxjs/toolkit/query';
import authReducer from './authSlice';
import { bookingApi } from '../api/bookingApi';
import { platformApi } from '../features/platform/platformApi';

export const store = configureStore({
  reducer: {
    auth: authReducer,
    [bookingApi.reducerPath]: bookingApi.reducer,
    [platformApi.reducerPath]: platformApi.reducer,
  },
  middleware: (getDefaultMiddleware) => getDefaultMiddleware().concat(bookingApi.middleware, platformApi.middleware),
});

/* Wires the browser's focus and online events into RTK Query, so an
 * endpoint that opts in with refetchOnFocus/refetchOnReconnect - the
 * notification bell, the live dashboard panels - refreshes the moment the
 * tab is looked at again instead of showing whatever was true when it was
 * last left. Endpoints that do not opt in are unaffected. */
setupListeners(store.dispatch);

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
