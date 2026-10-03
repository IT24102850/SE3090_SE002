/* The one place that decides where the API is.
 *
 * Every module used to read import.meta.env.VITE_API_URL itself, each with a
 * slightly different fallback, and one of them trimmed the value while the
 * rest did not. That is how a value pasted into Vercel with an invisible
 * UTF-8 BOM in front ("﻿https://...") broke sign-in but not the pages
 * that happened to trim: the browser treats a URL that starts with a BOM as
 * a relative path, posts it to Vercel itself, and gets a 405.
 *
 * Rules, in order:
 *   1. A configured absolute URL (http/https) wins, cleaned of BOM,
 *      whitespace and trailing slashes.
 *   2. A configured root-relative path ("/api") is used as-is.
 *   3. Otherwise, a production build uses "/api", which vercel.json rewrites
 *      to the deployed backend - so a missing or mangled variable still
 *      yields a working app rather than calls to localhost.
 *   4. Dev builds fall back to the local backend.
 */
const configured = (import.meta.env.VITE_API_URL ?? '')
  .replace(/^﻿/, '')
  .trim()
  .replace(/\/+$/, '');

export const LOCAL_API_BASE_URL = 'http://localhost:5298/api';

export const API_BASE_URL: string =
  /^https?:\/\//i.test(configured) ? configured
  : configured.startsWith('/') ? configured
  : import.meta.env.PROD ? '/api'
  : LOCAL_API_BASE_URL;
