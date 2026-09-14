/* Fails if a routed page has no sidebar entry, or a sidebar entry points at a
 * route that does not exist. Guards the sidebar grouping: sections are the
 * only nav definition, so this is what proves the regrouping dropped nothing.
 *
 * Plain Node with no dependencies on purpose — this repo has a `vitest run`
 * script but vitest is not installed, so a test file here would never run.
 *
 *   node scripts/check-nav-parity.mjs
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

/* Routes that intentionally have no sidebar entry: auth and error pages, the
 * redirect root, the profile page (reached from the sidebar footer avatar),
 * and two legacy routes kept only so old links do not 404. */
const NOT_IN_NAV = new Set([
  '/', '/login', '/register', '/unauthorized', '/profile', '/admin', '/legacy-dashboard',
]);

const routes = [...read('src/App.tsx').matchAll(/path="(\/[a-z0-9-]*)"/g)].map((m) => m[1]);
const navPaths = [...read('src/shared/components/AppLayout.tsx').matchAll(/path: '(\/[a-z0-9-]*)'/g)].map((m) => m[1]);

const routeSet = new Set(routes);
const navSet = new Set(navPaths);

const missingFromNav = routes.filter((r) => !NOT_IN_NAV.has(r) && !navSet.has(r));
const danglingNav = navPaths.filter((p) => !routeSet.has(p));
const duplicateNav = navPaths.filter((p, i) => navPaths.indexOf(p) !== i);

let failed = false;
const fail = (label, list) => {
  if (list.length === 0) return;
  failed = true;
  console.error(`FAIL ${label}:\n  ${list.join('\n  ')}`);
};

fail('routed pages with no sidebar entry', missingFromNav);
fail('sidebar entries pointing at no route', danglingNav);
fail('sidebar entries listed more than once', duplicateNav);

if (failed) process.exit(1);

console.log(
  `ok: ${navPaths.length} sidebar entries cover every routed page ` +
  `(${routes.length} routes, ${NOT_IN_NAV.size} intentionally not in nav)`
);
