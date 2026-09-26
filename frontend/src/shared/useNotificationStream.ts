import { useEffect, useRef, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { bookingApi } from '../api/bookingApi';
import { API_BASE_URL } from '../api/apiBaseUrl';
import type { RootState } from '../store/store';

/* Live notifications over Server-Sent Events.
 *
 * The bell used to poll, so "real time" meant "within the poll interval" -
 * long enough that a manager approving a plan on one screen would not see it
 * on another for several seconds. This holds one connection open and the
 * server pushes each notification the moment its row commits.
 *
 * `fetch` with a streaming body rather than the browser's `EventSource`,
 * because EventSource cannot send an Authorization header. The alternative is
 * putting the JWT in the query string, where it would end up in server logs
 * and browser history. The cost is that reconnection is ours to implement,
 * which is the loop below.
 *
 * SSE is a convenience layer, never the source of truth: every event only
 * invalidates the RTK Query cache, so the bell and the list are still served
 * by the same REST endpoints. A client that was disconnected sees whatever it
 * missed the moment it refetches. */

export type LiveNotification = {
  id: string;
  type: string;
  title: string;
  message: string;
  createdAt: string;
};

type Status = 'connecting' | 'live' | 'offline';

const RETRY_BASE_MS = 1_000;
const RETRY_MAX_MS = 30_000;

export function useNotificationStream(onNotification?: (n: LiveNotification) => void) {
  const dispatch = useDispatch();
  const token = useSelector((state: RootState) => state.auth.token);
  const isAuthenticated = useSelector((state: RootState) => state.auth.isAuthenticated);
  const [status, setStatus] = useState<Status>('connecting');

  // Held in a ref so a changing callback does not tear down the connection.
  const handlerRef = useRef(onNotification);
  handlerRef.current = onNotification;

  useEffect(() => {
    if (!isAuthenticated || !token) {
      setStatus('offline');
      return;
    }

    const controller = new AbortController();
    let retryTimer: number | undefined;
    let attempt = 0;
    let stopped = false;

    const connect = async () => {
      try {
        const response = await fetch(`${API_BASE_URL}/notifications/stream`, {
          headers: { Authorization: `Bearer ${token}`, Accept: 'text/event-stream' },
          signal: controller.signal,
        });

        // A 401 here means the session is gone; the shared baseQuery already
        // handles the redirect, so this just stops retrying into a wall.
        if (response.status === 401) {
          stopped = true;
          setStatus('offline');
          return;
        }
        if (!response.ok || !response.body) throw new Error(`stream: HTTP ${response.status}`);

        attempt = 0;
        setStatus('live');

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';

        // SSE frames are separated by a blank line. Chunks split anywhere, so
        // the tail of an incomplete frame stays in the buffer for next time.
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });

          let split = buffer.indexOf('\n\n');
          while (split !== -1) {
            handleFrame(buffer.slice(0, split));
            buffer = buffer.slice(split + 2);
            split = buffer.indexOf('\n\n');
          }
        }
        throw new Error('stream closed');
      } catch (error) {
        if (controller.signal.aborted || stopped) return;
        setStatus('offline');
        // Exponential backoff with jitter, so a backend restart does not bring
        // every open tab back in the same instant.
        attempt += 1;
        const wait = Math.min(RETRY_BASE_MS * 2 ** (attempt - 1), RETRY_MAX_MS);
        retryTimer = window.setTimeout(connect, wait + Math.random() * 500);
      }
    };

    const handleFrame = (frame: string) => {
      // ": keep-alive" - a comment frame proving the connection is alive.
      if (frame.startsWith(':')) return;

      let event = 'message';
      const dataLines: string[] = [];
      for (const line of frame.split('\n')) {
        if (line.startsWith('event:')) event = line.slice(6).trim();
        else if (line.startsWith('data:')) dataLines.push(line.slice(5).trim());
      }
      if (event !== 'notification' || dataLines.length === 0) return;

      let notification: LiveNotification;
      try {
        notification = JSON.parse(dataLines.join('\n'));
      } catch {
        return; // a malformed frame must not kill the connection
      }

      // The event carries enough to show a toast; the cache is refreshed from
      // the REST endpoints so the bell count and the list stay authoritative.
      dispatch(bookingApi.util.invalidateTags([
        { type: 'Notification', id: 'LIST' },
        { type: 'Notification', id: 'COUNT' },
      ]));
      handlerRef.current?.(notification);
    };

    void connect();

    return () => {
      stopped = true;
      controller.abort();
      if (retryTimer) window.clearTimeout(retryTimer);
    };
  }, [dispatch, token, isAuthenticated]);

  return status;
}
