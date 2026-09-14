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
  Scheduled: { bg: '#8B5CF6', label: 'Scheduled' },
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
  Confirmed: { fg: '#1d4ed8', bg: '#8B5CF6', tone: 'primary' },
  CheckedIn: { fg: '#0f766e', bg: '#22D3EE', tone: 'good' },
  InProgress: { fg: '#5b21b6', bg: '#E040FB', tone: 'primary' },
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
