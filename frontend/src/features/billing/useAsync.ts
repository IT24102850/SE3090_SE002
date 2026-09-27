import { useCallback, useEffect, useRef, useState } from 'react';
import { errorMessage } from './billingApi';

/** Loads data on mount and whenever `deps` change; `reload()` refetches.
 *  A stale response (deps changed mid-flight) is dropped. */
export function useAsync<T>(load: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const generation = useRef(0);

  const run = useCallback(async () => {
    const mine = ++generation.current;
    setLoading(true);
    setError(null);
    try {
      const result = await load();
      if (mine === generation.current) setData(result);
    } catch (err) {
      if (mine === generation.current) setError(errorMessage(err, 'Could not load this data.'));
    } finally {
      if (mine === generation.current) setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    void run();
  }, [run]);

  return { data, error, loading, reload: run, setData };
}
