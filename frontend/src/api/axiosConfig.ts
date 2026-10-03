import { API_BASE_URL } from './apiBaseUrl';
import axios, { type InternalAxiosRequestConfig } from 'axios';
import { expireSession, refreshSession } from './sessionRefresh';


const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const request = error.config as (InternalAxiosRequestConfig & { _retried?: boolean }) | undefined;
    if (error.response?.status === 401 && request && !request._retried) {
      // Expired access token: refresh once, then replay the request.
      const token = await refreshSession();
      if (token) {
        request._retried = true;
        request.headers.Authorization = `Bearer ${token}`;
        return api(request);
      }
      expireSession();
    }
    return Promise.reject(error);
  }
);

export default api;
