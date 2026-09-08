export type BookingStatus =
  | 'Pending'
  | 'Confirmed'
  | 'CheckedIn'
  | 'InProgress'
  | 'Completed'
  | 'Cancelled'
  | 'NoShow'
  | 'Rejected';

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
};

export const RESOURCE_CATEGORIES: ResourceCategory[] = ['Room', 'Equipment', 'Vehicle', 'Staff', 'Desk', 'Other'];
export const BOOKING_STATUSES: BookingStatus[] = [
  'Pending', 'Confirmed', 'CheckedIn', 'InProgress', 'Completed', 'Cancelled', 'NoShow', 'Rejected',
];
