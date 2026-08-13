import { configureStore } from '@reduxjs/toolkit';
import authReducer from './authSlice';
import { bookingApi } from '../api/bookingApi';

export const store = configureStore({
  reducer: {
    auth: authReducer,
    [bookingApi.reducerPath]: bookingApi.reducer,
  },
  middleware: (getDefaultMiddleware) => getDefaultMiddleware().concat(bookingApi.middleware),
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
