/**
 * The Unify backend treats every DateTime without an offset as UTC, and the web
 * app always sends UTC ISO strings (Date#toISOString). People and Claude talk in
 * local business time, so these helpers turn "2026-11-25T10:00" into the UTC
 * instant it means in the business's time zone.
 */

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
const LOCAL_DATETIME = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3})\d*)?)?$/;
const HAS_OFFSET = /(Z|[+-]\d{2}:?\d{2})$/i;

/** Offset of `timeZone` from UTC at instant `utcMs`, in milliseconds. */
export function tzOffsetMs(utcMs: number, timeZone: string): number {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const parts: Record<string, number> = {};
  for (const p of fmt.formatToParts(new Date(utcMs))) {
    if (p.type !== "literal") parts[p.type] = Number(p.value);
  }
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return asUtc - Math.floor(utcMs / 1000) * 1000;
}

function localPartsToUtc(
  y: number, mo: number, d: number, h: number, mi: number, s: number, ms: number, timeZone: string,
): Date {
  const naive = Date.UTC(y, mo - 1, d, h, mi, s, ms);
  // Two passes so the offset is the one in force at the resulting instant (DST-safe).
  let utc = naive - tzOffsetMs(naive, timeZone);
  utc = naive - tzOffsetMs(utc, timeZone);
  return new Date(utc);
}

/**
 * Converts a user-supplied date/time to a UTC ISO string.
 * - "...Z" or "...+05:30": parsed as given.
 * - "2026-11-25T10:00": local time in `timeZone`.
 * - "2026-11-25": local midnight (or 23:59:59.999 when `endOfDay`).
 */
export function toUtcIso(value: string, timeZone: string, opts: { endOfDay?: boolean } = {}): string {
  const v = value.trim();
  if (DATE_ONLY.test(v)) {
    const [y, mo, d] = v.split("-").map(Number);
    return (opts.endOfDay
      ? localPartsToUtc(y, mo, d, 23, 59, 59, 999, timeZone)
      : localPartsToUtc(y, mo, d, 0, 0, 0, 0, timeZone)
    ).toISOString();
  }
  const m = LOCAL_DATETIME.exec(v);
  if (m && !HAS_OFFSET.test(v)) {
    const [, y, mo, d, h, mi, s, ms] = m;
    return localPartsToUtc(
      Number(y), Number(mo), Number(d), Number(h), Number(mi), Number(s ?? 0),
      Number((ms ?? "0").padEnd(3, "0")), timeZone,
    ).toISOString();
  }
  const parsed = new Date(v);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(
      `Could not read "${value}" as a date/time. Use ISO 8601, e.g. 2026-11-25 or 2026-11-25T14:30 (local) or 2026-11-25T09:00:00Z.`,
    );
  }
  return parsed.toISOString();
}

/** A calendar date (YYYY-MM-DD) in `timeZone`; accepts a date or a date-time. */
export function toLocalDate(value: string, timeZone: string): string {
  const v = value.trim();
  if (DATE_ONLY.test(v)) return v;
  const iso = toUtcIso(v, timeZone);
  return formatLocal(iso, timeZone).slice(0, 10);
}

/** "2026-11-25 15:30" style rendering of a UTC instant in `timeZone`. */
export function formatLocal(isoUtc: string, timeZone: string): string {
  const d = new Date(isoUtc);
  if (Number.isNaN(d.getTime())) return isoUtc;
  const fmt = new Intl.DateTimeFormat("sv-SE", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  return fmt.format(d).replace(",", "");
}

export function todayLocal(timeZone: string): string {
  return formatLocal(new Date().toISOString(), timeZone).slice(0, 10);
}
