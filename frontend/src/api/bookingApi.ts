import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react';
import type { BaseQueryFn, FetchArgs, FetchBaseQueryError } from '@reduxjs/toolkit/query/react';
import { API_BASE_URL, LOCAL_API_BASE_URL } from './apiBaseUrl';
import type {
  AgentWorkflow,
  AvailabilityDay,
  DepartureBoard,
  DepartureForecast,
  DepartureManifest,
  ExcursionKpis,
  RescheduleOption,
  SafetyPanel,
  Sighting,
  SightingAnalytics,
  TicketLine,
  WeatherObservation,
  AvailabilitySearchResult,
  AvailableSlotsResponse,
  Booking,
  ClinicAlert,
  ClinicFlow,
  ClinicOverview,
  ClinicOverviewParams,
  ClinicReminders,
  GymAttendance,
  SchoolOverview,
  SchoolOverviewParams,
  SchoolGradebook,
  SchoolStudentDetail,
  SchoolToday,
  GymLive,
  GymOverview,
  GymOverviewParams,
  RestaurantInventory,
  RestaurantLive,
  RestaurantOverview,
  RestaurantOverviewParams,
  BookingType,
  Branch,
  ConflictPair,
  DaySchedule,
  NotificationItem,
  PagedResult,
  Resource,
  ScheduleException,
  StaffUser,
  Tenant,
  TenantProfile,
  UpdateTenantProfileBody,
} from '../features/booking/types';

// Where the API is - see api/apiBaseUrl.ts for the rules.

const rawBaseQuery = fetchBaseQuery({
  baseUrl: API_BASE_URL,
  prepareHeaders: (headers) => {
    const token = localStorage.getItem('token');
    if (token) headers.set('Authorization', `Bearer ${token}`);
    return headers;
  },
});
const localBackendQuery = fetchBaseQuery({
  baseUrl: LOCAL_API_BASE_URL,
  prepareHeaders: (headers) => {
    const token = localStorage.getItem('token');
    if (token) headers.set('Authorization', `Bearer ${token}`);
    return headers;
  },
});

// Access tokens live 2 hours (JwtService.GenerateAccessToken) and there is no
// refresh endpoint to renew them, so a session simply dies mid-use. Without
// this wrapper RTK Query swallowed the resulting 401s: every page kept
// rendering the logged-in shell off the stale `user` object in localStorage
// while each table showed its "nothing found" empty state, which reads as
// missing data rather than an expired login. Drop the dead session and bounce
// to /login - the same thing axiosConfig.ts already does for the axios half
// of the app.
const baseQueryWithAuth: BaseQueryFn<string | FetchArgs, unknown, FetchBaseQueryError> = async (
  args,
  api,
  extraOptions,
) => {
  let result = await rawBaseQuery(args, api, extraOptions);
  if (result.error?.status === 'PARSING_ERROR' && API_BASE_URL === '/api') {
    result = await localBackendQuery(args, api, extraOptions);
  }
  // Guard on the token still being present so concurrent 401s (this page
  // fires several queries at once) only redirect once, and so a genuine 401
  // while already logged out can't loop us back into /login.
  if (result.error?.status === 401 && localStorage.getItem('token')) {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.location.href = '/login';
  }
  return result;
};

/* Every booking write also leaves a trail in the notification centre - the
 * customer's confirmation and the desk's tenant-wide copy - so a write that
 * does not invalidate these leaves the bell showing a stale count until its
 * next poll. Spread into each booking mutation's invalidatesTags. */
const NOTIFICATION_TAGS = [
  { type: 'Notification' as const, id: 'LIST' },
  { type: 'Notification' as const, id: 'COUNT' },
];

export const bookingApi = createApi({
  reducerPath: 'bookingApi',
  baseQuery: baseQueryWithAuth,
  tagTypes: ['Booking', 'Resource', 'ResourceSchedule', 'BookingType', 'Conflicts', 'Branch', 'Staff', 'Workflow', 'Tenant', 'ScheduleException', 'Notification', 'Departure', 'Sighting', 'Weather', 'Safety', 'RestaurantInventory'],
  endpoints: (builder) => ({
    // ── Branches ──────────────────────────────────────────
    getBranches: builder.query<Branch[], { tenantId: string }>({
      query: (params) => ({ url: '/branches', params }),
      providesTags: [{ type: 'Branch', id: 'LIST' }],
    }),
    createBranch: builder.mutation<Branch, { tenantId: string; name: string; address?: string; phone?: string }>({
      query: (body) => ({ url: '/branches', method: 'POST', body }),
      invalidatesTags: [{ type: 'Branch', id: 'LIST' }],
    }),
    updateBranch: builder.mutation<Branch, { id: string; body: Partial<Branch> & { isActive?: boolean } }>({
      query: ({ id, body }) => ({ url: `/branches/${id}`, method: 'PUT', body }),
      invalidatesTags: [{ type: 'Branch', id: 'LIST' }],
    }),
    deleteBranch: builder.mutation<void, string>({
      query: (id) => ({ url: `/branches/${id}`, method: 'DELETE' }),
      invalidatesTags: [{ type: 'Branch', id: 'LIST' }],
    }),

    // ── Tenant settings (FR-AS4/AS11) ──────────────────────
    getTenant: builder.query<Tenant, { tenantId: string }>({
      query: (params) => ({ url: '/tenant', params }),
      providesTags: [{ type: 'Tenant', id: 'CURRENT' }],
    }),
    updateTenant: builder.mutation<Tenant, Partial<Pick<Tenant, 'name' | 'logoUrl' | 'rescheduleCutoffHours' | 'cancellationCutoffHours' | 'subType'>>>({
      query: (body) => ({ url: '/tenant', method: 'PUT', body }),
      invalidatesTags: [{ type: 'Tenant', id: 'CURRENT' }],
    }),

    // ── Business Profile (shared, business-type-agnostic listing page) ──
    getTenantProfile: builder.query<TenantProfile, { tenantId: string }>({
      query: ({ tenantId }) => `/tenants/${tenantId}/profile`,
      providesTags: (_r, _e, { tenantId }) => [{ type: 'Tenant', id: tenantId }],
    }),
    updateTenantProfile: builder.mutation<TenantProfile, { tenantId: string; body: UpdateTenantProfileBody }>({
      query: ({ tenantId, body }) => ({ url: `/tenants/${tenantId}/profile`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { tenantId }) => [{ type: 'Tenant', id: tenantId }],
    }),
    setTenantLogo: builder.mutation<{ logoUrl: string }, { tenantId: string; imageUrl: string }>({
      query: ({ tenantId, imageUrl }) => ({ url: `/tenants/${tenantId}/logo`, method: 'PUT', body: { imageUrl } }),
      invalidatesTags: (_r, _e, { tenantId }) => [{ type: 'Tenant', id: tenantId }],
    }),
    setTenantCoverImage: builder.mutation<{ coverImageUrl: string }, { tenantId: string; imageUrl: string }>({
      query: ({ tenantId, imageUrl }) => ({ url: `/tenants/${tenantId}/cover-image`, method: 'PUT', body: { imageUrl } }),
      invalidatesTags: (_r, _e, { tenantId }) => [{ type: 'Tenant', id: tenantId }],
    }),
    addGalleryImage: builder.mutation<{ galleryImageUrls: string[] }, { tenantId: string; imageUrl: string }>({
      query: ({ tenantId, imageUrl }) => ({ url: `/tenants/${tenantId}/gallery-images`, method: 'POST', body: { imageUrl } }),
      invalidatesTags: (_r, _e, { tenantId }) => [{ type: 'Tenant', id: tenantId }],
    }),
    removeGalleryImage: builder.mutation<{ galleryImageUrls: string[] }, { tenantId: string; index: number }>({
      query: ({ tenantId, index }) => ({ url: `/tenants/${tenantId}/gallery-images/${index}`, method: 'DELETE' }),
      invalidatesTags: (_r, _e, { tenantId }) => [{ type: 'Tenant', id: tenantId }],
    }),
    reorderGalleryImages: builder.mutation<{ galleryImageUrls: string[] }, { tenantId: string; orderedUrls: string[] }>({
      query: ({ tenantId, orderedUrls }) => ({ url: `/tenants/${tenantId}/gallery-images/reorder`, method: 'PUT', body: { orderedUrls } }),
      invalidatesTags: (_r, _e, { tenantId }) => [{ type: 'Tenant', id: tenantId }],
    }),
    uploadMedia: builder.mutation<{ url: string; publicId: string }, { file: File; purpose: 'logo' | 'cover' | 'gallery' | 'avatar' }>({
      query: ({ file, purpose }) => {
        const formData = new FormData();
        formData.append('file', file);
        formData.append('purpose', purpose);
        return { url: '/media/upload', method: 'POST', body: formData };
      },
    }),
    deleteMedia: builder.mutation<void, { publicId: string }>({
      query: ({ publicId }) => ({ url: `/media/${encodeURIComponent(publicId)}`, method: 'DELETE' }),
    }),

    // ── Own profile (any authenticated role) ─────────────────
    updateMyProfile: builder.mutation<
      { id: string; fullName: string; phone: string; profilePictureUrl?: string | null },
      { fullName?: string; phone?: string; profilePictureUrl?: string }
    >({
      query: (body) => ({ url: '/auth/me', method: 'PUT', body }),
    }),

    // ── Staff management (FR-AS2) ──────────────────────────
    createStaff: builder.mutation<StaffUser, { email: string; password: string; fullName: string; phone?: string; branchId?: string; role: 'Staff' | 'Manager' }>({
      query: (body) => ({ url: '/tenant/staff', method: 'POST', body }),
      invalidatesTags: [{ type: 'Staff', id: 'LIST' }],
    }),
    updateStaffMember: builder.mutation<StaffUser, { id: string; branchId?: string | null; isActive?: boolean }>({
      query: ({ id, ...body }) => ({ url: `/tenant/staff/${id}`, method: 'PUT', body }),
      invalidatesTags: [{ type: 'Staff', id: 'LIST' }],
    }),

    // ── Notifications (FR-C11/FR-AS21) ─────────────────────
    getNotifications: builder.query<{ items: NotificationItem[]; total: number }, void>({
      query: () => '/notifications',
      providesTags: [{ type: 'Notification', id: 'LIST' }],
    }),
    getUnreadNotificationCount: builder.query<{ count: number }, void>({
      query: () => '/notifications/unread-count',
      providesTags: [{ type: 'Notification', id: 'COUNT' }],
    }),
    markNotificationRead: builder.mutation<void, string>({
      query: (id) => ({ url: `/notifications/${id}/read`, method: 'PUT' }),
      invalidatesTags: [{ type: 'Notification', id: 'LIST' }, { type: 'Notification', id: 'COUNT' }],
    }),

    // ── Bookings ──────────────────────────────────────────
    getBookings: builder.query<
      PagedResult<Booking>,
      Partial<{
        tenantId: string;
        type: string;
        resourceId: string;
        branchId: string;
        dateFrom: string;
        dateTo: string;
        status: string;
        page: number;
        pageSize: number;
      }>
    >({
      query: (params) => ({ url: '/bookings', params }),
      providesTags: (result) =>
        Array.isArray(result?.items)
          ? [...result.items.map((b) => ({ type: 'Booking' as const, id: b.id })), { type: 'Booking', id: 'LIST' }]
          : [{ type: 'Booking', id: 'LIST' }],
    }),
    // Note: GetById/Create/Update/Reschedule/UpdateStatus on the backend return the
    // raw EF entity (not the flattened list DTO with resourceName/bookingTypeName/
    // colorHex), so these are typed loosely — callers refetch the list via
    // invalidatesTags rather than reading fields off the mutation result.
    getBooking: builder.query<unknown, string>({
      query: (id) => `/bookings/${id}`,
      providesTags: (_r, _e, id) => [{ type: 'Booking', id }],
    }),
    // ticketBreakdown is asymmetric on purpose: the client POSTs an array
    // of { type, qty } and the server returns the priced jsonb *string* it
    // stored, so Booking's own string-typed field is omitted here rather
    // than widened - only the write side takes an array.
    createBooking: builder.mutation<
      { id: string; totalCost?: number | null; capacityWarning?: string | null },
      Omit<Partial<Booking>, 'ticketBreakdown'> & {
        tenantId: string; resourceId: string; bookingTypeId: string; bookedBy: string;
        startTime: string; endTime: string; priority: string;
        ticketBreakdown?: TicketLine[];
        departureId?: string;
        formData?: string;
      }
    >({
      query: (body) => ({ url: '/bookings', method: 'POST', body }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'Conflicts', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    updateBooking: builder.mutation<unknown, { id: string; body: Partial<Booking> }>({
      query: ({ id, body }) => ({ url: `/bookings/${id}`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }],
    }),
    deleteBooking: builder.mutation<void, string>({
      query: (id) => ({ url: `/bookings/${id}`, method: 'DELETE' }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    rescheduleBooking: builder.mutation<unknown, { id: string; newStartTime: string; newEndTime: string }>({
      query: ({ id, ...body }) => ({ url: `/bookings/${id}/reschedule`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, { type: 'Conflicts', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    cancelBooking: builder.mutation<void, string>({
      query: (id) => ({ url: `/bookings/${id}/cancel`, method: 'PUT' }),
      invalidatesTags: (_r, _e, id) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    updateBookingStatus: builder.mutation<unknown, { id: string; status: string }>({
      query: ({ id, status }) => ({ url: `/bookings/${id}/status`, method: 'PUT', body: { status } }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, { type: 'Booking', id: 'MINE' }, ...NOTIFICATION_TAGS],
    }),
    sendReminder: builder.mutation<{ message: string }, { id: string; channel: string }>({
      query: ({ id, channel }) => ({ url: `/bookings/${id}/remind`, method: 'POST', body: { channel } }),
    }),
    getAvailableSlots: builder.query<
      AvailableSlotsResponse,
      { resourceId: string; date: string; duration?: number; bookingTypeId?: string }
    >({
      query: (params) => ({ url: '/bookings/available-slots', params }),
    }),
    getConflicts: builder.query<{ totalConflicts: number; conflicts: ConflictPair[] }, { tenantId: string }>({
      query: (params) => ({ url: '/bookings/conflicts', params }),
      providesTags: [{ type: 'Conflicts', id: 'LIST' }],
    }),
    bulkSchedule: builder.mutation<any, { tenantId: string; bookings: any[] }>({
      query: (body) => ({ url: '/bookings/bulk-schedule', method: 'POST', body }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    createRecurringBooking: builder.mutation<
      | { totalRequested: number; created: number; skippedConflicts: number }
      | { message: string; workflowId: string; totalOccurrences: number },
      {
        tenantId: string; resourceId: string; bookingTypeId: string; bookedBy: string;
        title?: string; notes?: string; firstStartTime: string; durationMinutes: number;
        daysOfWeek?: number[]; endDate: string;
      }
    >({
      query: (body) => ({ url: '/bookings/recurring', method: 'POST', body }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    // FR-AS8: the logged-in doctor/staff member's own schedule.
    getMySchedule: builder.query<Booking[], { date?: string } | void>({
      query: (params) => ({ url: '/bookings/my-schedule', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'MINE' }],
    }),
    checkInBooking: builder.mutation<{ message: string }, string>({
      query: (id) => ({ url: `/bookings/${id}/checkin`, method: 'POST' }),
      invalidatesTags: (_r, _e, id) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    /* Spec 2.5's "revenue per slot": which hour of the day earns, not which
       resource earns. `tz` is minutes east of UTC so the hours are the
       operator's own clock, matching the dashboards' convention. */
    getRevenuePerSlot: builder.query<
      {
        totalRevenue: number; totalBookings: number; averagePerBooking: number; forgoneRevenue: number;
        busiestHour: number | null; richestHour: number | null;
        slots: { hour: number; label: string; bookings: number; earnedBookings: number; lostBookings: number; guests: number; revenue: number; averageValue: number; forgoneRevenue: number }[];
      },
      { tenantId: string; from: string; to: string; branchId?: string; tz?: number }
    >({
      query: (params) => ({ url: '/bookings/reports/revenue-per-slot', params }),
    }),
    /* Spec 2.3's AvailabilitySlots, made real: a business can now hold its
       capacity rather than only compute it. */
    getAvailabilitySlots: builder.query<
      {
        total: number; booked: number; free: number; utilisationPercent: number;
        days: { date: string; total: number; booked: number;
          slots: { id: string; date: string; startTime: string; endTime: string; isBooked: boolean; bookingId: string | null }[] }[];
      },
      { id: string; from: string; to: string; onlyFree?: boolean }
    >({
      query: ({ id, ...params }) => ({ url: `/resources/${id}/availability-slots`, params }),
      providesTags: (_r, _e, { id }) => [{ type: 'ResourceSchedule', id: `slots-${id}` }],
    }),
    generateAvailabilitySlots: builder.mutation<
      { created: number; skipped: number; days: number },
      { id: string; from: string; to: string; slotMinutes: number }
    >({
      query: ({ id, ...body }) => ({ url: `/resources/${id}/availability-slots/generate`, method: 'POST', body }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'ResourceSchedule', id: `slots-${id}` }],
    }),
    deleteAvailabilitySlots: builder.mutation<
      { removed: number; keptBecauseBooked: number },
      { id: string; from: string; to: string }
    >({
      query: ({ id, ...params }) => ({ url: `/resources/${id}/availability-slots`, method: 'DELETE', params }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'ResourceSchedule', id: `slots-${id}` }],
    }),

    /* Spec 2.3's RecurringPatterns, previously write-only. */
    getRecurringSeries: builder.query<
      {
        items: {
          patternId: string; anchorBookingId: string; title: string | null;
          resourceName: string | null; bookingTypeName: string | null; colorHex: string | null;
          frequency: string; daysOfWeek: number[]; endDate: string; startTime: string;
          total: number; remaining: number; cancelled: number; isActive: boolean;
        }[];
      },
      { tenantId: string }
    >({
      query: (params) => ({ url: '/bookings/series', params }),
      providesTags: [{ type: 'Booking', id: 'SERIES' }],
    }),
    cancelRecurringSeries: builder.mutation<{ cancelled: number }, string>({
      query: (patternId) => ({ url: `/bookings/series/${patternId}`, method: 'DELETE' }),
      invalidatesTags: [{ type: 'Booking', id: 'SERIES' }, { type: 'Booking', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    getNoShowStats: builder.query<
      { total: number; noShows: number; completed: number; cancelled: number; noShowRate: number; utilizationRate: number },
      { tenantId: string; from: string; to: string }
    >({
      query: (params) => ({ url: '/bookings/reports/no-shows', params }),
    }),

    // ── Departure operations (fixed-departure excursions) ────────
    // Only reached by sub-types whose registry config turns the departures
    // module on; every other tenant never issues these requests.
    getDepartureBoard: builder.query<DepartureBoard, { from?: string; days?: number }>({
      query: (params) => ({ url: '/departures/board', params }),
      providesTags: [{ type: 'Departure', id: 'LIST' }],
    }),
    getDepartureManifest: builder.query<DepartureManifest, string>({
      query: (id) => `/departures/${id}/manifest`,
      providesTags: (_r, _e, id) => [{ type: 'Departure', id }],
    }),
    createDeparture: builder.mutation<
      { id: string; scheduledDeparture: string },
      {
        resourceId: string; bookingTypeId?: string; scheduledDeparture: string;
        scheduledReturn?: string; captainUserId?: string; crew?: string;
        licensedCapacity?: number; notes?: string;
      }
    >({
      query: (body) => ({ url: '/departures', method: 'POST', body }),
      invalidatesTags: [{ type: 'Departure', id: 'LIST' }],
    }),
    updateDeparture: builder.mutation<
      unknown,
      { id: string; captainUserId?: string; crew?: string; licensedCapacity?: number; notes?: string }
    >({
      query: ({ id, ...body }) => ({ url: `/departures/${id}`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Departure', id }, { type: 'Departure', id: 'LIST' }],
    }),
    setDepartureStatus: builder.mutation<
      unknown,
      { id: string; status: string; reason?: string; overrideSafetyChecklist?: boolean }
    >({
      query: ({ id, ...body }) => ({ url: `/departures/${id}/status`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Departure', id }, { type: 'Departure', id: 'LIST' }],
    }),
    setSafetyChecklist: builder.mutation<
      unknown,
      { id: string; jacketsCounted: boolean; briefingDone: boolean; manifestClosed: boolean; weatherChecked: boolean }
    >({
      query: ({ id, ...body }) => ({ url: `/departures/${id}/safety-checklist`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Departure', id }, { type: 'Departure', id: 'LIST' }],
    }),
    cancelDepartureForWeather: builder.mutation<
      {
        departureId: string; status: string; bookingsCancelled: number;
        guestsNotified: number; rescheduleOptions: RescheduleOption[];
      },
      {
        id: string; reason?: string;
        weather?: { windSpeedKnots?: number; waveHeightMetres?: number; visibilityKm?: number; seaStateCode?: number; note?: string };
      }
    >({
      query: ({ id, ...body }) => ({ url: `/departures/${id}/cancel-weather`, method: 'POST', body }),
      invalidatesTags: [
        { type: 'Departure', id: 'LIST' }, { type: 'Booking', id: 'LIST' },
        { type: 'Weather', id: 'LIST' }, { type: 'Notification', id: 'LIST' },
      ],
    }),
    getRescheduleOptions: builder.query<RescheduleOption[], string>({
      query: (id) => `/departures/${id}/reschedule-options`,
    }),
    bulkRescheduleDeparture: builder.mutation<
      { movedCount: number; skippedCount: number; skipped: { bookingId: string; reason: string }[] },
      { id: string; targetDepartureId: string; bookingIds: string[] }
    >({
      query: ({ id, ...body }) => ({ url: `/departures/${id}/bulk-reschedule`, method: 'POST', body }),
      invalidatesTags: [{ type: 'Departure', id: 'LIST' }, { type: 'Booking', id: 'LIST' }],
    }),

    // ── Weather / sea-state console ───────────────────────
    getWeather: builder.query<
      { latest?: WeatherObservation | null; items: WeatherObservation[] },
      { departureId?: string; limit?: number } | void
    >({
      query: (params) => ({ url: '/departures/weather', params: params ?? undefined }),
      providesTags: [{ type: 'Weather', id: 'LIST' }],
    }),
    // Open-Meteo forecast for one departure. Fetched on demand rather than
    // polled: it is a third-party call, and a board showing twelve sailings
    // should not make twelve of them on a timer.
    getDepartureForecast: builder.query<DepartureForecast, string>({
      query: (departureId) => ({ url: `/departures/${departureId}/forecast` }),
      providesTags: (_r, _e, id) => [{ type: 'Weather', id }],
    }),
    recordWeather: builder.mutation<
      WeatherObservation,
      {
        resourceId?: string; departureId?: string; observedAt?: string;
        windSpeedKnots?: number; waveHeightMetres?: number; visibilityKm?: number;
        seaStateCode?: number; note?: string;
      }
    >({
      query: (body) => ({ url: '/departures/weather', method: 'POST', body }),
      invalidatesTags: [{ type: 'Weather', id: 'LIST' }, { type: 'Departure', id: 'LIST' }],
    }),

    // ── Safety & compliance ───────────────────────────
    getSafetyPanel: builder.query<SafetyPanel, { expiringWithinDays?: number } | void>({
      query: (params) => ({ url: '/departures/safety', params: params ?? undefined }),
      providesTags: [{ type: 'Safety', id: 'LIST' }],
    }),

    // ── Sightings ─────────────────────────────────
    getSightings: builder.query<
      { items: Sighting[]; total: number },
      { departureId?: string; resourceId?: string; species?: string; from?: string; to?: string; pageSize?: number }
    >({
      query: (params) => ({ url: '/sightings', params }),
      providesTags: [{ type: 'Sighting', id: 'LIST' }],
    }),
    logSighting: builder.mutation<
      Sighting,
      {
        departureId?: string; resourceId?: string; bookingId?: string;
        departureDateTime?: string; species: string; count?: number;
        locationLat?: number; locationLng?: number; behaviour?: string;
        notes?: string; photoUrls?: string;
      }
    >({
      query: (body) => ({ url: '/sightings', method: 'POST', body }),
      invalidatesTags: [
        { type: 'Sighting', id: 'LIST' }, { type: 'Sighting', id: 'ANALYTICS' },
        { type: 'Departure', id: 'LIST' },
      ],
    }),
    deleteSighting: builder.mutation<void, string>({
      query: (id) => ({ url: `/sightings/${id}`, method: 'DELETE' }),
      invalidatesTags: [{ type: 'Sighting', id: 'LIST' }, { type: 'Sighting', id: 'ANALYTICS' }],
    }),
    getSightingAnalytics: builder.query<
      SightingAnalytics,
      { from?: string; to?: string; species?: string } | void
    >({
      query: (params) => ({ url: '/sightings/analytics', params: params ?? undefined }),
      providesTags: [{ type: 'Sighting', id: 'ANALYTICS' }],
    }),
    getSightingVocabulary: builder.query<{ species: string[]; behaviours: string[] }, void>({
      query: () => '/sightings/vocabulary',
    }),

    // ── Per-ticket-type pricing ─────────────────────────
    quoteTickets: builder.mutation<
      {
        lines: TicketLine[]; totalQuantity: number; total: number; currency: string;
        seasonLabel?: string | null; isOffPeakRate: boolean;
        inSeason?: boolean | null; weatherDependent?: boolean | null;
      },
      { bookingTypeId: string; startTime: string; ticketBreakdown: TicketLine[] }
    >({
      query: (body) => ({ url: '/bookings/quote', method: 'POST', body }),
    }),
    setBookingTickets: builder.mutation<
      { totalCost: number; currency: string; capacityWarning?: string | null },
      { id: string; ticketBreakdown: TicketLine[] }
    >({
      query: ({ id, ticketBreakdown }) => ({ url: `/bookings/${id}/tickets`, method: 'PUT', body: { ticketBreakdown } }),
      invalidatesTags: (_r, _e, { id }) => [
        { type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, { type: 'Departure', id: 'LIST' },
      ],
    }),
    setBookingWaiver: builder.mutation<
      unknown,
      { id: string; signerName: string; signedAt?: string; minorCount?: number }
    >({
      query: ({ id, ...body }) => ({ url: `/bookings/${id}/waiver`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { id }) => [
        { type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, { type: 'Departure', id: 'LIST' },
      ],
    }),

    // ── Excursion reports ─────────────────────────────
    getExcursionKpis: builder.query<ExcursionKpis, { on?: string; forwardDays?: number } | void>({
      query: (params) => ({ url: '/reports/excursions/kpis', params: params ?? undefined }),
      providesTags: [{ type: 'Departure', id: 'KPIS' }],
    }),
    getRevenueByTicketType: builder.query<
      {
        byTicketType: { ticketType: string; quantity: number; revenue: number }[];
        unbrokenDownRevenue: number; totalRevenue: number; totalTickets: number;
      },
      { from?: string; to?: string }
    >({
      query: (params) => ({ url: '/reports/excursions/revenue-by-ticket-type', params }),
    }),
    getPerDepartureReport: builder.query<
      {
        departures: {
          departureId: string; vesselName: string; scheduledDeparture: string; status: string;
          capacity: number; pax: number; occupancyPercent: number; revenue: number;
          revenuePerSeat: number; bookings: number; sightings: number;
        }[];
        totalRevenue: number; averageOccupancyPercent: number;
      },
      { from?: string; to?: string }
    >({
      query: (params) => ({ url: '/reports/excursions/per-departure', params }),
    }),
    getWeatherCancellationReport: builder.query<
      {
        totalCancelled: number; totalBookingsAffected: number;
        totalRefundableAmount: number; totalRebooked: number;
        byMonth: { month: string; label: string; count: number }[];
        departures: {
          departureId: string; vesselName: string; scheduledDeparture: string;
          cancellationReason?: string | null; bookingsAffected: number;
          refundableAmount: number; paxAffected: number; rebookedCount: number;
        }[];
      },
      { from?: string; to?: string }
    >({
      query: (params) => ({ url: '/reports/excursions/weather-cancellations', params }),
    }),
    getChannelSplit: builder.query<
      {
        byChannel: { channel: string; bookings: number; pax: number; revenue: number }[];
        byNationality: { nationality: string; bookings: number }[];
        nationalityCaptured: boolean;
      },
      { from?: string; to?: string }
    >({
      query: (params) => ({ url: '/reports/excursions/channel-split', params }),
    }),

    // ── Clinic operations dashboard ─────────────────────
    // All four carry the Booking LIST tag: a check-in, a status change or
    // a reminder sent from the flow board invalidates that tag already, so
    // the waiting room and the alerts refresh without extra wiring.
    getClinicOverview: builder.query<ClinicOverview, ClinicOverviewParams | void>({
      query: (params) => ({ url: '/reports/clinic/overview', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getClinicFlow: builder.query<ClinicFlow, { on?: string; branchId?: string; resourceId?: string } | void>({
      query: (params) => ({ url: '/reports/clinic/flow', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getClinicAlerts: builder.query<{ asOf: string; alerts: ClinicAlert[] }, { branchId?: string } | void>({
      query: (params) => ({ url: '/reports/clinic/alerts', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getClinicReminders: builder.query<ClinicReminders, { withinHours?: number; branchId?: string } | void>({
      query: (params) => ({ url: '/reports/clinic/reminders', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),

    // ── Restaurant operations dashboard ─────────────────
    // Same tagging as the clinic: Booking LIST so an order moved along the
    // feed refreshes the KPIs, kitchen board and alerts. Inventory carries
    // its own tag so logging waste refreshes only the stock panel.
    getRestaurantOverview: builder.query<RestaurantOverview, RestaurantOverviewParams | void>({
      query: (params) => ({ url: '/reports/restaurant/overview', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'RestaurantInventory', id: 'LIST' }],
    }),
    getRestaurantLive: builder.query<RestaurantLive, { on?: string; branchId?: string; resourceId?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/restaurant/live', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getRestaurantAlerts: builder.query<{ asOf: string; alerts: ClinicAlert[] }, { branchId?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/restaurant/alerts', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'RestaurantInventory', id: 'LIST' }],
    }),
    getRestaurantInventory: builder.query<RestaurantInventory, { from?: string; to?: string; branchId?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/restaurant/inventory', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'RestaurantInventory', id: 'LIST' }],
    }),
    logInventoryWaste: builder.mutation<unknown, { id: string; quantity: number; reason?: string; notes?: string; reference?: string }>({
      query: ({ id, ...body }) => ({ url: `/inventory/${id}/waste`, method: 'POST', body }),
      invalidatesTags: [{ type: 'RestaurantInventory', id: 'LIST' }],
    }),

    // ── Gym / fitness operations dashboard ──────────────
    getGymOverview: builder.query<GymOverview, GymOverviewParams | void>({
      query: (params) => ({ url: '/reports/gym/overview', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getGymLive: builder.query<GymLive, { branchId?: string; resourceId?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/gym/live', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getGymAttendance: builder.query<GymAttendance, { from?: string; to?: string; branchId?: string; resourceId?: string; search?: string; method?: string; page?: number; pageSize?: number; tz?: number } | void>({
      query: (params) => ({ url: '/reports/gym/attendance', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getGymAlerts: builder.query<{ asOf: string; alerts: ClinicAlert[] }, { branchId?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/gym/alerts', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),

    // ── School / tuition-centre dashboard ───────────────
    // Marking attendance or entering a grade invalidates Booking LIST, so
    // the timetable, KPIs and at-risk list refresh together.
    getSchoolOverview: builder.query<SchoolOverview, SchoolOverviewParams | void>({
      query: (params) => ({ url: '/reports/school/overview', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'Staff', id: 'LIST' }],
    }),
    getSchoolToday: builder.query<SchoolToday, { on?: string; branchId?: string; resourceId?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/school/today', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'Staff', id: 'LIST' }],
    }),
    getSchoolStudent: builder.query<SchoolStudentDetail, { id: string; from?: string; to?: string; tz?: number }>({
      query: ({ id, ...params }) => ({ url: `/reports/school/students/${id}`, params }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getSchoolGradebook: builder.query<SchoolGradebook, { from?: string; to?: string; branchId?: string; bookingTypeId?: string; grade?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/school/gradebook', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    getSchoolAlerts: builder.query<{ asOf: string; alerts: ClinicAlert[] }, { branchId?: string; tz?: number } | void>({
      query: (params) => ({ url: '/reports/school/alerts', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'Staff', id: 'LIST' }],
    }),
    markSchoolAttendance: builder.mutation<unknown, { bookingId: string; mark: string; points?: number | null; note?: string | null }>({
      query: (body) => ({ url: '/reports/school/attendance', method: 'POST', body }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    approveSchoolUser: builder.mutation<unknown, { userId: string; role?: string }>({
      query: (body) => ({ url: '/reports/school/approve', method: 'POST', body }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'Staff', id: 'LIST' }],
    }),
    gradeSchoolAssessment: builder.mutation<unknown, { bookingId: string; score: number | null; maxScore?: number | null; feedback?: string | null }>({
      query: (body) => ({ url: '/reports/school/grade', method: 'POST', body }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }],
    }),

    // ── Resources ─────────────────────────────────────────
    getResources: builder.query<
      PagedResult<Resource>,
      Partial<{ tenantId: string; branchId: string; category: string; status: string; search: string; specialty: string; page: number; pageSize: number }>
    >({
      query: (params) => ({ url: '/resources', params }),
      providesTags: (result) =>
        Array.isArray(result?.items)
          ? [...result.items.map((r) => ({ type: 'Resource' as const, id: r.id })), { type: 'Resource', id: 'LIST' }]
          : [{ type: 'Resource', id: 'LIST' }],
    }),
    // FR-B1: combined branch + specialty + date availability search
    searchAvailability: builder.query<
      { date: string; results: AvailabilitySearchResult[] },
      Partial<{ tenantId: string; branchId: string; specialty: string; bookingTypeId: string; duration: number }> & { date: string }
    >({
      query: (params) => ({ url: '/resources/search-availability', params }),
    }),
    createResource: builder.mutation<Resource, Partial<Resource> & { tenantId: string; name: string }>({
      query: (body) => ({ url: '/resources', method: 'POST', body }),
      invalidatesTags: [{ type: 'Resource', id: 'LIST' }],
    }),
    updateResource: builder.mutation<Resource, { id: string; body: Partial<Resource> }>({
      query: ({ id, body }) => ({ url: `/resources/${id}`, method: 'PUT', body }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Resource', id }, { type: 'Resource', id: 'LIST' }],
    }),
    deleteResource: builder.mutation<void, string>({
      query: (id) => ({ url: `/resources/${id}`, method: 'DELETE' }),
      invalidatesTags: [{ type: 'Resource', id: 'LIST' }],
    }),
    getResourceSchedule: builder.query<DaySchedule[], string>({
      query: (id) => `/resources/${id}/schedule`,
      providesTags: (_r, _e, id) => [{ type: 'ResourceSchedule', id }],
    }),
    setResourceSchedule: builder.mutation<{ message: string }, { id: string; days: DaySchedule[] }>({
      query: ({ id, days }) => ({ url: `/resources/${id}/schedule`, method: 'PUT', body: { days } }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'ResourceSchedule', id }],
    }),
    getAvailabilityGrid: builder.query<AvailabilityDay[], { id: string; from: string; to: string }>({
      query: ({ id, from, to }) => ({ url: `/resources/${id}/availability-grid`, params: { from, to } }),
    }),

    // FR-AS6: one-off closed dates (holidays/closures) on top of the weekly hours.
    getScheduleExceptions: builder.query<ScheduleException[], string>({
      query: (resourceId) => `/resources/${resourceId}/schedule-exceptions`,
      providesTags: (_r, _e, resourceId) => [{ type: 'ScheduleException', id: resourceId }],
    }),
    addScheduleException: builder.mutation<ScheduleException, { resourceId: string; date: string; reason?: string }>({
      query: ({ resourceId, ...body }) => ({ url: `/resources/${resourceId}/schedule-exceptions`, method: 'POST', body }),
      invalidatesTags: (_r, _e, { resourceId }) => [{ type: 'ScheduleException', id: resourceId }],
    }),
    removeScheduleException: builder.mutation<void, { resourceId: string; exceptionId: string }>({
      query: ({ resourceId, exceptionId }) => ({ url: `/resources/${resourceId}/schedule-exceptions/${exceptionId}`, method: 'DELETE' }),
      invalidatesTags: (_r, _e, { resourceId }) => [{ type: 'ScheduleException', id: resourceId }],
    }),

    // ── Booking Types ─────────────────────────────────────
    getBookingTypes: builder.query<BookingType[], { tenantId: string; status?: string }>({
      query: (params) => ({ url: '/bookingtypes', params }),
      providesTags: [{ type: 'BookingType', id: 'LIST' }],
    }),
    createBookingType: builder.mutation<BookingType, Partial<BookingType> & { tenantId: string; name: string }>({
      query: (body) => ({ url: '/bookingtypes', method: 'POST', body }),
      invalidatesTags: [{ type: 'BookingType', id: 'LIST' }],
    }),
    updateBookingType: builder.mutation<BookingType, { id: string; body: Partial<BookingType> }>({
      query: ({ id, body }) => ({ url: `/bookingtypes/${id}`, method: 'PUT', body }),
      invalidatesTags: [{ type: 'BookingType', id: 'LIST' }],
    }),
    deleteBookingType: builder.mutation<void, string>({
      query: (id) => ({ url: `/bookingtypes/${id}`, method: 'DELETE' }),
      invalidatesTags: [{ type: 'BookingType', id: 'LIST' }],
    }),

    // ── Staff directory (for linking a doctor resource to a login) ────────
    getStaffUsers: builder.query<StaffUser[], { tenantId: string; includeInactive?: boolean }>({
      query: (params) => ({ url: '/tenant/staff', params }),
      providesTags: [{ type: 'Staff', id: 'LIST' }],
    }),

    // ── Agent workflows (FR-B12: planner propose/approve/apply) ───────────
    // ── Customer side (mirrors the Flutter customer screens) ──
    getMyWorkflows: builder.query<AgentWorkflow[], void>({
      query: () => '/agent/workflow/mine',
      providesTags: [{ type: 'Workflow', id: 'MINE' }],
    }),
    findAndBook: builder.mutation<
      { workflowId: string; status: string; bookingId?: string | null; message?: string | null },
      { objective: string; dateFrom?: string; dateTo?: string; extraConstraints?: Record<string, unknown> }
    >({
      query: (body) => ({ url: '/agent/find-and-book', method: 'POST', body }),
      invalidatesTags: [{ type: 'Workflow', id: 'MINE' }, { type: 'Booking', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    getUnavailableRanges: builder.query<{ startTime: string; endTime: string }[], { resourceId: string; from: string; to: string }>({
      query: (params) => ({ url: '/bookings/unavailable-ranges', params }),
      providesTags: [{ type: 'Booking', id: 'LIST' }],
    }),

    getWorkflows: builder.query<AgentWorkflow[], { tenantId: string; status?: string }>({
      query: (params) => ({ url: '/agent/workflow', params }),
      providesTags: (result) =>
        result
          ? [...result.map((w) => ({ type: 'Workflow' as const, id: w.id })), { type: 'Workflow', id: 'LIST' }]
          : [{ type: 'Workflow', id: 'LIST' }],
    }),
    proposeSchedule: builder.mutation<
      AgentWorkflow,
      { tenantId: string; objective: string; count: number; bookingTypeId: string; branchId?: string; withinDays?: number }
    >({
      query: (body) => ({ url: '/agent/workflow/propose', method: 'POST', body }),
      invalidatesTags: [{ type: 'Workflow', id: 'LIST' }],
    }),
    // Schedule Copilot (spec 2.7): runs the four-agent workflow and returns
    // the stored workflow together with the agents' full trace.
    planSchedule: builder.mutation<
      { workflow: AgentWorkflow; trace: unknown },
      {
        tenantId: string;
        objective: string;
        bookingTypeId: string;
        dateFrom: string;
        dateTo: string;
        targetCount: number;
        resourceIds?: string[];
        priorityRules?: string[];
        branchId?: string;
      }
    >({
      query: (body) => ({ url: '/agent/workflow/plan-schedule', method: 'POST', body }),
      invalidatesTags: [{ type: 'Workflow', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    approveWorkflow: builder.mutation<{ message: string }, string>({
      query: (id) => ({ url: `/agent/workflow/${id}/approve`, method: 'POST' }),
      invalidatesTags: (_r, _e, id) => [{ type: 'Workflow', id }, { type: 'Workflow', id: 'LIST' }],
    }),
    rejectWorkflow: builder.mutation<{ message: string }, { id: string; reason: string }>({
      query: ({ id, reason }) => ({ url: `/agent/workflow/${id}/reject`, method: 'POST', body: { reason } }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Workflow', id }, { type: 'Workflow', id: 'LIST' }],
    }),
    applyWorkflow: builder.mutation<{ message: string; created: number; skipped: number }, string>({
      query: (id) => ({ url: `/agent/workflow/${id}/apply`, method: 'POST' }),
      invalidatesTags: (_r, _e, id) => [{ type: 'Workflow', id }, { type: 'Workflow', id: 'LIST' }, { type: 'Booking', id: 'LIST' }, ...NOTIFICATION_TAGS],
    }),
    reviseWorkflow: builder.mutation<AgentWorkflow, { id: string; plan: { steps: unknown[]; estimatedRevenueImpact: number } }>({
      query: ({ id, plan }) => ({ url: `/agent/workflow/${id}/revise`, method: 'POST', body: { plan } }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Workflow', id }, { type: 'Workflow', id: 'LIST' }],
    }),
    askWorkspaceAssistant: builder.mutation<{ answer: string; answeredAt: string }, { message: string }>({
      query: (body) => ({ url: '/workspace-assistant/chat', method: 'POST', body }),
    }),
  }),
});

export const {
  useGetBranchesQuery,
  useCreateBranchMutation,
  useUpdateBranchMutation,
  useDeleteBranchMutation,
  useGetTenantQuery,
  useUpdateTenantMutation,
  useCreateStaffMutation,
  useUpdateStaffMemberMutation,
  useGetNotificationsQuery,
  useGetUnreadNotificationCountQuery,
  useMarkNotificationReadMutation,
  useGetMyScheduleQuery,
  useCheckInBookingMutation,
  useGetScheduleExceptionsQuery,
  useAddScheduleExceptionMutation,
  useRemoveScheduleExceptionMutation,
  useReviseWorkflowMutation,
  useGetTenantProfileQuery,
  useUpdateTenantProfileMutation,
  useSetTenantLogoMutation,
  useSetTenantCoverImageMutation,
  useAddGalleryImageMutation,
  useRemoveGalleryImageMutation,
  useReorderGalleryImagesMutation,
  useUploadMediaMutation,
  useDeleteMediaMutation,
  useUpdateMyProfileMutation,
  useGetBookingsQuery,
  useGetBookingQuery,
  useCreateBookingMutation,
  useUpdateBookingMutation,
  useDeleteBookingMutation,
  useRescheduleBookingMutation,
  useCancelBookingMutation,
  useUpdateBookingStatusMutation,
  useSendReminderMutation,
  useGetAvailableSlotsQuery,
  useLazyGetAvailableSlotsQuery,
  useGetConflictsQuery,
  useBulkScheduleMutation,
  useGetAvailabilitySlotsQuery,
  useGenerateAvailabilitySlotsMutation,
  useDeleteAvailabilitySlotsMutation,
  useGetRecurringSeriesQuery,
  useCancelRecurringSeriesMutation,
  useGetNoShowStatsQuery,
  useGetRevenuePerSlotQuery,
  useGetDepartureBoardQuery,
  useGetDepartureManifestQuery,
  useCreateDepartureMutation,
  useUpdateDepartureMutation,
  useSetDepartureStatusMutation,
  useSetSafetyChecklistMutation,
  useCancelDepartureForWeatherMutation,
  useGetRescheduleOptionsQuery,
  useBulkRescheduleDepartureMutation,
  useGetWeatherQuery,
  useGetDepartureForecastQuery,
  useLazyGetDepartureForecastQuery,
  useRecordWeatherMutation,
  useGetSafetyPanelQuery,
  useGetSightingsQuery,
  useLogSightingMutation,
  useDeleteSightingMutation,
  useGetSightingAnalyticsQuery,
  useGetSightingVocabularyQuery,
  useQuoteTicketsMutation,
  useSetBookingTicketsMutation,
  useSetBookingWaiverMutation,
  useGetExcursionKpisQuery,
  useGetClinicOverviewQuery,
  useGetClinicFlowQuery,
  useGetClinicAlertsQuery,
  useGetClinicRemindersQuery,
  useGetRestaurantOverviewQuery,
  useGetRestaurantLiveQuery,
  useGetRestaurantAlertsQuery,
  useGetRestaurantInventoryQuery,
  useLogInventoryWasteMutation,
  useGetGymOverviewQuery,
  useGetGymLiveQuery,
  useGetGymAttendanceQuery,
  useGetGymAlertsQuery,
  useGetSchoolOverviewQuery,
  useGetSchoolTodayQuery,
  useGetSchoolStudentQuery,
  useGetSchoolAlertsQuery,
  useGetSchoolGradebookQuery,
  useMarkSchoolAttendanceMutation,
  useGradeSchoolAssessmentMutation,
  useApproveSchoolUserMutation,
  useGetMyWorkflowsQuery,
  useFindAndBookMutation,
  useGetUnavailableRangesQuery,
  useGetRevenueByTicketTypeQuery,
  useGetPerDepartureReportQuery,
  useGetWeatherCancellationReportQuery,
  useGetChannelSplitQuery,
  useGetResourcesQuery,
  useCreateResourceMutation,
  useUpdateResourceMutation,
  useDeleteResourceMutation,
  useGetResourceScheduleQuery,
  useSetResourceScheduleMutation,
  useGetAvailabilityGridQuery,
  useGetBookingTypesQuery,
  useCreateBookingTypeMutation,
  useUpdateBookingTypeMutation,
  useDeleteBookingTypeMutation,
  useCreateRecurringBookingMutation,
  useSearchAvailabilityQuery,
  useGetStaffUsersQuery,
  useGetWorkflowsQuery,
  useProposeScheduleMutation,
  usePlanScheduleMutation,
  useApproveWorkflowMutation,
  useRejectWorkflowMutation,
  useApplyWorkflowMutation,
  useAskWorkspaceAssistantMutation,
} = bookingApi;
