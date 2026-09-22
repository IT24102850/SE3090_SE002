export type BookingStatus =
  | 'Pending'
  | 'Confirmed'
  | 'CheckedIn'
  | 'InProgress'
  | 'Completed'
  | 'Cancelled'
  | 'NoShow'
  | 'Rejected'
  // Set by the weather-cancel flow, never by a guest. Kept apart from
  // Cancelled so weather losses do not read as churn in the reports.
  | 'WeatherCancelled';

export type BookingPriority = 'Low' | 'Normal' | 'High' | 'Urgent';

export type ResourceCategory = 'Room' | 'Equipment' | 'Vehicle' | 'Staff' | 'Desk' | 'Other';
export type ResourceStatus = 'Available' | 'UnderMaintenance' | 'Archived' | 'Reserved';

export interface Booking {
  id: string;
  tenantId: string;
  resourceId: string;
  resourceName: string;
  bookingTypeId: string;
  bookingTypeName: string;
  colorHex: string;
  bookedBy: string;
  bookedFor?: string | null;
  title?: string | null;
  notes?: string | null;
  startTime: string;
  endTime: string;
  status: BookingStatus;
  priority: BookingPriority;
  attendeeCount?: number | null;
  totalCost?: number | null;
  createdAt: string;
  checkInAt?: string | null;
  /** Set when the consultation begins (status -> InProgress). */
  consultationStartedAt?: string | null;
  /** Set when the visit completes (status -> Completed). */
  checkOutAt?: string | null;
  // Fixed-departure excursion fields. All optional - a booking that has
  // none of them renders exactly as it did before they existed.
  departureId?: string | null;
  /** Raw jsonb: TicketLine[]. Parse with parseTicketBreakdown below. */
  ticketBreakdown?: string | null;
  /** Raw jsonb: { signedAt, signerName, minorCount }. */
  waiver?: string | null;
  source?: string | null;
}

// ── Fixed-departure excursion types (whale watching, safari) ──────────

export interface TicketLine {
  type: string;
  qty: number;
  unitPrice?: number | null;
  lineTotal?: number | null;
}

export const TICKET_TYPES = ['Adult', 'Child', 'Infant'] as const;

/** Parses Booking.ticketBreakdown. Returns [] for null/blank/malformed
 *  jsonb, so a bad row degrades one card rather than the whole board. */
export function parseTicketBreakdown(json?: string | null): TicketLine[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? (parsed as TicketLine[]).filter((l) => l && l.qty > 0) : [];
  } catch {
    return [];
  }
}

export interface WaiverState {
  signedAt?: string | null;
  signerName?: string | null;
  minorCount?: number | null;
}

export function parseWaiver(json?: string | null): WaiverState | null {
  if (!json) return null;
  try {
    return JSON.parse(json) as WaiverState;
  } catch {
    return null;
  }
}

export type DepartureStatus =
  | 'Scheduled'
  | 'Boarding'
  | 'AtSea'
  | 'Returned'
  | 'CancelledWeather'
  | 'CancelledOther';

export const DEPARTURE_STATUS_COLORS: Record<DepartureStatus, { bg: string; label: string }> = {
  Scheduled: { bg: '#2563EB', label: 'Scheduled' },
  Boarding: { bg: '#FBBF24', label: 'Boarding' },
  AtSea: { bg: '#22D3EE', label: 'At sea' },
  Returned: { bg: '#4ADE80', label: 'Returned' },
  CancelledWeather: { bg: '#38BDF8', label: 'Weather-cancelled' },
  CancelledOther: { bg: '#7C7C85', label: 'Cancelled' },
};

export interface WeatherObservation {
  id: string;
  resourceId?: string | null;
  departureId?: string | null;
  observedAt: string;
  windSpeedKnots?: number | null;
  waveHeightMetres?: number | null;
  visibilityKm?: number | null;
  seaStateCode?: number | null;
  note?: string | null;
  source: string;
}

export interface SafetyChecklist {
  jacketsCounted?: boolean;
  briefingDone?: boolean;
  manifestClosed?: boolean;
  weatherChecked?: boolean;
  completedAt?: string | null;
  completedBy?: string | null;
}

export function parseSafetyChecklist(json?: string | null): SafetyChecklist {
  if (!json) return {};
  try {
    return JSON.parse(json) as SafetyChecklist;
  } catch {
    return {};
  }
}

export interface CrewMember {
  userId?: string | null;
  name: string;
  role?: string | null;
}

export function parseCrew(json?: string | null): CrewMember[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? (parsed as CrewMember[]) : [];
  } catch {
    return [];
  }
}

export interface DepartureSummary {
  id: string;
  resourceId: string;
  vesselName: string;
  bookingTypeId?: string | null;
  bookingTypeName?: string | null;
  scheduledDeparture: string;
  scheduledReturn: string;
  durationMinutes: number;
  status: DepartureStatus;
  captainUserId?: string | null;
  crew?: string | null;
  safetyChecklist?: string | null;
  safetyChecklistComplete: boolean;
  capacity: number;
  paxBooked: number;
  seatsRemaining: number;
  occupancyPercent: number;
  nearCapacity: boolean;
  ticketMix: Record<string, number>;
  bookingCount: number;
  checkedInCount: number;
  waiverCompletionPercent: number;
  revenue: number;
  sightingCount: number;
  cancellationReason?: string | null;
  latestWeather?: WeatherObservation | null;
}

export interface DepartureBoard {
  from: string;
  to: string;
  today: DepartureSummary[];
  upcoming: DepartureSummary[];
}

export interface ManifestPassenger {
  bookingId: string;
  guestName: string;
  guestEmail?: string | null;
  guestPhone?: string | null;
  seats: number;
  tickets: TicketLine[];
  status: BookingStatus;
  source?: string | null;
  checkedIn: boolean;
  checkInAt?: string | null;
  noShow: boolean;
  waiverSigned: boolean;
  waiverSignerName?: string | null;
  minorCount: number;
  totalCost?: number | null;
  notes?: string | null;
}

export interface DepartureManifest {
  departure: DepartureSummary;
  passengers: ManifestPassenger[];
  waiverCompletionPercent: number;
  checkedInCount: number;
  noShowCount: number;
}

export interface Sighting {
  id: string;
  resourceId: string;
  departureId?: string | null;
  bookingId?: string | null;
  departureDateTime: string;
  species: string;
  count?: number | null;
  locationLat?: number | null;
  locationLng?: number | null;
  behaviour?: string | null;
  notes?: string | null;
  photoUrls?: string | null;
  loggedByUserId?: string | null;
  createdAt: string;
}

export interface SightingAnalytics {
  from: string;
  to: string;
  speciesFilter?: string | null;
  departuresSailed: number;
  departuresWithSighting: number;
  successRate: number;
  totalSightings: number;
  totalIndividuals: number;
  speciesFrequency: { species: string; sightings: number; individuals: number }[];
  monthly: {
    month: string;
    label: string;
    departures: number;
    departuresWithSighting: number;
    successRate: number;
    totalSightings: number;
    bySpecies: Record<string, number>;
  }[];
}

export interface ExcursionKpis {
  asOf: string;
  seasonStart: string;
  departuresToday: number;
  departuresTodayByStatus: Record<string, number>;
  paxBookedToday: number;
  capacityToday: number;
  occupancyTodayPercent: number;
  sightingSuccessRate: number;
  departuresSailedSeasonToDate: number;
  departuresWithSightingSeasonToDate: number;
  revenueToday: number;
  weatherCancelledThisMonth: number;
  waiverCompletionPercent: number;
  checkedInToday: number;
  forwardDays: number;
  nextDaysOccupancyPercent: number;
  nextDaysPax: number;
  nextDaysCapacity: number;
}

export interface SafetyPanel {
  vessels: {
    resourceId: string;
    vesselName: string;
    licensedCapacity: number;
    lifeJacketCount: number;
    lifeJacketShortfall: number;
    jacketsSufficient: boolean;
    equipment: SafetyGearItem[];
  }[];
  sharedEquipment: SafetyGearItem[];
  expiredCount: number;
  expiringSoonCount: number;
}

export interface SafetyGearItem {
  equipmentItemId: string;
  name: string;
  category: string;
  quantity: number;
  expiryDate?: string | null;
  isExpired: boolean;
  isExpiringSoon: boolean;
}

export interface RescheduleOption {
  departureId: string;
  vesselName: string;
  scheduledDeparture: string;
  capacity: number;
  seatsTaken: number;
  seatsRemaining: number;
}

export interface PagedResult<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export interface Branch {
  id: string;
  name: string;
  address?: string | null;
  phone?: string | null;
}

export interface Resource {
  id: string;
  tenantId: string;
  branchId?: string | null;
  name: string;
  code?: string | null;
  category: ResourceCategory;
  status: ResourceStatus;
  description?: string | null;
  capacity?: number | null;
  hourlyRate?: number | null;
  specialty?: string | null;
  linkedUserId?: string | null;
  customAttributes?: string | null;
  createdAt: string;
}

export interface StaffUser {
  id: string;
  fullName: string;
  email: string;
  phone?: string | null;
  branchId?: string | null;
  isActive?: boolean;
  role: 'Manager' | 'Staff';
}

export interface Tenant {
  id: string;
  name: string;
  businessType: string;
  subType?: string | null;
  logoUrl?: string | null;
  isActive: boolean;
  rescheduleCutoffHours: number;
  cancellationCutoffHours: number;
}

// Shared, business-type-agnostic profile shell (TenantProfileController) -
// works identically for a clinic, a restaurant, or a dive center. Nothing
// here is Tourism/sub-type-specific; that content lives entirely in
// BookingType, a separate concern.
export interface BusinessHourEntry {
  dayOfWeek: string; // "Monday" .. "Sunday"
  openTime: string | null; // "HH:mm"
  closeTime: string | null;
  isClosed: boolean;
}

export interface TenantProfile {
  tenantId: string;
  name: string;
  businessType: string;
  logoUrl?: string | null;
  coverImageUrl?: string | null;
  galleryImageUrls: string[];
  description?: string | null;
  shortTagline?: string | null;
  amenities: string[];
  contactPhone?: string | null;
  contactEmail?: string | null;
  website?: string | null;
  socialLinks: Record<string, string>;
  businessHours: BusinessHourEntry[];
  averageRating?: number | null;
  reviewCount: number;
  address?: string | null;
}

export interface UpdateTenantProfileBody {
  description?: string;
  shortTagline?: string;
  amenities?: string[];
  contactPhone?: string;
  contactEmail?: string;
  website?: string;
  socialLinks?: Record<string, string>;
  businessHours?: BusinessHourEntry[];
}

export const DAYS_OF_WEEK = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

export const TOURISM_SUB_TYPES = [
  'Water sports / diving',
  'Safari / wildlife',
  'Whale / dolphin watching',
  'Surf schools',
  'Hiking / trekking / adventure',
  'Cultural / heritage tours',
  'Multi-day packages',
  'Accommodation',
  'Villa / Hotel',
  'Vehicle rental / transport',
  'Wellness / Ayurveda',
  'Cycling tours',
];

export interface ScheduleException {
  id: string;
  date: string;
  reason?: string | null;
}

export interface NotificationItem {
  id: string;
  type: string;
  title: string;
  message: string;
  isRead: boolean;
  createdAt: string;
}

export interface AvailabilitySearchResult {
  resourceId: string;
  resourceName: string;
  specialty?: string | null;
  branchId?: string | null;
  isOpen: boolean;
  hasAvailability: boolean;
  nextAvailableSlot?: { startTime: string; endTime: string } | null;
}

export interface WorkflowStep {
  agent: string;
  action: string;
  tool: string;
  parameters: Record<string, unknown>;
}

export interface AgentWorkflow {
  id: string;
  tenantId: string;
  objective: string;
  planJson?: string | null;
  status: string;
  approvalStatus: string;
  approvedBy?: string | null;
  approvedAt?: string | null;
  errorLog?: string | null;
  finalOutcome?: string | null;
  completedAt?: string | null;
  createdAt: string;
}

export type BookingUnit = 'Slot' | 'Night' | 'DateRange' | 'Package';

export interface BookingType {
  id: string;
  name: string;
  slug: string;
  description?: string | null;
  colorHex: string;
  status: 'Active' | 'Inactive' | 'Archived';
  defaultDurationMinutes: number;
  requiresApproval: boolean;
  maxParticipants?: number | null;
  bufferMinutesBefore: number;
  bufferMinutesAfter: number;
  bookingUnit: BookingUnit;
  configJson?: string | null;
}

export const BOOKING_UNITS: { value: BookingUnit; label: string; hint: string }[] = [
  { value: 'Slot', label: 'Time slot', hint: 'Fixed-duration slot within a day - consultations, dives, safari drives, lessons.' },
  { value: 'Night', label: 'Night-based', hint: 'Check-in / check-out, priced per night - homestays, guesthouses, hotel rooms.' },
  { value: 'DateRange', label: 'Date range', hint: 'Multi-day, priced per day - vehicle rental, equipment rental.' },
  { value: 'Package', label: 'Multi-day package', hint: 'One reservation across several days with an itinerary - round-island tours.' },
];

export interface DaySchedule {
  dayOfWeek: number;
  startTime: string;
  endTime: string;
  isAvailable: boolean;
  // Business-rule validation (BookingsController.ValidateBusinessRulesAsync).
  // Both unset = no lunch break enforced for this day.
  lunchBreakStart?: string | null;
  lunchBreakEnd?: string | null;
  // Unset = falls back to the platform default of 8 hours/day.
  maxDailyBookedHours?: number | null;
}

export interface AvailabilityDay {
  date: string;
  dayOfWeek: number;
  isOpen: boolean;
  openHours: number;
  bookedHours: number;
  availableHours: number;
  utilizationPercent: number;
}

export interface AvailableSlot {
  startTime: string;
  endTime: string;
  isAvailable: boolean;
}

export interface AvailableSlotsResponse {
  date: string;
  isOpen: boolean;
  resourceId?: string;
  slots: AvailableSlot[];
}

export interface ConflictPair {
  resourceId: string;
  resourceName: string;
  bookingA: { id: string; title?: string | null; startTime: string; endTime: string };
  bookingB: { id: string; title?: string | null; startTime: string; endTime: string };
}

export const STATUS_COLORS: Record<BookingStatus, { fg: string; bg: string; tone: 'good' | 'warning' | 'critical' | 'neutral' | 'primary' }> = {
  Pending: { fg: '#92400e', bg: '#FBBF24', tone: 'warning' },
  Confirmed: { fg: '#1d4ed8', bg: '#2563EB', tone: 'primary' },
  CheckedIn: { fg: '#0f766e', bg: '#22D3EE', tone: 'good' },
  InProgress: { fg: '#155e75', bg: '#0E7490', tone: 'primary' },
  Completed: { fg: '#065f46', bg: '#4ADE80', tone: 'good' },
  Cancelled: { fg: '#475569', bg: '#7C7C85', tone: 'neutral' },
  NoShow: { fg: '#991b1b', bg: '#F87171', tone: 'critical' },
  Rejected: { fg: '#991b1b', bg: '#EF4444', tone: 'critical' },
  // Storm blue rather than the red of a rejection: the operator did not
  // turn this guest away, the sea did.
  WeatherCancelled: { fg: '#075985', bg: '#38BDF8', tone: 'warning' },
};

export const RESOURCE_CATEGORIES: ResourceCategory[] = ['Room', 'Equipment', 'Vehicle', 'Staff', 'Desk', 'Other'];
export const BOOKING_STATUSES: BookingStatus[] = [
  'Pending', 'Confirmed', 'CheckedIn', 'InProgress', 'Completed', 'Cancelled', 'NoShow', 'Rejected',
  'WeatherCancelled',
];

// ── Clinic operations dashboard (ClinicReportsController) ─────────────

export type ClinicGroupBy = 'day' | 'week' | 'month';

export interface ClinicOverviewParams {
  from?: string;
  to?: string;
  branchId?: string;
  resourceId?: string;
  bookingTypeId?: string;
  insuranceProvider?: string;
  groupBy?: ClinicGroupBy;
}

/** Rates and averages are null when there is nothing to measure yet, and
 *  the UI shows a dash for them - never a zero pretending to be a result. */
export interface ClinicKpis {
  totalPatients: number;
  newPatients: number;
  activePatients: number;
  totalDoctors: number;
  doctorsOnDutyToday: number;
  rooms: number;
  totalAppointments: number;
  completed: number;
  noShows: number;
  cancelled: number;
  pending: number;
  confirmed: number;
  completionRate: number | null;
  noShowRate: number | null;
  cancellationRate: number | null;
  revenueRealised: number;
  revenueBooked: number;
  currency: string;
  avgWaitMinutes: number | null;
  avgVisitMinutes: number | null;
  waitSamples: number;
  appointmentsToday: number;
  patientsToday: number;
  patientsPerDoctorToday: number | null;
}

export interface ClinicTrendBucket {
  bucket: string;
  label: string;
  appointments: number;
  completed: number;
  noShows: number;
  cancelled: number;
  revenue: number;
}

export interface ClinicOverview {
  from: string;
  to: string;
  groupBy: ClinicGroupBy;
  asOf: string;
  filters: { branchId?: string | null; resourceId?: string | null; bookingTypeId?: string | null; insuranceProvider?: string | null };
  kpis: ClinicKpis;
  statusMix: { status: BookingStatus; count: number }[];
  trend: ClinicTrendBucket[];
  byDoctor: { resourceId: string; name: string; specialty?: string | null; branchName?: string | null; appointments: number; completed: number; noShows: number; revenue: number; avgWaitMinutes: number | null }[];
  byTreatment: { bookingTypeId: string; name: string; colorHex?: string | null; appointments: number; completed: number; revenue: number }[];
  byBranch: { branchId?: string | null; name: string; appointments: number; patients: number; revenue: number; completionRate: number | null }[];
  byInsurance: { provider: string; patients: number; appointments: number; revenue: number }[];
  bySource: { source: string; appointments: number }[];
  byHour: { hour: number; appointments: number }[];
  filterOptions: {
    branches: { id: string; name: string }[];
    doctors: { id: string; name: string; specialty?: string | null; branchId?: string | null }[];
    treatments: { id: string; name: string; colorHex?: string | null }[];
    insuranceProviders: string[];
  };
}

export type ClinicStage = 'scheduled' | 'waiting' | 'inConsultation' | 'completed' | 'noShow' | 'cancelled';

export interface ClinicQueueEntry {
  bookingId: string;
  patientId: string;
  patientName: string;
  patientPhone?: string | null;
  insuranceProvider?: string | null;
  resourceId: string;
  doctorName: string;
  treatment: string;
  colorHex?: string | null;
  startTime: string;
  endTime: string;
  status: BookingStatus;
  priority: BookingPriority;
  stage: ClinicStage;
  checkInAt?: string | null;
  consultationStartedAt?: string | null;
  checkOutAt?: string | null;
  waitingMinutes: number | null;
  isLongWait: boolean;
  isOverdue: boolean;
  reminderSent: boolean;
}

export interface ClinicFlow {
  asOf: string;
  date: string;
  stages: Record<ClinicStage, number>;
  waitingNow: ClinicQueueEntry[];
  longestWaitMinutes: number | null;
  avgWaitMinutesToday: number | null;
  overdue: number;
  doctorsOnDuty: number;
  doctorsInConsultation: number;
  patientsToday: number;
  patientsPerDoctor: number | null;
  rooms: { total: number; occupied: number; occupancyPercent: number | null };
  queue: ClinicQueueEntry[];
}

export type ClinicAlertSeverity = 'critical' | 'warning' | 'info';

export interface ClinicAlert {
  id: string;
  severity: ClinicAlertSeverity;
  category: string;
  title: string;
  detail: string;
  count: number;
  href: string;
}

export interface ClinicReminderItem {
  bookingId: string;
  patientName: string;
  patientPhone?: string | null;
  patientEmail?: string | null;
  doctorName: string;
  treatment: string;
  startTime: string;
  status: BookingStatus;
  reminderSent: boolean;
  lastReminderAt?: string | null;
  lastChannel?: string | null;
}

export interface ClinicFollowUp {
  patientId: string;
  patientName: string;
  patientPhone?: string | null;
  lastVisit: string;
  doctorName: string;
  treatment: string;
  daysSince: number;
}

export interface ClinicReminders {
  asOf: string;
  withinHours: number;
  unsent: number;
  items: ClinicReminderItem[];
  followUps: ClinicFollowUp[];
}

// ── Restaurant operations dashboard (RestaurantReportsController) ─────
// An "order" is a Booking; see the controller header for the full mapping.
// Rates and averages are null when there is nothing to measure yet.

export type RestaurantGroupBy = 'hour' | 'day' | 'week' | 'month';
export type RestaurantShift = 'breakfast' | 'lunch' | 'dinner' | 'late';
export type RestaurantServiceMode = 'Dine-in' | 'Takeaway' | 'Delivery' | 'Drive-thru';
export type RestaurantStage = 'new' | 'accepted' | 'preparing' | 'ready' | 'completed' | 'cancelled' | 'noShow';
export type RestaurantResourceKind = 'station' | 'table' | 'rider' | 'staff' | 'other';

export interface RestaurantOverviewParams {
  from?: string;
  to?: string;
  groupBy?: RestaurantGroupBy;
  branchId?: string;
  resourceId?: string;
  bookingTypeId?: string;
  channel?: string;
  serviceMode?: string;
  shift?: RestaurantShift;
  /** Viewer offset in minutes east of UTC (-new Date().getTimezoneOffset()). */
  tz?: number;
}

export interface RestaurantKpis {
  currency: string;
  orders: number;
  completed: number;
  cancelled: number;
  noShows: number;
  pending: number;
  open: number;
  completionRate: number | null;
  cancellationRate: number | null;
  revenue: number;
  revenueBooked: number;
  averageOrderValue: number | null;
  covers: number;
  revenuePerCover: number | null;
  revenuePerDay: number;
  ordersPerDay: number;
  avgPrepMinutes: number | null;
  avgTicketMinutes: number | null;
  prepSamples: number;
  onTimeRate: number | null;
  delayed: number;
  prepTargetMinutes: number;
  tables: number;
  tableTurnover: number | null;
  staffRostered: number;
  staffHeadcount: number;
  laborHours: number;
  laborCost: number;
  laborPercent: number | null;
  laborRated: number;
  wasteUnits: number;
  wasteCost: number;
  wastePercent: number | null;
  wasteEntries: number;
  consumptionMovements: number;
  consumptionCost: number;
  lowStockItems: number;
  ordersToday: number;
  revenueToday: number;
  coversToday: number;
}

export interface RestaurantTrendBucket {
  bucket: string;
  label: string;
  orders: number;
  completed: number;
  cancelled: number;
  revenue: number;
  covers: number;
  dineIn: number;
  offPremise: number;
}

export interface RestaurantOverview {
  from: string;
  to: string;
  groupBy: RestaurantGroupBy;
  asOf: string;
  tz: number;
  filters: { branchId?: string | null; resourceId?: string | null; bookingTypeId?: string | null; channel?: string | null; serviceMode?: string | null; shift?: string | null };
  kpis: RestaurantKpis;
  previous: { from: string; to: string; orders: number; completed: number; cancelled: number; revenue: number; covers: number; averageOrderValue: number | null };
  statusMix: { status: BookingStatus; count: number }[];
  trend: RestaurantTrendBucket[];
  byHour: { hour: number; orders: number; revenue: number }[];
  byShift: { shift: RestaurantShift; label: string; hours: string; orders: number; completed: number; revenue: number; covers: number }[];
  byChannel: { channel: string; orders: number; completed: number; cancelled: number; revenue: number; covers: number }[];
  byServiceMode: { mode: string; orders: number; completed: number; revenue: number; covers: number; avgPrepMinutes: number | null }[];
  byMenu: { bookingTypeId: string; name: string; colorHex?: string | null; serviceMode: string; orders: number; completed: number; revenue: number; avgPrepMinutes: number | null; prepTargetMinutes: number; onTimeRate: number | null }[];
  byStation: { resourceId: string; name: string; kind: RestaurantResourceKind; branchName?: string | null; orders: number; completed: number; cancelled: number; revenue: number; covers: number; avgPrepMinutes: number | null; delayed: number }[];
  byBranch: { branchId?: string | null; name: string; orders: number; completed: number; revenue: number; covers: number }[];
  waste: {
    byItem: { inventoryItemId: string; name: string; units: number; cost: number }[];
    byReason: { reason: string; entries: number; units: number; cost: number }[];
  };
  filterOptions: {
    branches: { id: string; name: string }[];
    stations: { id: string; name: string; kind: RestaurantResourceKind; branchId?: string | null }[];
    menu: { id: string; name: string; colorHex?: string | null; serviceMode: string; prepTargetMinutes: number }[];
    channels: string[];
    serviceModes: string[];
    shifts: { id: RestaurantShift; label: string; hours: string }[];
  };
}

export interface RestaurantOrder {
  bookingId: string;
  customerName: string;
  customerPhone?: string | null;
  resourceId: string;
  resourceName: string;
  resourceKind: RestaurantResourceKind;
  menuItem: string;
  colorHex?: string | null;
  serviceMode: string;
  channel: string;
  startTime: string;
  endTime: string;
  createdAt: string;
  status: BookingStatus;
  stage: RestaurantStage;
  priority: BookingPriority;
  covers: number;
  totalCost?: number | null;
  notes?: string | null;
  kitchenStartedAt?: string | null;
  readyAt?: string | null;
  servedAt?: string | null;
  kitchenMinutes: number | null;
  prepTargetMinutes: number;
  isDelayed: boolean;
  wasDelayed: boolean;
  waitingMinutes: number | null;
  isStale: boolean;
  isLateStart: boolean;
}

export interface RestaurantShiftRow {
  resourceId: string;
  name: string;
  role?: string | null;
  shiftStart: string;
  shiftEnd: string;
  scheduledHours: number;
  hoursSoFar: number;
  hourlyRate?: number | null;
  onShift: boolean;
  status: 'busy' | 'on shift' | 'finished' | 'due later';
  ordersHandled: number;
}

export interface RestaurantLive {
  asOf: string;
  date: string;
  isToday: boolean;
  stages: Record<RestaurantStage, number>;
  kitchen: {
    openTickets: number;
    delayed: number;
    stale: number;
    lateStarts: number;
    longestOpenMinutes: number | null;
    avgPrepMinutesToday: number | null;
    onTimeRateToday: number | null;
    defaultTargetMinutes: number;
  };
  tables: { total: number; occupied: number; occupancyPercent: number | null };
  sales: {
    currency: string;
    revenue: number;
    orders: number;
    covers: number;
    averageOrderValue: number | null;
    revenueBooked: number;
    byHour: { hour: number; orders: number; revenue: number }[];
  };
  labor: {
    headcountRostered: number;
    onShiftNow: number;
    scheduledToday: number;
    hoursSoFar: number;
    hoursScheduled: number;
    costSoFar: number;
    costScheduled: number;
    laborPercent: number | null;
    rated: number;
    shifts: RestaurantShiftRow[];
  };
  stations: { resourceId: string; name: string; kind: RestaurantResourceKind; orders: number; open: number; queued: number; completed: number; delayed: number; avgPrepMinutes: number | null; covers: number; revenue: number }[];
  upcoming: { bookingId: string; customerName: string; customerPhone?: string | null; resourceName: string; menuItem: string; serviceMode: string; channel: string; startTime: string; status: BookingStatus; covers: number; totalCost?: number | null; notes?: string | null }[];
  feed: RestaurantOrder[];
}

export interface RestaurantInventoryItem {
  id: string;
  name: string;
  sku: string;
  category?: string | null;
  unit?: string | null;
  quantity: number;
  reorderLevel: number;
  unitCost?: number | null;
  status: 'out' | 'low' | 'ok';
  levelPercent: number | null;
  wastedInRange: number;
  consumedInRange: number;
}

export interface RestaurantInventory {
  asOf: string;
  from: string;
  to: string;
  currency: string;
  summary: {
    items: number;
    lowStock: number;
    outOfStock: number;
    stockValue: number;
    wasteEntries: number;
    wasteUnits: number;
    wasteCost: number;
    consumptionMovements: number;
    consumptionUnits: number;
    consumptionCost: number;
    ordersConsumed: number;
  };
  items: RestaurantInventoryItem[];
  waste: {
    byItem: { inventoryItemId: string; name: string; entries: number; units: number; cost: number }[];
    byReason: { reason: string; entries: number; units: number; cost: number }[];
    log: { id: string; occurredAt: string; item: string; units: number; cost: number; reason: string; notes?: string | null; reference?: string | null }[];
  };
  recentMovements: { id: string; occurredAt: string; item: string; movementType: string; quantity: number; reference?: string | null; notes?: string | null }[];
}

// ── Gym / fitness operations dashboard (GymReportsController) ─────────
// A "visit" is a Booking with a CheckInAt; a membership is a Subscription.
// Rates and averages are null when there is nothing to measure yet.

export type GymGroupBy = 'hour' | 'day' | 'week' | 'month';
export type GymBookingKind = 'access' | 'class' | 'pt' | 'dropIn';
export type GymMembershipStatus = 'active' | 'frozen' | 'cancelled' | 'expired' | 'none';
export type GymPaymentStatus = 'Paid' | 'Pending' | 'Failed' | 'Overdue';
export type GymMaintenanceStatus = 'none' | 'scheduled' | 'dueSoon' | 'overdue' | 'usageDue' | 'inService';

export interface GymOverviewParams {
  from?: string;
  to?: string;
  groupBy?: GymGroupBy;
  branchId?: string;
  resourceId?: string;
  bookingTypeId?: string;
  plan?: string;
  tz?: number;
}

export interface GymKpis {
  currency: string;
  visits: number;
  uniqueVisitors: number;
  visitsPerDay: number;
  avgVisitMinutes: number | null;
  visitSamples: number;
  peakHour: number | null;
  peakHourCheckIns: number;
  totalMembers: number;
  activeMembers: number;
  frozenMembers: number;
  expiredMembers: number;
  cancelledMembers: number;
  withoutMembership: number;
  newMembers: number;
  signUps: number;
  lapsed: number;
  churnRate: number | null;
  renewalsDue30: number;
  renewalsDue7: number;
  overduePayments: number;
  overdueAmount: number;
  revenue: number;
  membershipRevenue: number;
  dropInRevenue: number;
  revenueMtd: number;
  revenueYtd: number;
  monthlyRecurring: number;
  classSessions: number;
  classBookings: number;
  classFillRate: number | null;
  equipmentItems: number;
  equipmentUtilisation: number | null;
  maintenanceDue: number;
  zones: number;
  trainers: number;
}

export interface GymTrendBucket {
  bucket: string;
  label: string;
  visits: number;
  uniqueMembers: number;
  classBookings: number;
  signUps: number;
  revenue: number;
}

export interface GymRenewal {
  subscriptionId: string;
  memberId: string;
  memberName: string;
  phone?: string | null;
  email?: string | null;
  plan: string;
  amount: number;
  endDate: string;
  daysLeft: number;
  autoRenew: boolean;
  paymentStatus: GymPaymentStatus;
}

export interface GymEquipmentRow {
  equipmentItemId: string;
  name: string;
  category: string;
  units: number;
  uses: number;
  hoursUsed: number;
  utilisationPercent: number | null;
  lastServicedAt?: string | null;
  nextDueAt?: string | null;
  usesSinceService: number;
  maintenanceEveryUses: number;
  maintenanceStatus: GymMaintenanceStatus;
  maintenanceNotes?: string | null;
}

export interface GymOverview {
  from: string;
  to: string;
  groupBy: GymGroupBy;
  asOf: string;
  tz: number;
  filters: { branchId?: string | null; resourceId?: string | null; bookingTypeId?: string | null; plan?: string | null };
  targets: { facilityCapacity: number | null; monthlyRevenueTarget: number | null; yearlyRevenueTarget: number | null; monthTargetToDate: number | null; openHoursPerDay: number; maintenanceEveryUses: number };
  kpis: GymKpis;
  previous: { visits: number; uniqueVisitors: number; signUps: number; revenue: number };
  renewals: GymRenewal[];
  outstanding: { subscriptionId: string; memberId: string; memberName: string; phone?: string | null; plan: string; amount: number; paymentStatus: GymPaymentStatus; nextBillingAt?: string | null; lastPaymentAt?: string | null }[];
  payment: { status: GymPaymentStatus; memberships: number; amount: number }[];
  statusMix: { status: BookingStatus; count: number }[];
  trend: GymTrendBucket[];
  heatmap: { dayOfWeek: number; label: string; hours: number[] }[];
  byHour: { hour: number; checkIns: number }[];
  byMethod: { method: string; checkIns: number }[];
  byClass: { bookingTypeId: string; name: string; colorHex?: string | null; sessions: number; bookings: number; attended: number; capacityPerSession?: number | null; fillRate: number | null; avgPerSession: number | null; noShows: number; revenue: number }[];
  byTrainer: { resourceId: string; name: string; specialty?: string | null; sessions: number; bookings: number; completed: number; revenue: number }[];
  byZone: { resourceId: string; name: string; capacity?: number | null; visits: number; hoursBooked: number; utilisationPercent: number | null }[];
  byEquipment: GymEquipmentRow[];
  byPlan: { plan: string; members: number; monthlyValue: number; signUpsInRange: number }[];
  byAge: { band: string; members: number }[];
  byGender: { gender: string; members: number }[];
  byBranch: { branchId?: string | null; name: string; visits: number; members: number }[];
  filterOptions: {
    branches: { id: string; name: string }[];
    zones: { id: string; name: string; capacity?: number | null }[];
    trainers: { id: string; name: string; specialty?: string | null }[];
    classes: { id: string; name: string; colorHex?: string | null; capacity?: number | null }[];
    bookingTypes: { id: string; name: string; kind: GymBookingKind }[];
    plans: string[];
  };
}

export interface GymLiveRow {
  bookingId: string;
  memberId: string;
  memberName: string;
  plan?: string | null;
  membershipStatus: GymMembershipStatus;
  paymentStatus?: GymPaymentStatus | null;
  kind: GymBookingKind;
  activity: string;
  colorHex?: string | null;
  zone: string;
  method: string;
  status: BookingStatus;
  startTime: string;
  checkInAt?: string | null;
  checkOutAt?: string | null;
  minutesInside: number | null;
  isInside: boolean;
}

export interface GymLive {
  asOf: string;
  date: string;
  insideNow: number;
  capacity: number | null;
  occupancyPercent: number | null;
  entriesToday: number;
  exitsToday: number;
  uniqueToday: number;
  expiredInsideToday: number;
  byHour: { hour: number; entries: number; exits: number }[];
  inside: GymLiveRow[];
  recent: GymLiveRow[];
  classesToday: { bookingTypeId: string; name: string; colorHex?: string | null; resourceName: string; startTime: string; endTime: string; booked: number; checkedIn: number; capacity?: number | null; fillPercent: number | null; isFull: boolean; state: 'upcoming' | 'inProgress' | 'done' }[];
  trainers: { rostered: number; onFloor: number; list: { resourceId: string; name: string; specialty?: string | null; shiftStart: string; shiftEnd: string; onFloor: boolean; busy: boolean; sessionsToday: number }[] };
}

export interface GymAttendanceRow {
  bookingId: string;
  memberId: string;
  memberName: string;
  phone?: string | null;
  plan?: string | null;
  membershipStatus: GymMembershipStatus;
  method: string;
  kind: GymBookingKind;
  activity: string;
  zone: string;
  checkInAt: string;
  checkOutAt?: string | null;
  minutes: number | null;
  status: BookingStatus;
}

export interface GymAttendance {
  asOf: string;
  from: string;
  to: string;
  total: number;
  page: number;
  pageSize: number;
  methods: string[];
  rows: GymAttendanceRow[];
}

// ── School / tuition-centre dashboard (SchoolReportsController) ───────
// A lesson session is one start time on one resource; each student has a
// booking on it whose FormData carries the attendance mark. Exams and
// assignments are bookings whose FormData carries the score.

export type SchoolGroupBy = 'day' | 'week' | 'month';
export type SchoolKind = 'lesson' | 'tutoring' | 'exam' | 'assignment';
export type AttendanceMark = 'present' | 'late' | 'absent' | 'excused';
export type SchoolPaymentStatus = 'Paid' | 'Pending' | 'Failed' | 'Overdue';
export type SchoolTuitionStatus = SchoolPaymentStatus | 'lapsed' | 'none';

export interface SchoolOverviewParams {
  from?: string;
  to?: string;
  groupBy?: SchoolGroupBy;
  branchId?: string;
  resourceId?: string;
  bookingTypeId?: string;
  grade?: string;
  tz?: number;
}

export interface SchoolKpis {
  currency: string;
  students: number;
  enrolled: number;
  newStudents: number;
  lapsed: number;
  retentionRate: number | null;
  pendingApprovals: number;
  pendingStudents: number;
  pendingStaff: number;
  sessions: number;
  sessionsHeld: number;
  attendanceRate: number | null;
  present: number;
  late: number;
  absent: number;
  excused: number;
  unmarked: number;
  unmarkedSessions: number;
  assessments: number;
  gradedEntries: number;
  ungradedOverdue: number;
  avgScore: number | null;
  passRate: number | null;
  atRisk: number;
  behaviourPoints: number;
  incidents: number;
  commendations: number;
  teachers: number;
  rooms: number;
  conflicts: number;
  tuitionPaid: number;
  tutoringFees: number;
  income: number;
  payrollHours: number;
  payrollCost: number;
  purchases: number;
  costs: number;
  net: number;
  outstandingCount: number;
  outstandingAmount: number;
  monthlyRecurring: number;
}

export interface SchoolStudentRow {
  studentId: string;
  name: string;
  phone?: string | null;
  grade?: string | null;
  sessionsMarked: number;
  attended: number;
  late: number;
  absent: number;
  excused: number;
  attendanceRate: number | null;
  avgScore: number | null;
  graded: number;
  points: number;
  incidents: number;
  commendations: number;
  lastSeen?: string | null;
  atRisk: boolean;
  reasons: string[];
  medicalAlert: boolean;
  tuitionStatus: SchoolTuitionStatus;
}

export interface SchoolTrendBucket {
  bucket: string;
  label: string;
  sessions: number;
  attendanceRate: number | null;
  absences: number;
  avgScore: number | null;
  newStudents: number;
  tuitionPaid: number;
}

export interface SchoolOverview {
  from: string;
  to: string;
  groupBy: SchoolGroupBy;
  asOf: string;
  tz: number;
  filters: { branchId?: string | null; resourceId?: string | null; bookingTypeId?: string | null; grade?: string | null };
  thresholds: { atRiskAttendancePercent: number; atRiskGradePercent: number; lateAfterMinutes: number; scale: { grade: string; min: number }[] };
  calendar: {
    terms: { name: string; from: string; to: string; isCurrent: boolean }[];
    currentTerm: { name: string; from: string; to: string; daysLeft: number; progressPercent: number } | null;
    holidays: { name: string; date: string; daysAway: number }[];
    nextHoliday: { name: string; date: string; daysAway: number } | null;
  };
  kpis: SchoolKpis;
  previous: { attendanceRate: number | null; avgScore: number | null; newStudents: number; income: number; sessions: number };
  attendanceMix: { mark: AttendanceMark; count: number }[];
  distribution: { grade: string; min: number; count: number }[];
  trend: SchoolTrendBucket[];
  bySubject: { bookingTypeId: string; name: string; subject?: string | null; grade?: string | null; kind: SchoolKind; colorHex?: string | null; teacher?: string | null; sessions: number; students: number; attendanceRate: number | null; assessments: number; graded: number; avgScore: number | null; weight: number }[];
  byGrade: { grade: string; students: number; sessions: number; attendanceRate: number | null; avgScore: number | null; atRisk: number }[];
  byGradeEnrolment: { grade: string; students: number }[];
  byTeacher: { resourceId: string; name: string; specialty?: string | null; sessions: number; hoursTaught: number; students: number; attendanceRate: number | null; unmarkedSessions: number; payEstimate: number | null }[];
  byRoom: { resourceId: string; name: string; capacity?: number | null; sessions: number; hoursBooked: number; utilisationPercent: number | null }[];
  atRisk: SchoolStudentRow[];
  students: SchoolStudentRow[];
  payment: { status: SchoolPaymentStatus; students: number; amount: number }[];
  outstanding: { subscriptionId: string; studentId: string; studentName: string; phone?: string | null; plan: string; amount: number; paymentStatus: SchoolPaymentStatus; nextBillingAt?: string | null; lastPaymentAt?: string | null }[];
  pendingApprovals: { id: string; fullName: string; email: string; phone: string; createdAt: string; role: string }[];
  conflicts: { resource: string; first: string; second: string; startTime: string; overlapMinutes: number }[];
  filterOptions: {
    branches: { id: string; name: string }[];
    teachers: { id: string; name: string; specialty?: string | null }[];
    rooms: { id: string; name: string; capacity?: number | null }[];
    subjects: { id: string; name: string; kind: SchoolKind; subject?: string | null; grade?: string | null }[];
    grades: string[];
  };
}

export interface SchoolRosterRow {
  bookingId: string;
  studentId: string;
  studentName: string;
  phone?: string | null;
  mark: AttendanceMark | null;
  arrivedAt?: string | null;
  points: number;
  note?: string | null;
  medicalAlert?: string | null;
  tuitionStatus: SchoolTuitionStatus;
}

export interface SchoolSession {
  sessionKey: string;
  bookingTypeId: string;
  name: string;
  subject?: string | null;
  grade?: string | null;
  colorHex?: string | null;
  resourceId: string;
  resourceName: string;
  resourceKind: 'teacher' | 'room';
  startTime: string;
  endTime: string;
  state: 'upcoming' | 'inProgress' | 'done';
  students: number;
  present: number;
  late: number;
  absent: number;
  excused: number;
  unmarked: number;
  needsMarking: boolean;
  roster: SchoolRosterRow[];
}

export interface SchoolToday {
  asOf: string;
  date: string;
  holiday?: string | null;
  term?: string | null;
  summary: { sessions: number; done: number; inProgress: number; upcoming: number; needsMarking: number; studentsExpected: number; presentSoFar: number; absentSoFar: number; medicalAlerts: number };
  sessions: SchoolSession[];
  teachers: { rostered: number; onDuty: number; list: { resourceId: string; name: string; specialty?: string | null; shiftStart: string; shiftEnd: string; onDuty: boolean; sessionsToday: number }[] };
  assignments: { bookingTypeId: string; name: string; subject?: string | null; grade?: string | null; dueAt: string; isOverdue: boolean; students: number; submitted: number; graded: number }[];
  pendingApprovals: { id: string; fullName: string; email: string; phone: string; role: string; createdAt: string }[];
}

export interface SchoolStudentDetail {
  asOf: string;
  student: { id: string; fullName: string; email: string; phone: string; address?: string | null; medicalNotes?: string | null; joinedAt: string; isApproved: boolean; dateOfBirth?: string | null };
  tuition: { plan: string; amount: number; status: string; paymentStatus: SchoolPaymentStatus; endDate: string } | null;
  summary: { attendanceRate: number | null; avgScore: number | null; letter?: string | null; points: number; incidents: number; commendations: number; atRisk: boolean; reasons: string[]; sessionsMarked: number; attended: number } | null;
  perSubject: { bookingTypeId: string; name: string; subject?: string | null; grade?: string | null; kind: SchoolKind; colorHex?: string | null; sessions: number; attended: number; marked: number; attendanceRate: number | null; avgScore: number | null; letter?: string | null }[];
  assessments: { bookingId: string; name: string; subject?: string | null; kind: SchoolKind; colorHex?: string | null; date: string; dueAt: string; submittedAt?: string | null; score: number | null; maxScore: number; percent: number | null; letter?: string | null; weight: number; feedback?: string | null }[];
  attendance: { bookingId: string; date: string; name: string; teacher: string; mark: AttendanceMark | null; arrivedAt?: string | null; points: number; note?: string | null }[];
  behaviour: { bookingId: string; date: string; name: string; teacher: string; mark: AttendanceMark | null; points: number; note?: string | null }[];
}

export interface SchoolGradebookRow {
  bookingId: string;
  studentId: string;
  studentName: string;
  score: number | null;
  maxScore: number;
  percent: number | null;
  letter?: string | null;
  submittedAt?: string | null;
  feedback?: string | null;
}

export interface SchoolAssessment {
  key: string;
  bookingTypeId: string;
  name: string;
  subject?: string | null;
  grade?: string | null;
  kind: SchoolKind;
  colorHex?: string | null;
  weight: number;
  date: string;
  dueAt: string;
  isOverdue: boolean;
  students: number;
  submitted: number;
  graded: number;
  avgPercent: number | null;
  maxScore: number;
  rows: SchoolGradebookRow[];
}

export interface SchoolGradebook {
  asOf: string;
  from: string;
  to: string;
  scale: { grade: string; min: number }[];
  assessments: SchoolAssessment[];
}
