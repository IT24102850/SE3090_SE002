import { configureStore } from '@reduxjs/toolkit';
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

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
