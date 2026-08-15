import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react';
import type {
  AgentWorkflow,
  AvailabilityDay,
  AvailabilitySearchResult,
  AvailableSlotsResponse,
  Booking,
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

const API_BASE_URL = 'http://localhost:5298/api';

export const bookingApi = createApi({
  reducerPath: 'bookingApi',
  baseQuery: fetchBaseQuery({
    baseUrl: API_BASE_URL,
    prepareHeaders: (headers) => {
      const token = localStorage.getItem('token');
      if (token) headers.set('Authorization', `Bearer ${token}`);
      return headers;
    },
  }),
  tagTypes: ['Booking', 'Resource', 'ResourceSchedule', 'BookingType', 'Conflicts', 'Branch', 'Staff', 'Workflow', 'Tenant', 'ScheduleException', 'Notification'],
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
    uploadMedia: builder.mutation<{ url: string; publicId: string }, { file: File; purpose: 'logo' | 'cover' | 'gallery' }>({
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
        result
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
    createBooking: builder.mutation<unknown, Partial<Booking> & {
      tenantId: string; resourceId: string; bookingTypeId: string; bookedBy: string;
      startTime: string; endTime: string; priority: string;
    }>({
      query: (body) => ({ url: '/bookings', method: 'POST', body }),
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }, { type: 'Conflicts', id: 'LIST' }],
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
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, { type: 'Conflicts', id: 'LIST' }],
    }),
    cancelBooking: builder.mutation<void, string>({
      query: (id) => ({ url: `/bookings/${id}/cancel`, method: 'PUT' }),
      invalidatesTags: (_r, _e, id) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }],
    }),
    updateBookingStatus: builder.mutation<unknown, { id: string; status: string }>({
      query: ({ id, status }) => ({ url: `/bookings/${id}/status`, method: 'PUT', body: { status } }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }, { type: 'Booking', id: 'MINE' }],
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
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }],
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
      invalidatesTags: [{ type: 'Booking', id: 'LIST' }],
    }),
    // FR-AS8: the logged-in doctor/staff member's own schedule.
    getMySchedule: builder.query<Booking[], { date?: string } | void>({
      query: (params) => ({ url: '/bookings/my-schedule', params: params ?? undefined }),
      providesTags: [{ type: 'Booking', id: 'MINE' }],
    }),
    checkInBooking: builder.mutation<{ message: string }, string>({
      query: (id) => ({ url: `/bookings/${id}/checkin`, method: 'POST' }),
      invalidatesTags: (_r, _e, id) => [{ type: 'Booking', id }, { type: 'Booking', id: 'LIST' }],
    }),
    getNoShowStats: builder.query<
      { total: number; noShows: number; completed: number; cancelled: number; noShowRate: number; utilizationRate: number },
      { tenantId: string; from: string; to: string }
    >({
      query: (params) => ({ url: '/bookings/reports/no-shows', params }),
    }),

    // ── Resources ─────────────────────────────────────────
    getResources: builder.query<
      PagedResult<Resource>,
      Partial<{ tenantId: string; branchId: string; category: string; status: string; search: string; specialty: string; page: number; pageSize: number }>
    >({
      query: (params) => ({ url: '/resources', params }),
      providesTags: (result) =>
        result
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
      invalidatesTags: (_r, _e, id) => [{ type: 'Workflow', id }, { type: 'Workflow', id: 'LIST' }, { type: 'Booking', id: 'LIST' }],
    }),
    reviseWorkflow: builder.mutation<AgentWorkflow, { id: string; plan: { steps: unknown[]; estimatedRevenueImpact: number } }>({
      query: ({ id, plan }) => ({ url: `/agent/workflow/${id}/revise`, method: 'POST', body: { plan } }),
      invalidatesTags: (_r, _e, { id }) => [{ type: 'Workflow', id }, { type: 'Workflow', id: 'LIST' }],
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
  useGetNoShowStatsQuery,
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
  useApproveWorkflowMutation,
  useRejectWorkflowMutation,
  useApplyWorkflowMutation,
} = bookingApi;
