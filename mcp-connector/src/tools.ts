import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { UnifyApiError, UnifyClient, type Query } from "./client.js";
import { formatLocal, toLocalDate, toUtcIso, todayLocal, tzOffsetMs } from "./time.js";

type ToolResult = { content: { type: "text"; text: string }[]; isError?: boolean };

const MAX_CHARS = 60_000;
const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]00:?00)$/;

/** Adds a `<key>Local` sibling to every UTC timestamp so Claude never has to convert by hand. */
export function annotateTimes(data: unknown, timeZone: string, depth = 0): unknown {
  if (depth > 12 || data === null || typeof data !== "object") return data;
  if (Array.isArray(data)) return data.map((d) => annotateTimes(d, timeZone, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data as Record<string, unknown>)) {
    out[k] = annotateTimes(v, timeZone, depth + 1);
    if (typeof v === "string" && ISO_UTC.test(v) && !(`${k}Local` in (data as object))) {
      out[`${k}Local`] = formatLocal(v, timeZone);
    }
  }
  return out;
}

function render(data: unknown, timeZone: string): string {
  const annotated = annotateTimes(data, timeZone);
  let text = JSON.stringify(annotated, null, 2);
  if (text.length > 8_000) text = JSON.stringify(annotated);
  if (text.length > MAX_CHARS) {
    text =
      text.slice(0, MAX_CHARS) +
      `\n...[truncated ${text.length - MAX_CHARS} characters - narrow the query with filters, a smaller date range, or a smaller pageSize]`;
  }
  return text;
}

function ok(data: unknown, timeZone: string, note?: string): ToolResult {
  const body = render(data, timeZone);
  return { content: [{ type: "text", text: note ? `${note}\n\n${body}` : body }] };
}

function fail(err: unknown): ToolResult {
  let text: string;
  if (err instanceof UnifyApiError) {
    text = `Unify API error on ${err.method} ${err.path}: ${err.message}`;
    if (err.details && typeof err.details === "object") {
      const d = JSON.stringify(err.details);
      if (d.length < 2000 && !text.includes(d)) text += `\nDetails: ${d}`;
    }
  } else {
    text = `Error: ${(err as Error)?.message ?? String(err)}`;
  }
  return { content: [{ type: "text", text }], isError: true };
}

const uuid = (what: string) => z.string().uuid().describe(`${what} (UUID)`);
const optUuid = (what: string) => uuid(what).optional();
const dateTime = (what: string) =>
  z.string().describe(
    `${what}. ISO 8601. Without an offset it is read as business-local time ` +
      `(e.g. "2026-11-25T14:30"); a bare date like "2026-11-25" is also accepted.`,
  );
const page = z.number().int().min(1).optional().describe("Page number, starting at 1");
const pageSize = (max = 100) => z.number().int().min(1).max(max).optional().describe(`Items per page (max ${max})`);

const BOOKING_STATUSES = [
  "Pending", "Confirmed", "CheckedIn", "InProgress", "Completed", "Cancelled", "NoShow", "Rejected", "WeatherCancelled",
] as const;

const DASHBOARD_VIEWS = {
  clinic: ["overview", "flow", "alerts", "reminders"],
  restaurant: ["overview", "live", "alerts", "inventory"],
  gym: ["overview", "live", "attendance", "alerts"],
  school: ["overview", "today", "gradebook", "alerts"],
  excursions: ["kpis", "revenue-by-ticket-type", "per-departure", "weather-cancellations", "channel-split"],
} as const;
type Dashboard = keyof typeof DASHBOARD_VIEWS;

const READ = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true } as const;
const WRITE = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true } as const;
const DESTRUCTIVE = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true } as const;

export function registerTools(server: McpServer, client: UnifyClient, opts: { readOnly: boolean }) {
  const tz = client.timeZone;
  const utc = (v: string | undefined, endOfDay = false) => (v ? toUtcIso(v, tz, { endOfDay }) : undefined);
  const tzMinutes = () => Math.round(tzOffsetMs(Date.now(), tz) / 60_000);
  const get = (path: string, query?: Query) => client.request("GET", path, { query });

  type Shape = z.ZodRawShape;
  const tool = <S extends Shape>(
    name: string,
    title: string,
    description: string,
    inputSchema: S,
    annotations: typeof READ | typeof WRITE | typeof DESTRUCTIVE,
    handler: (args: z.objectOutputType<S, z.ZodTypeAny>) => Promise<unknown>,
  ) => {
    if (opts.readOnly && !annotations.readOnlyHint) return;
    server.registerTool(
      name,
      { title, description, inputSchema, annotations: { title, ...annotations } },
      (async (args: z.objectOutputType<S, z.ZodTypeAny>) => {
        try {
          const result = await handler(args);
          if (result && typeof result === "object" && "__note" in (result as object)) {
            const { __note, data } = result as { __note: string; data: unknown };
            return ok(data, tz, __note);
          }
          return ok(result, tz);
        } catch (e) {
          return fail(e);
        }
      }) as never,
    );
  };

  // ── Account & business ────────────────────────────────────────────────
  tool(
    "unify_whoami",
    "Who am I in Unify",
    "Shows the signed-in Unify user (name, role, tenant/business id, branch), the business profile " +
      "(name, business type, sub-type), the API being used, and the time zone this connector uses. " +
      "It reports the business type and the user's permissions. " +
      "Roles: Admin (full), Manager, Staff, Customer.",
    {},
    READ,
    async () => {
      const user = await client.me();
      let business: unknown = null;
      try {
        business = await get("/tenant", { tenantId: user.tenantId });
      } catch (e) {
        business = { unavailable: (e as Error).message };
      }
      return {
        user,
        business,
        connector: { apiUrl: client.baseUrl, timeZone: tz, todayLocal: todayLocal(tz), readOnly: opts.readOnly },
      };
    },
  );

  tool(
    "unify_list_branches",
    "List branches",
    "Lists the business's branches (locations). Use the branch ids to filter resources, bookings and reports.",
    {},
    READ,
    async () => get("/branches", { tenantId: await client.tenantId() }),
  );

  tool(
    "unify_list_staff",
    "List staff",
    "Lists staff and manager accounts of the business (Admin/Manager only).",
    { includeInactive: z.boolean().optional().describe("Include deactivated staff") },
    READ,
    async ({ includeInactive }) => get("/tenant/staff", { tenantId: await client.tenantId(), includeInactive }),
  );

  tool(
    "unify_search_customers",
    "Search customers",
    "Finds customers of this business by name, email or phone. Use the returned id as customerId when " +
      "creating a booking on someone's behalf. Staff, Manager or Admin only.",
    {
      search: z.string().optional().describe("Name, email or phone fragment"),
      take: z.number().int().min(1).max(200).optional().describe("Max results (default 50)"),
    },
    READ,
    async ({ search, take }) => get("/billing/customers", { search, take }),
  );

  tool(
    "unify_list_public_businesses",
    "Browse Unify businesses",
    "Lists the public directory of businesses on the Unify platform (what customers see in the app's " +
      "'Find a business' screen).",
    {},
    READ,
    async () => client.request("GET", "/tenant/public", { anonymous: true }),
  );

  // ── Resources & availability ─────────────────────────────────────────
  tool(
    "unify_list_resources",
    "List resources",
    "Lists bookable resources (doctors, tables, trainers, tutors, boats, rooms, vehicles, equipment...). " +
      "Filter by branch, category (Room|Equipment|Vehicle|Staff|Desk|Other), status, free-text search or specialty.",
    {
      branchId: optUuid("Branch id"),
      category: z.enum(["Room", "Equipment", "Vehicle", "Staff", "Desk", "Other"]).optional(),
      status: z.string().optional().describe("e.g. Available, Unavailable, Maintenance"),
      search: z.string().optional(),
      specialty: z.string().optional().describe("e.g. Dentist, Pediatrics"),
      page,
      pageSize: pageSize(100),
    },
    READ,
    async (a) => get("/resources", { tenantId: await client.tenantId(), ...a }),
  );

  tool(
    "unify_get_resource",
    "Get resource details",
    "Gets one resource with its weekly working schedule and schedule exceptions (holidays, leave, closures).",
    { resourceId: uuid("Resource id") },
    READ,
    async ({ resourceId }) => {
      const [resource, schedule, exceptions] = await Promise.allSettled([
        get(`/resources/${resourceId}`),
        get(`/resources/${resourceId}/schedule`),
        get(`/resources/${resourceId}/schedule-exceptions`),
      ]);
      const val = (r: PromiseSettledResult<unknown>) =>
        r.status === "fulfilled" ? r.value : { error: (r.reason as Error)?.message };
      if (resource.status === "rejected") throw resource.reason;
      return { resource: val(resource), weeklySchedule: val(schedule), scheduleExceptions: val(exceptions) };
    },
  );

  tool(
    "unify_find_available_slots",
    "Find free time slots",
    "Finds open time slots on a given day. Give resourceId to check one resource, or leave it out to search " +
      "every available resource of the business (optionally by specialty/branch). For Slot-type bookings " +
      "(consultations, tables, classes, tours). For Night/DateRange bookings (rooms, vehicles) use " +
      "unify_get_booked_ranges instead.",
    {
      date: z.string().describe("Day to search, YYYY-MM-DD (business-local)"),
      resourceId: optUuid("Resource id - omit to search all resources"),
      bookingTypeId: optUuid("Booking type id (applies its duration and buffers)"),
      durationMinutes: z.number().int().min(5).max(24 * 60).optional().describe("Slot length; default 60 or the booking type's"),
      specialty: z.string().optional().describe("Only when searching all resources"),
      branchId: optUuid("Only when searching all resources"),
    },
    READ,
    async ({ date, resourceId, bookingTypeId, durationMinutes, specialty, branchId }) => {
      const day = toLocalDate(date, tz);
      const duration = durationMinutes ?? (bookingTypeId ? 0 : 60);
      if (resourceId) {
        return get("/bookings/available-slots", { resourceId, date: day, duration, bookingTypeId });
      }
      return get("/resources/search-availability", {
        tenantId: await client.tenantId(),
        date: day,
        duration: duration || 60,
        bookingTypeId,
        specialty,
        branchId,
      });
    },
  );

  tool(
    "unify_get_booked_ranges",
    "Get booked date ranges",
    "Returns the periods a resource is already booked between two dates. Use for Night (accommodation), " +
      "DateRange (vehicle/equipment rental) and Package bookings to see which dates are free.",
    {
      resourceId: uuid("Resource id"),
      from: dateTime("Start of the window"),
      to: dateTime("End of the window"),
    },
    READ,
    async ({ resourceId, from, to }) =>
      get("/bookings/unavailable-ranges", { resourceId, from: utc(from), to: utc(to, true) }),
  );

  const jsonOrNull = (v: unknown) => (v === undefined ? undefined : JSON.stringify(v));
  const RESOURCE_CATEGORIES = ["Room", "Equipment", "Vehicle", "Staff", "Desk", "Other"] as const;

  tool(
    "unify_create_resource",
    "Create a resource",
    "Adds a bookable resource (boat, room, vehicle, staff member, table...) to the business (Admin/Manager). " +
      "It appears in the website booking form's resource list once it has status Available.",
    {
      name: z.string().min(1).max(100),
      category: z.enum(RESOURCE_CATEGORIES),
      description: z.string().max(500).optional(),
      capacity: z.number().int().min(1).optional(),
      hourlyRate: z.number().min(0).optional(),
      specialty: z.string().max(100).optional(),
      code: z.string().max(20).optional(),
      branchId: optUuid("Branch id"),
      customAttributes: z.record(z.unknown()).optional().describe("Free-form details, e.g. departure time, pricing, inclusions"),
    },
    WRITE,
    async (a) =>
      client.request("POST", "/resources", {
        body: {
          tenantId: await client.tenantId(),
          branchId: a.branchId ?? null,
          name: a.name,
          code: a.code ?? null,
          category: a.category,
          description: a.description ?? null,
          capacity: a.capacity ?? null,
          hourlyRate: a.hourlyRate ?? null,
          specialty: a.specialty ?? null,
          linkedUserId: null,
          customAttributes: jsonOrNull(a.customAttributes) ?? null,
          locationMetadata: null,
        },
      }),
  );

  tool(
    "unify_update_resource",
    "Update a resource",
    "Changes a resource's details or status (Admin/Manager). Only the fields given are changed. Status " +
      "Available shows it in the booking form; UnderMaintenance or Archived hides it without deleting it.",
    {
      resourceId: uuid("Resource id"),
      name: z.string().min(1).max(100).optional(),
      category: z.enum(RESOURCE_CATEGORIES).optional(),
      status: z.enum(["Available", "UnderMaintenance", "Archived", "Reserved"]).optional(),
      description: z.string().max(500).optional(),
      capacity: z.number().int().min(1).optional(),
      hourlyRate: z.number().min(0).optional(),
      specialty: z.string().max(100).optional(),
      branchId: optUuid("Branch id"),
      customAttributes: z.record(z.unknown()).optional().describe("Replaces the resource's custom attributes"),
    },
    WRITE,
    async ({ resourceId, customAttributes, ...rest }) =>
      client.request("PUT", `/resources/${resourceId}`, {
        body: { ...rest, customAttributes: jsonOrNull(customAttributes) },
      }),
  );

  tool(
    "unify_delete_resource",
    "Delete a resource",
    "Deletes a resource so it no longer appears anywhere (Admin/Manager). Unify refuses while the resource " +
      "has upcoming bookings.",
    { resourceId: uuid("Resource id") },
    WRITE,
    async ({ resourceId }) => client.request("DELETE", `/resources/${resourceId}`),
  );

  // ── Booking types ────────────────────────────────────────────────────
  tool(
    "unify_list_booking_types",
    "List booking types",
    "Lists the services/products that can be booked (e.g. 'Consultation', 'Whale Watching Tour', 'Room Stay') " +
      "with duration, price, booking unit (Slot | Night | DateRange | Package), approval rules and config.",
    { status: z.string().optional().describe("e.g. Active") },
    READ,
    async ({ status }) => get("/bookingtypes", { tenantId: await client.tenantId(), status }),
  );

  const priceFields = {
    adultPrice: z.number().min(0).optional().describe("Price per adult"),
    childPrice: z.number().min(0).optional().describe("Price per child"),
    infantPrice: z.number().min(0).optional().describe("Price per infant"),
    currency: z.string().length(3).optional().describe("e.g. LKR, USD"),
  };
  /** Merges price fields and a config patch into a booking type's ConfigJson (null in the patch removes a key). */
  const mergeConfig = (
    current: string | null | undefined,
    prices: { adultPrice?: number; childPrice?: number; infantPrice?: number; currency?: string },
    patch?: Record<string, unknown>,
  ) => {
    let cfg: Record<string, unknown> = {};
    try {
      cfg = current ? JSON.parse(current) : {};
    } catch {
      cfg = {};
    }
    for (const [k, v] of Object.entries(patch ?? {})) {
      if (v === null) delete cfg[k];
      else cfg[k] = v;
    }
    const touched = ["adultPrice", "childPrice", "infantPrice", "currency"].some(
      (k) => (prices as Record<string, unknown>)[k] !== undefined,
    );
    if (touched) {
      const pricing = { ...((cfg.pricing as Record<string, unknown>) ?? {}) };
      if (prices.adultPrice !== undefined) pricing.adult = prices.adultPrice;
      if (prices.childPrice !== undefined) pricing.child = prices.childPrice;
      if (prices.infantPrice !== undefined) pricing.infant = prices.infantPrice;
      if (prices.currency !== undefined) pricing.currency = prices.currency.toUpperCase();
      cfg.pricing = pricing;
    }
    return JSON.stringify(cfg);
  };

  tool(
    "unify_create_booking_type",
    "Create a booking type",
    "Adds a service customers can book, such as a tour or treatment (Admin/Manager), with duration, booking " +
      "unit and per-person prices. Active booking types appear in the website booking form's tour list.",
    {
      name: z.string().min(1).max(100),
      description: z.string().max(1000).optional(),
      durationMinutes: z.number().int().min(5).max(60 * 24 * 30),
      bookingUnit: z.enum(["Slot", "Night", "DateRange", "Package"]).optional().describe("Default Slot"),
      maxParticipants: z.number().int().min(1).optional(),
      requiresApproval: z.boolean().optional(),
      bufferMinutesBefore: z.number().int().min(0).optional(),
      bufferMinutesAfter: z.number().int().min(0).optional(),
      colorHex: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
      ...priceFields,
      config: z.record(z.unknown()).optional().describe("Other settings stored with the booking type (season, includes...)"),
    },
    WRITE,
    async (a) =>
      client.request("POST", "/bookingtypes", {
        body: {
          tenantId: await client.tenantId(),
          name: a.name,
          description: a.description ?? null,
          colorHex: a.colorHex ?? null,
          defaultDurationMinutes: a.durationMinutes,
          requiresApproval: a.requiresApproval ?? false,
          maxParticipants: a.maxParticipants ?? null,
          bufferMinutesBefore: a.bufferMinutesBefore ?? 0,
          bufferMinutesAfter: a.bufferMinutesAfter ?? 0,
          bookingUnit: a.bookingUnit ?? "Slot",
          configJson: mergeConfig(JSON.stringify({ bookingUnit: a.bookingUnit ?? "Slot" }), a, a.config),
        },
      }),
  );

  tool(
    "unify_update_booking_type",
    "Update a booking type",
    "Changes a service's details, prices or status (Admin/Manager). Only the fields given are changed; prices " +
      "and configPatch are merged into the existing settings. Status Inactive removes it from the booking form.",
    {
      bookingTypeId: uuid("Booking type id"),
      name: z.string().min(1).max(100).optional(),
      description: z.string().max(1000).optional(),
      status: z.enum(["Active", "Inactive"]).optional(),
      durationMinutes: z.number().int().min(5).max(60 * 24 * 30).optional(),
      maxParticipants: z.number().int().min(1).optional(),
      requiresApproval: z.boolean().optional(),
      bufferMinutesBefore: z.number().int().min(0).optional(),
      bufferMinutesAfter: z.number().int().min(0).optional(),
      colorHex: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
      ...priceFields,
      configPatch: z
        .record(z.unknown())
        .optional()
        .describe("Top-level settings to set; a null value removes that key"),
    },
    WRITE,
    async (a) => {
      const touchesConfig =
        a.configPatch !== undefined ||
        [a.adultPrice, a.childPrice, a.infantPrice, a.currency].some((v) => v !== undefined);
      let configJson: string | undefined;
      if (touchesConfig) {
        const current = (await get(`/bookingtypes/${a.bookingTypeId}`)) as Record<string, unknown>;
        configJson = mergeConfig((current.configJson ?? current.ConfigJson) as string | null, a, a.configPatch);
      }
      return client.request("PUT", `/bookingtypes/${a.bookingTypeId}`, {
        body: {
          name: a.name,
          description: a.description,
          colorHex: a.colorHex,
          status: a.status,
          defaultDurationMinutes: a.durationMinutes,
          requiresApproval: a.requiresApproval,
          maxParticipants: a.maxParticipants,
          bufferMinutesBefore: a.bufferMinutesBefore,
          bufferMinutesAfter: a.bufferMinutesAfter,
          configJson,
        },
      });
    },
  );

  tool(
    "unify_delete_booking_type",
    "Archive a booking type",
    "Archives a service so it can no longer be booked (Admin/Manager). Existing bookings keep it.",
    { bookingTypeId: uuid("Booking type id") },
    WRITE,
    async ({ bookingTypeId }) => client.request("DELETE", `/bookingtypes/${bookingTypeId}`),
  );

  // ── Bookings ─────────────────────────────────────────────────────────
  tool(
    "unify_list_bookings",
    "List bookings",
    "Lists bookings/reservations with filters. Dates are business-local; a bare date for dateTo covers " +
      "that whole day. Each timestamp also comes back with a ...Local field in business time.",
    {
      dateFrom: dateTime("From").optional(),
      dateTo: dateTime("To").optional(),
      status: z.enum(BOOKING_STATUSES).optional(),
      resourceId: optUuid("Resource id"),
      bookingTypeId: optUuid("Booking type id"),
      branchId: optUuid("Branch id"),
      customerId: optUuid("Customer (bookedBy) user id"),
      page,
      pageSize: pageSize(100),
    },
    READ,
    async (a) =>
      get("/bookings", {
        tenantId: await client.tenantId(),
        dateFrom: utc(a.dateFrom),
        dateTo: utc(a.dateTo, true),
        status: a.status,
        resourceId: a.resourceId,
        type: a.bookingTypeId,
        branchId: a.branchId,
        bookedBy: a.customerId,
        page: a.page,
        pageSize: a.pageSize ?? 50,
      }),
  );

  tool(
    "unify_get_booking",
    "Get booking details",
    "Gets one booking, optionally with its full history timeline (who created, rescheduled, checked in...).",
    { bookingId: uuid("Booking id"), includeHistory: z.boolean().optional().describe("Default true") },
    READ,
    async ({ bookingId, includeHistory }) => {
      const booking = await get(`/bookings/${bookingId}`);
      if (includeHistory === false) return booking;
      let history: unknown;
      try {
        history = await get(`/bookings/${bookingId}/history`);
      } catch (e) {
        history = { unavailable: (e as Error).message };
      }
      return { booking, history };
    },
  );

  tool(
    "unify_get_my_schedule",
    "My schedule",
    "The signed-in staff member's own bookings for a day (Admin/Manager/Staff).",
    { date: z.string().optional().describe("YYYY-MM-DD, default today (business-local)") },
    READ,
    async ({ date }) => get("/bookings/my-schedule", { date: date ? toLocalDate(date, tz) : todayLocal(tz) }),
  );

  tool(
    "unify_find_booking_conflicts",
    "Find double-bookings",
    "Reports overlapping bookings on the same resource (Admin/Manager).",
    { from: dateTime("From").optional(), to: dateTime("To").optional() },
    READ,
    async ({ from, to }) =>
      get("/bookings/conflicts", { tenantId: await client.tenantId(), from: utc(from), to: utc(to, true) }),
  );

  tool(
    "unify_create_booking",
    "Create a booking",
    "Creates a booking for a resource and booking type. Free times come from unify_find_available_slots (Slot types) " +
      "or unify_get_booked_ranges (Night/DateRange types). Takes either endTime or durationMinutes. customerId is the customer the " +
      "booking is for (find it with unify_search_customers); if omitted the booking is made under the " +
      "signed-in user.",
    {
      resourceId: uuid("Resource id"),
      bookingTypeId: uuid("Booking type id"),
      startTime: dateTime("Start"),
      endTime: dateTime("End").optional(),
      durationMinutes: z.number().int().min(1).optional().describe("Used when endTime is not given"),
      customerId: optUuid("Customer user id (bookedBy)"),
      title: z.string().max(200).optional(),
      notes: z.string().max(2000).optional(),
      attendeeCount: z.number().int().min(1).optional().describe("Party size / number of guests"),
      priority: z.enum(["Low", "Normal", "High", "Urgent"]).optional(),
      source: z.string().optional().describe("Channel: WalkIn | Online | OTA | phone..."),
      ticketBreakdown: z
        .array(z.record(z.unknown()))
        .optional()
        .describe('Excursion tickets, e.g. [{"type":"Adult","quantity":2},{"type":"Child","quantity":1}]'),
      departureId: optUuid("Fixed departure id (excursions)"),
      formData: z.record(z.unknown()).optional().describe("Extra booking-type fields (tourism wizard data)"),
    },
    WRITE,
    async (a) => {
      const me = await client.me();
      const start = toUtcIso(a.startTime, tz);
      let end: string;
      if (a.endTime) end = toUtcIso(a.endTime, tz);
      else if (a.durationMinutes) end = new Date(new Date(start).getTime() + a.durationMinutes * 60_000).toISOString();
      else throw new Error("Give endTime or durationMinutes.");
      if (new Date(end) <= new Date(start)) throw new Error("endTime must be after startTime.");
      return client.request("POST", "/bookings", {
        body: {
          tenantId: me.tenantId,
          resourceId: a.resourceId,
          bookingTypeId: a.bookingTypeId,
          bookedBy: a.customerId ?? me.id,
          startTime: start,
          endTime: end,
          title: a.title ?? null,
          notes: a.notes ?? null,
          bookedFor: null,
          priority: a.priority ?? "Normal",
          attendeeCount: a.attendeeCount ?? null,
          formData: a.formData ? JSON.stringify(a.formData) : null,
          departureId: a.departureId ?? null,
          ticketBreakdown: a.ticketBreakdown ?? null,
          source: a.source ?? null,
        },
      });
    },
  );

  tool(
    "unify_reschedule_booking",
    "Reschedule a booking",
    "Moves a booking to a new time. Give newEndTime, or durationMinutes to keep/set the length " +
      "(if neither is given the original length is kept). Respects the business's reschedule cutoff.",
    {
      bookingId: uuid("Booking id"),
      newStartTime: dateTime("New start"),
      newEndTime: dateTime("New end").optional(),
      durationMinutes: z.number().int().min(1).optional(),
    },
    WRITE,
    async ({ bookingId, newStartTime, newEndTime, durationMinutes }) => {
      const start = toUtcIso(newStartTime, tz);
      let end: string;
      if (newEndTime) end = toUtcIso(newEndTime, tz);
      else {
        let minutes = durationMinutes;
        if (!minutes) {
          const b = (await get(`/bookings/${bookingId}`)) as Record<string, string>;
          const s = new Date(b.startTime ?? b.StartTime).getTime();
          const e = new Date(b.endTime ?? b.EndTime).getTime();
          if (!Number.isFinite(s) || !Number.isFinite(e)) throw new Error("Could not read the booking's current length; give newEndTime.");
          minutes = Math.round((e - s) / 60_000);
        }
        end = new Date(new Date(start).getTime() + minutes * 60_000).toISOString();
      }
      return client.request("PUT", `/bookings/${bookingId}/reschedule`, {
        body: { newStartTime: start, newEndTime: end },
      });
    },
  );

  tool(
    "unify_cancel_booking",
    "Cancel a booking",
    "Cancels a booking. Unify notifies the customer.",
    { bookingId: uuid("Booking id") },
    DESTRUCTIVE,
    async ({ bookingId }) => client.request("PUT", `/bookings/${bookingId}/cancel`),
  );

  tool(
    "unify_update_booking_status",
    "Update booking status",
    "Sets a booking's status: Confirmed (approve), Rejected, CheckedIn, InProgress, Completed, NoShow... " +
      "Optional notes are stored as the practitioner's notes. Admin/Manager/Staff.",
    {
      bookingId: uuid("Booking id"),
      status: z.enum(BOOKING_STATUSES),
      notes: z.string().max(4000).optional(),
    },
    WRITE,
    async ({ bookingId, status, notes }) =>
      client.request("PUT", `/bookings/${bookingId}/status`, { body: { status, doctorNotes: notes ?? null } }),
  );

  tool(
    "unify_check_in_booking",
    "Check in a guest",
    "Checks a customer in for their booking (same as scanning their QR code). Admin/Manager/Staff.",
    { bookingId: uuid("Booking id") },
    WRITE,
    async ({ bookingId }) => client.request("POST", `/bookings/${bookingId}/checkin`),
  );

  tool(
    "unify_send_booking_reminder",
    "Send booking reminder",
    "Sends the customer a reminder for an upcoming booking.",
    { bookingId: uuid("Booking id"), channel: z.string().optional().describe("e.g. Email, Push, InApp") },
    WRITE,
    async ({ bookingId, channel }) =>
      client.request("POST", `/bookings/${bookingId}/remind`, { body: { channel: channel ?? null } }),
  );

  // ── Reports ──────────────────────────────────────────────────────────
  tool(
    "unify_get_dashboard",
    "Operations dashboard",
    "Reads a business-type operations dashboard. Dashboards and views:\n" +
      Object.entries(DASHBOARD_VIEWS).map(([d, v]) => `- ${d}: ${v.join(", ")}`).join("\n") +
      "\nOmit 'dashboard' to pick it from the business type (Clinic, Restaurant, Gym, School, Tourism->excursions). " +
      "Omit 'view' for the overview/kpis. 'on' is for single-day views (flow, live, today, kpis).",
    {
      dashboard: z.enum(Object.keys(DASHBOARD_VIEWS) as [Dashboard, ...Dashboard[]]).optional(),
      view: z.string().optional(),
      from: dateTime("From").optional(),
      to: dateTime("To").optional(),
      on: z.string().optional().describe("Day, YYYY-MM-DD"),
      branchId: optUuid("Branch id"),
      resourceId: optUuid("Resource id"),
      groupBy: z.enum(["day", "week", "month"]).optional(),
    },
    READ,
    async (a) => {
      let dashboard = a.dashboard;
      if (!dashboard) {
        const me = await client.me();
        const t = (await get("/tenant", { tenantId: me.tenantId })) as Record<string, unknown>;
        const type = String(t.businessType ?? t.BusinessType ?? "").toLowerCase();
        const map: Record<string, Dashboard> = {
          clinic: "clinic", restaurant: "restaurant", gym: "gym", school: "school", tourism: "excursions",
        };
        dashboard = map[type];
        if (!dashboard) {
          throw new Error(
            `No operations dashboard for business type "${type || "unknown"}". Use unify_get_revenue_report or unify_list_bookings instead.`,
          );
        }
      }
      const views = DASHBOARD_VIEWS[dashboard] as readonly string[];
      const view = a.view ?? views[0];
      if (!views.includes(view)) throw new Error(`View "${view}" is not valid for ${dashboard}. Use one of: ${views.join(", ")}`);
      const path = dashboard === "excursions" ? `/reports/excursions/${view}` : `/reports/${dashboard}/${view}`;
      const data = await get(path, {
        from: utc(a.from),
        to: utc(a.to, true),
        on: a.on ? toLocalDate(a.on, tz) : undefined,
        branchId: a.branchId,
        resourceId: a.resourceId,
        groupBy: a.groupBy,
        tz: tzMinutes(),
      });
      return { __note: `Dashboard: ${dashboard} / ${view}`, data };
    },
  );

  tool(
    "unify_get_revenue_report",
    "Revenue report",
    "Revenue for a period (optionally one branch). Defaults to the last 30 days.",
    { from: dateTime("From").optional(), to: dateTime("To").optional(), branchId: optUuid("Branch id") },
    READ,
    async ({ from, to, branchId }) => {
      const end = to ?? todayLocal(tz);
      const start = from ?? new Date(new Date(toUtcIso(end, tz)).getTime() - 29 * 86_400_000).toISOString();
      return get("/reports/revenue", { from: utc(start), to: utc(end, true), branchId });
    },
  );

  tool(
    "unify_get_booking_stats",
    "Booking statistics",
    "No-show statistics and revenue per time slot for a period (Admin/Manager). Defaults to the last 30 days.",
    { from: dateTime("From").optional(), to: dateTime("To").optional(), branchId: optUuid("Branch id") },
    READ,
    async ({ from, to, branchId }) => {
      const tenantId = await client.tenantId();
      const end = utc(to ?? todayLocal(tz), true)!;
      const start = from ? utc(from)! : new Date(new Date(end).getTime() - 30 * 86_400_000).toISOString();
      const [noShows, revenuePerSlot] = await Promise.allSettled([
        get("/bookings/reports/no-shows", { tenantId, from: start, to: end }),
        get("/bookings/reports/revenue-per-slot", { tenantId, from: start, to: end, branchId, tz: tzMinutes() }),
      ]);
      const val = (r: PromiseSettledResult<unknown>) =>
        r.status === "fulfilled" ? r.value : { error: (r.reason as Error)?.message };
      return { period: { from: start, to: end }, noShows: val(noShows), revenuePerSlot: val(revenuePerSlot) };
    },
  );

  // ── Inventory & billing ──────────────────────────────────────────────
  tool(
    "unify_list_inventory",
    "List inventory",
    "Lists stock items (with quantities and reorder levels). Set lowStock to see only items that need reordering.",
    {
      lowStock: z.boolean().optional(),
      category: z.string().optional(),
      branchId: optUuid("Branch id"),
      page,
      pageSize: pageSize(100),
    },
    READ,
    async ({ lowStock, category, branchId, page: p, pageSize: ps }) =>
      lowStock && !category
        ? get("/inventory/low-stock", { branchId, page: p, pageSize: ps })
        : get("/inventory", { category, lowStock, branchId, page: p, pageSize: ps }),
  );

  tool(
    "unify_list_invoices",
    "List invoices",
    "Lists invoices with filters (status e.g. Draft, Issued, PartiallyPaid, Paid, Overdue, Cancelled).",
    {
      status: z.string().optional(),
      from: dateTime("From").optional(),
      to: dateTime("To").optional(),
      customerId: optUuid("Customer id"),
      branchId: optUuid("Branch id"),
      search: z.string().optional(),
      page,
      pageSize: pageSize(100),
    },
    READ,
    async (a) =>
      get("/invoices", {
        status: a.status,
        from: utc(a.from),
        to: utc(a.to, true),
        customerId: a.customerId,
        branchId: a.branchId,
        search: a.search,
        page: a.page,
        pageSize: a.pageSize,
      }),
  );

  tool(
    "unify_get_invoice",
    "Get invoice",
    "Gets one invoice with its line items and payments.",
    { invoiceId: uuid("Invoice id") },
    READ,
    async ({ invoiceId }) => get(`/invoices/${invoiceId}`),
  );

  // ── Notifications ────────────────────────────────────────────────────
  tool(
    "unify_list_notifications",
    "List notifications",
    "The signed-in user's in-app notifications (new bookings, cancellations, approvals...), with unread count.",
    { page, pageSize: pageSize(100) },
    READ,
    async ({ page: p, pageSize: ps }) => {
      const [items, unread] = await Promise.allSettled([
        get("/notifications", { page: p, pageSize: ps }),
        get("/notifications/unread-count"),
      ]);
      if (items.status === "rejected") throw items.reason;
      return { unread: unread.status === "fulfilled" ? unread.value : null, notifications: items.value };
    },
  );

  tool(
    "unify_mark_notification_read",
    "Mark notification read",
    "Marks one notification as read.",
    { notificationId: uuid("Notification id") },
    WRITE,
    async ({ notificationId }) => client.request("PUT", `/notifications/${notificationId}/read`),
  );

  // ── AI planner workflows ─────────────────────────────────────────────
  tool(
    "unify_list_ai_workflows",
    "List AI planner workflows",
    "Lists Unify's AI agent workflows (scheduling plans, find-and-book proposals) awaiting review or already " +
      "handled. Status e.g. PendingApproval, Approved, Rejected, Applied.",
    { status: z.string().optional() },
    READ,
    async ({ status }) => get("/agent/workflow", { tenantId: await client.tenantId(), status }),
  );

  tool(
    "unify_get_ai_workflow",
    "Get AI workflow",
    "Gets one AI workflow with its objective, planned steps and validation results.",
    { workflowId: uuid("Workflow id") },
    READ,
    async ({ workflowId }) => get(`/agent/workflow/${workflowId}`),
  );

  tool(
    "unify_approve_ai_workflow",
    "Approve AI workflow",
    "Approves a pending AI planner workflow (Admin/Manager). Approval alone books nothing; " +
      "unify_apply_ai_workflow carries out an approved plan.",
    { workflowId: uuid("Workflow id") },
    WRITE,
    async ({ workflowId }) => client.request("POST", `/agent/workflow/${workflowId}/approve`),
  );

  tool(
    "unify_reject_ai_workflow",
    "Reject AI workflow",
    "Rejects a pending AI planner workflow with a reason (Admin/Manager).",
    { workflowId: uuid("Workflow id"), reason: z.string().min(3).max(1000).describe("Why it is rejected") },
    WRITE,
    async ({ workflowId, reason }) =>
      client.request("POST", `/agent/workflow/${workflowId}/reject`, { body: { reason } }),
  );

  tool(
    "unify_apply_ai_workflow",
    "Apply AI workflow",
    "Carries out an approved AI planner workflow, creating the bookings in its plan (Admin/Manager).",
    { workflowId: uuid("Workflow id") },
    WRITE,
    async ({ workflowId }) => client.request("POST", `/agent/workflow/${workflowId}/apply`),
  );

  tool(
    "unify_plan_schedule_with_ai",
    "Ask Unify's AI to plan bookings",
    "Asks Unify's own AI planner to propose a batch of bookings (e.g. 'fill next week's free dentist slots with " +
      "follow-ups'). It creates a workflow in PendingApproval; nothing is booked until it is approved and applied.",
    {
      objective: z.string().min(3),
      bookingTypeId: uuid("Booking type id"),
      dateFrom: z.string().describe("YYYY-MM-DD"),
      dateTo: z.string().describe("YYYY-MM-DD"),
      targetCount: z.number().int().min(1).max(200),
      resourceIds: z.array(z.string().uuid()).optional(),
      priorityRules: z.array(z.string()).optional(),
      branchId: optUuid("Branch id"),
    },
    WRITE,
    async (a) =>
      client.request("POST", "/agent/workflow/plan-schedule", {
        body: {
          tenantId: await client.tenantId(),
          objective: a.objective,
          bookingTypeId: a.bookingTypeId,
          dateFrom: toLocalDate(a.dateFrom, tz),
          dateTo: toLocalDate(a.dateTo, tz),
          targetCount: a.targetCount,
          resourceIds: a.resourceIds ?? null,
          priorityRules: a.priorityRules ?? null,
          branchId: a.branchId ?? null,
        },
      }),
  );

  tool(
    "unify_ask_workspace_assistant",
    "Ask the Unify workspace assistant",
    "Sends a question to the built-in Unify workspace assistant (the chat panel in the web app) and returns its answer.",
    { message: z.string().min(1).max(4000) },
    READ,
    async ({ message }) => client.request("POST", "/workspace-assistant/chat", { body: { message } }),
  );

  // ── Escape hatch ─────────────────────────────────────────────────────
  tool(
    "unify_api_get",
    "Read any Unify API endpoint",
    "Read-only GET request to the Unify REST API (endpoint reference: " +
      "https://sme-backend-lxsp.onrender.com/swagger), for data the other tools don't cover: equipment, " +
      "departures, sightings, subscriptions, purchase orders, suppliers, dynamic forms, school reports and so on. " +
      "path is relative to /api, e.g. '/departures/board' or '/inventory/movements'. Many list endpoints take " +
      "tenantId as a query parameter (from unify_whoami). Times in the query are UTC ISO strings.",
    {
      path: z.string().regex(/^\/?[A-Za-z0-9\-._~/{}%:]+$/, "A relative API path like /bookings/series"),
      query: z.record(z.union([z.string(), z.number(), z.boolean()])).optional(),
    },
    READ,
    async ({ path, query }) => {
      const p = path.startsWith("/") ? path : `/${path}`;
      if (/^\/(platform|auth)(\/|$)/i.test(p) && !/^\/auth\/me$/i.test(p)) {
        throw new Error("The platform-owner console and auth endpoints are not available through this connector.");
      }
      return client.request("GET", p, { query: query as Query });
    },
  );
}
