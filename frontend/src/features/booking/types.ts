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
  createdAt: string;
}

export interface StaffUser {
  id: string;
  fullName: string;
  email: string;
  role: 'Manager' | 'Staff';
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
  finalOutcome?: string | null;
  createdAt: string;
}

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
}

export interface DaySchedule {
  dayOfWeek: number;
  startTime: string;
  endTime: string;
  isAvailable: boolean;
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
  Pending: { fg: '#92400e', bg: '#d97706', tone: 'warning' },
  Confirmed: { fg: '#1d4ed8', bg: '#2563eb', tone: 'primary' },
  CheckedIn: { fg: '#0f766e', bg: '#0d9488', tone: 'good' },
  InProgress: { fg: '#5b21b6', bg: '#7c3aed', tone: 'primary' },
  Completed: { fg: '#065f46', bg: '#059669', tone: 'good' },
  Cancelled: { fg: '#475569', bg: '#64748b', tone: 'neutral' },
  NoShow: { fg: '#991b1b', bg: '#dc2626', tone: 'critical' },
  Rejected: { fg: '#991b1b', bg: '#b91c1c', tone: 'critical' },
};

export const RESOURCE_CATEGORIES: ResourceCategory[] = ['Room', 'Equipment', 'Vehicle', 'Staff', 'Desk', 'Other'];
export const BOOKING_STATUSES: BookingStatus[] = [
  'Pending', 'Confirmed', 'CheckedIn', 'InProgress', 'Completed', 'Cancelled', 'NoShow', 'Rejected',
];
