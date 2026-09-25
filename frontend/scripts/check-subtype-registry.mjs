/* Fails if the tourism sub-type vocabulary has drifted apart across the four
 * places that must agree on it:
 *
 *   1. frontend/src/features/booking/types.ts   TOURISM_SUB_TYPES
 *        - the registration dropdown, and what actually gets stored in
 *          Tenant.SubType;
 *   2. frontend/.../subtypes/tourismSubTypes.ts TOURISM_SUB_TYPE_LABELS
 *        - what the dashboard registry matches that stored string against;
 *   3. frontend/.../subtypes/subtypeRegistry.ts
 *        - one config per key, no orphans;
 *   4. mobile/.../models/tourism_subtype.dart   kTourismSubTypeLabels
 *        - the Flutter app's copy of the same list.
 *
 * A mismatch between 1 and 2 is silent and nasty: the tenant registers fine,
 * and then quietly gets the generic dashboard forever because its SubType
 * string matches no registry key. Nothing else in the build catches that.
 *
 * Plain Node with no dependencies, the same reason check-nav-parity.mjs is:
 * this repo has a `vitest run` script, but the npm registry is blocked here,
 * so the vitest suite alongside these files cannot actually be installed or
 * run. This check runs on every build regardless.
 *
 *   node scripts/check-subtype-registry.mjs
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const repo = join(root, '..');
const read = (p) => readFileSync(p, 'utf8');

/** The string literals inside the first `[ ... ]` after a marker. */
function listAfter(source, marker) {
  const start = source.indexOf(marker);
  if (start === -1) return null;
  const open = source.indexOf('[', start);
  const close = source.indexOf(']', open);
  if (open === -1 || close === -1) return null;
  return [...source.slice(open, close).matchAll(/'([^']+)'/g)].map((m) => m[1]);
}

const registryTs = read(join(root, 'src/features/dashboard/subtypes/subtypeRegistry.ts'));
const subTypesTs = read(join(root, 'src/features/dashboard/subtypes/tourismSubTypes.ts'));
const bookingTypesTs = read(join(root, 'src/features/booking/types.ts'));
const mobileDart = read(join(repo, 'mobile/sme_mobile/lib/models/tourism_subtype.dart'));

/* 1. The registration dropdown. */
const registrationLabels = listAfter(bookingTypesTs, 'export const TOURISM_SUB_TYPES');

/* 2. The registry's key -> label map, in declaration order. */
const labelBlockStart = subTypesTs.indexOf('TOURISM_SUB_TYPE_LABELS');
const labelBlock = subTypesTs.slice(labelBlockStart, subTypesTs.indexOf('};', labelBlockStart));
const registryEntries = [...labelBlock.matchAll(/^\s{2}(\w+):\s*'([^']+)',$/gm)]
  .map(([, key, label]) => ({ key, label }));

/* The key list the type union is built from. */
const registryKeys = listAfter(subTypesTs, 'export const TOURISM_SUB_TYPE_KEYS');

/* 3. One config per key. */
const configKeys = [...registryTs.matchAll(/^ {2}(\w+): \{$/gm)].map((m) => m[1]);

/* 4. Mobile's copy. */
const mobileLabels = listAfter(mobileDart, 'kTourismSubTypeLabels');

let failed = false;
const fail = (message) => {
  failed = true;
  console.error(`FAIL ${message}`);
};

for (const [name, list] of Object.entries({
  registrationLabels, registryKeys, mobileLabels,
})) {
  if (!list || list.length === 0) fail(`could not parse ${name} - the source shape changed`);
}
if (registryEntries.length === 0) fail('could not parse TOURISM_SUB_TYPE_LABELS');
if (failed) process.exit(1);

const registryLabels = registryEntries.map((e) => e.label);

const compare = (label, a, b) => {
  const missing = a.filter((x) => !b.includes(x));
  const extra = b.filter((x) => !a.includes(x));
  if (missing.length) fail(`${label}: missing ${JSON.stringify(missing)}`);
  if (extra.length) fail(`${label}: unexpected ${JSON.stringify(extra)}`);
};

compare('registry labels vs the registration dropdown', registrationLabels, registryLabels);
compare('registry labels vs the Flutter app', mobileLabels, registryLabels);
compare('registry keys vs configs in subtypeRegistry.ts', registryKeys, configKeys);

/* Order matters for the dropdown, not just membership: the two lists are
 * compared elementwise in the vitest suite, so keep them in step here too. */
if (registrationLabels.join('|') !== registryLabels.join('|')) {
  fail('registry labels and the registration dropdown are in a different order');
}

/* Every key must actually be a config key, and every config a known key. */
const duplicateConfigs = configKeys.filter((k, i) => configKeys.indexOf(k) !== i);
if (duplicateConfigs.length) fail(`duplicate config entries: ${JSON.stringify(duplicateConfigs)}`);

if (failed) process.exit(1);

console.log(
  `ok: ${registryKeys.length} tourism sub-types agree across the registration dropdown, ` +
  `the dashboard registry, and the Flutter app`,
);
