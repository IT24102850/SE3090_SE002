/* The single source of truth for what makes each tourism business type's
 * admin dashboard distinct - the React mirror of mobile's
 * lib/registry/tourism_dashboard_registry.dart.
 *
 * Adding a sub-type is one entry here plus one key in tourismSubTypes.ts.
 * No screen component changes.
 *
 * Only whaleWatching turns on the full operational module set in this
 * iteration; the other eleven define their terminology, KPIs, resource
 * columns and booking form fields, and declare which shared modules they
 * would use, so extending a module to them is config, not code. */

import {
  NO_MODULES,
  type SubtypeDashboardConfig,
} from './SubtypeDashboardConfig';
import { TOURISM_SUB_TYPE_LABELS, type TourismSubType } from './tourismSubTypes';

/* KPI cards every sub-type gets, derived from the bookings the dashboard
 * has already loaded so they cost no extra request. Sub-types append their
 * own on top. */
const BASE_KPIS = (unitPlural: string): SubtypeDashboardConfig['kpis'] => [
  { id: 'today', label: 'Today', source: 'bookings', field: 'today', sub: `${unitPlural} scheduled` },
  { id: 'pending', label: 'Pending', source: 'bookings', field: 'pending', sub: 'awaiting confirmation', tone: 'warning' },
  { id: 'confirmed', label: 'Confirmed', source: 'bookings', field: 'confirmed', sub: 'in this view', tone: 'good' },
];

const CONFIGS: Record<TourismSubType, SubtypeDashboardConfig> = {
  // ── Whale / dolphin watching - fully implemented ───────────────────
  whaleWatching: {
    subType: 'whaleWatching',
    label: TOURISM_SUB_TYPE_LABELS.whaleWatching,
    bookingUnit: 'slot',
    resourceTermSingular: 'Departure',
    resourceTermPlural: 'Departures',
    bookingTermSingular: 'Reservation',
    bookingTermPlural: 'Reservations / Manifest',
    equipmentTerm: 'Safety Equipment & Gear',
    heroActionLabel: "Manage today's departures",
    icon: '🐋',
    themeColor: '#0EA5E9',
    // An operator running four sailings a day does not think of the home
    // screen as "Dashboard" or of a boat as a "Resource".
    navOverrides: {
      '/dashboard': { label: 'Departure Board', icon: '🐋' },
      '/bookings': { label: 'Reservations & Manifest', icon: '📋' },
      '/resources': { label: 'Vessels & Crew', icon: '🚤' },
    },
    kpis: [
      { id: 'departuresToday', label: 'Departures today', source: 'excursion', field: 'departuresToday', sub: 'scheduled sailings' },
      { id: 'paxToday', label: 'Pax booked today', source: 'excursion', field: 'paxBookedToday', sub: 'of capacity' },
      { id: 'sightingRate', label: 'Sighting success', source: 'excursion', field: 'sightingSuccessRate', format: 'percent', sub: 'season to date', tone: 'good' },
      { id: 'revenueToday', label: 'Revenue today', source: 'excursion', field: 'revenueToday', format: 'currency' },
      { id: 'weatherCancelled', label: 'Weather-cancelled', source: 'excursion', field: 'weatherCancelledThisMonth', sub: 'departures this month', tone: 'critical' },
      { id: 'waivers', label: 'Waiver completion', source: 'excursion', field: 'waiverCompletionPercent', format: 'percent', tone: 'warning' },
      { id: 'forwardOccupancy', label: 'Next 7 days', source: 'excursion', field: 'nextDaysOccupancyPercent', format: 'percent', sub: 'forward occupancy' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Vessel' },
      { key: 'capacity', label: 'Licensed capacity' },
      { key: 'specialty', label: 'Operation' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'capacity', icon: '👥', labelTemplate: '{value} passenger capacity' },
      { key: 'departureTime', icon: '🕕', labelTemplate: 'Departs {value}' },
    ],
    bookingFormFields: [
      { key: 'hotelPickupNeeded', label: 'Hotel pickup & drop-off', type: 'checkbox' },
      { key: 'pickupLocation', label: 'Pickup location', type: 'text' },
      { key: 'nationality', label: 'Guest nationality', type: 'text', hint: 'Feeds the nationality breakdown in Reports.' },
    ],
    modules: {
      weather: true,
      departures: true,
      sightings: true,
      safety: true,
      approvals: false,
      ticketTypes: true,
    },
  },

  // ── Water sports / diving ───────────────────────────────────────────
  diving: {
    subType: 'diving',
    label: TOURISM_SUB_TYPE_LABELS.diving,
    bookingUnit: 'slot',
    resourceTermSingular: 'Dive Trip',
    resourceTermPlural: 'Dive Boats & Instructors',
    bookingTermSingular: 'Dive booking',
    bookingTermPlural: 'Dive bookings',
    equipmentTerm: 'Dive Gear & Tanks',
    heroActionLabel: "Manage today's dives",
    icon: '🤿',
    themeColor: '#38BDF8',
    kpis: [
      { id: 'today', label: 'Dives today', source: 'bookings', field: 'today', sub: 'scheduled dives' },
      { id: 'divers', label: 'Divers today', source: 'bookings', field: 'attendeesToday', sub: 'across all trips' },
      { id: 'tankUtilisation', label: 'Boat utilisation', source: 'resources', field: 'utilisation', format: 'percent', sub: 'of dive-boat seats' },
      { id: 'certifications', label: 'Certified divers', source: 'bookings', field: 'certifiedCount', sub: 'Open Water or above' },
      { id: 'serviceDue', label: 'Equipment service due', source: 'resources', field: 'maintenanceDue', tone: 'warning' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Boat / instructor' },
      { key: 'capacity', label: 'Max divers' },
      { key: 'specialty', label: 'Certification' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'capacity', icon: '👥', labelTemplate: '{value} divers max' },
      { key: 'tankCount', icon: '🛢️', labelTemplate: '{value} tanks' },
      { key: 'depth', icon: '🌊', labelTemplate: 'Max depth {value}m' },
    ],
    bookingFormFields: [
      {
        key: 'certificationLevel',
        label: 'Certification level',
        type: 'dropdown',
        options: ['None', 'Discover Scuba', 'Open Water', 'Advanced', 'Rescue', 'Divemaster'],
      },
      { key: 'divesLogged', label: 'Dives logged', type: 'numberStepper' },
      { key: 'rentalBcd', label: 'Rent BCD', type: 'checkbox' },
      { key: 'rentalRegulator', label: 'Rent regulator', type: 'checkbox' },
      { key: 'rentalWetsuit', label: 'Rent wetsuit', type: 'checkbox' },
      { key: 'rentalFins', label: 'Rent fins', type: 'checkbox' },
      { key: 'medicalDeclaration', label: 'Medical fitness declaration', type: 'fileUpload' },
    ],
    modules: { ...NO_MODULES, weather: true, safety: true, ticketTypes: true },
  },

  // ── Safari / wildlife ───────────────────────────────────────────────
  safari: {
    subType: 'safari',
    label: TOURISM_SUB_TYPE_LABELS.safari,
    bookingUnit: 'slot',
    resourceTermSingular: 'Safari Drive',
    resourceTermPlural: 'Jeeps & Driver-Guides',
    bookingTermSingular: 'Drive booking',
    bookingTermPlural: 'Drive bookings',
    equipmentTerm: 'Vehicle Equipment',
    heroActionLabel: "Manage today's drives",
    icon: '🐆',
    themeColor: '#F0A868',
    kpis: [
      { id: 'today', label: 'Drives today', source: 'bookings', field: 'today', sub: 'scheduled drives' },
      { id: 'pax', label: 'Pax carried', source: 'bookings', field: 'attendeesToday', sub: 'across all jeeps' },
      { id: 'parkFees', label: 'Park-fee revenue', source: 'bookings', field: 'parkFeeRevenue', format: 'currency', sub: 'entrance fees collected' },
      // The same SightingsLog table and analytics the whale-watching
      // dashboard uses - species just happen to be leopard and elephant.
      { id: 'sightingRate', label: 'Sighting success', source: 'excursion', field: 'sightingSuccessRate', format: 'percent', sub: 'drives with a sighting', tone: 'good' },
      { id: 'utilisation', label: 'Jeep utilisation', source: 'resources', field: 'utilisation', format: 'percent' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Jeep / driver-guide' },
      { key: 'capacity', label: 'Seats' },
      { key: 'specialty', label: 'Park' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'capacity', icon: '👥', labelTemplate: '{value} seats' },
      { key: 'fourWheelDrive', icon: '🚙', labelTemplate: '4WD: {value}' },
      { key: 'guideLanguage', icon: '🗣️', labelTemplate: 'Guide speaks {value}' },
    ],
    bookingFormFields: [
      {
        key: 'parkPreference',
        label: 'Park',
        type: 'dropdown',
        options: ['Yala', 'Udawalawe', 'Wilpattu', 'Minneriya'],
      },
      {
        key: 'entranceFeeIncluded',
        label: 'Include park entrance fee',
        type: 'checkbox',
        hint: 'Park fees are a real per-pax cost and vary by residency.',
      },
      { key: 'hotelPickup', label: 'Hotel pickup', type: 'checkbox' },
      { key: 'pickupLocation', label: 'Pickup location', type: 'text' },
      { key: 'nationality', label: 'Guest nationality', type: 'text' },
    ],
    modules: { ...NO_MODULES, weather: true, sightings: true, ticketTypes: true },
  },

  // ── Surf schools ────────────────────────────────────────────────────
  surfSchool: {
    subType: 'surfSchool',
    label: TOURISM_SUB_TYPE_LABELS.surfSchool,
    bookingUnit: 'slot',
    resourceTermSingular: 'Surf Lesson',
    resourceTermPlural: 'Instructors & Boards',
    bookingTermSingular: 'Lesson',
    bookingTermPlural: 'Lessons',
    equipmentTerm: 'Boards & Wetsuits',
    heroActionLabel: "Manage today's lessons",
    icon: '🏄',
    themeColor: '#22D3EE',
    kpis: [
      { id: 'today', label: 'Lessons today', source: 'bookings', field: 'today', sub: 'scheduled lessons' },
      { id: 'students', label: 'Students today', source: 'bookings', field: 'attendeesToday' },
      { id: 'utilisation', label: 'Instructor utilisation', source: 'resources', field: 'utilisation', format: 'percent' },
      { id: 'boardRentals', label: 'Board rentals', source: 'bookings', field: 'boardRentals', sub: 'boards out today' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Instructor / board' },
      { key: 'capacity', label: 'Max students' },
      { key: 'specialty', label: 'Speciality' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'instructor', icon: '🧑‍🏫', labelTemplate: 'with {value}' },
      { key: 'boardType', icon: '🏄', labelTemplate: '{value}' },
    ],
    bookingFormFields: [
      { key: 'skillLevel', label: 'Skill level', type: 'dropdown', options: ['Beginner', 'Intermediate', 'Advanced'] },
      {
        key: 'boardTypePreference',
        label: 'Board preference',
        type: 'dropdown',
        options: ['Soft-top', 'Funboard', 'Shortboard'],
      },
      { key: 'lessonLength', label: 'Lesson length', type: 'dropdown', options: ['1 hour', '2 hours', 'Full day'] },
    ],
    modules: { ...NO_MODULES, weather: true },
  },

  // ── Hiking / trekking / adventure ───────────────────────────────────
  trekking: {
    subType: 'trekking',
    label: TOURISM_SUB_TYPE_LABELS.trekking,
    bookingUnit: 'slot',
    resourceTermSingular: 'Guided Trek',
    resourceTermPlural: 'Guides & Treks',
    bookingTermSingular: 'Trek booking',
    bookingTermPlural: 'Trek bookings',
    equipmentTerm: 'Trekking Gear',
    heroActionLabel: "Manage this week's treks",
    icon: '🥾',
    themeColor: '#4ADE80',
    kpis: [
      { id: 'thisWeek', label: 'Treks this week', source: 'bookings', field: 'thisWeek' },
      { id: 'today', label: 'Departing today', source: 'bookings', field: 'today' },
      { id: 'utilisation', label: 'Guide utilisation', source: 'resources', field: 'utilisation', format: 'percent' },
      { id: 'avgGroup', label: 'Avg group size', source: 'bookings', field: 'avgGroupSize', sub: 'trekkers per departure' },
      // Groups over 8 need a guide pairing decision, so they route through
      // the existing RequiresApproval flow rather than auto-confirming.
      { id: 'pendingApproval', label: 'Awaiting approval', source: 'bookings', field: 'pending', sub: 'groups over 8', tone: 'warning' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Guide' },
      { key: 'capacity', label: 'Max group' },
      { key: 'specialty', label: 'Route' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'difficulty', icon: '⛰️', labelTemplate: '{value} difficulty' },
      { key: 'durationHours', icon: '⏱️', labelTemplate: '{value} hours' },
    ],
    bookingFormFields: [
      { key: 'difficulty', label: 'Difficulty', type: 'dropdown', options: ['Easy', 'Moderate', 'Challenging'] },
      { key: 'fitnessDeclaration', label: 'Fitness declaration confirmed', type: 'checkbox' },
      { key: 'pickupPoint', label: 'Pickup point', type: 'text' },
      { key: 'emergencyContact', label: 'Emergency contact', type: 'text' },
    ],
    modules: { ...NO_MODULES, weather: true, approvals: true, safety: true },
  },

  // ── Cultural / heritage tours ───────────────────────────────────────
  culturalTour: {
    subType: 'culturalTour',
    label: TOURISM_SUB_TYPE_LABELS.culturalTour,
    bookingUnit: 'slot',
    resourceTermSingular: 'Guided Tour',
    resourceTermPlural: 'Guides & Vehicles',
    bookingTermSingular: 'Tour booking',
    bookingTermPlural: 'Tour bookings',
    equipmentTerm: 'Tour Equipment',
    heroActionLabel: "Manage today's tours",
    icon: '🏛️',
    themeColor: '#E0A87A',
    kpis: [
      { id: 'today', label: 'Tours today', source: 'bookings', field: 'today' },
      { id: 'avgParty', label: 'Avg party size', source: 'bookings', field: 'avgGroupSize' },
      { id: 'revenue', label: 'Revenue by tour type', source: 'bookings', field: 'revenue', format: 'currency' },
      { id: 'utilisation', label: 'Guide utilisation', source: 'resources', field: 'utilisation', format: 'percent' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Guide / vehicle' },
      { key: 'capacity', label: 'Party size' },
      { key: 'specialty', label: 'Languages' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'language', icon: '🗣️', labelTemplate: '{value}' },
      { key: 'sites', icon: '📍', labelTemplate: '{value}' },
    ],
    bookingFormFields: [
      {
        key: 'languagePreference',
        label: 'Guide language',
        type: 'dropdown',
        options: ['English', 'German', 'French', 'Chinese', 'Japanese', 'Other'],
      },
      { key: 'siteSigiriya', label: 'Include Sigiriya', type: 'checkbox' },
      { key: 'siteDambulla', label: 'Include Dambulla', type: 'checkbox' },
      { key: 'siteKandy', label: 'Include Kandy Temple', type: 'checkbox' },
      { key: 'entranceTicketsIncluded', label: 'Include entrance tickets', type: 'checkbox' },
      { key: 'lunchIncluded', label: 'Include lunch', type: 'checkbox' },
    ],
    modules: { ...NO_MODULES, ticketTypes: true },
  },

  // ── Multi-day packages ──────────────────────────────────────────────
  multiDayPackage: {
    subType: 'multiDayPackage',
    label: TOURISM_SUB_TYPE_LABELS.multiDayPackage,
    bookingUnit: 'package',
    resourceTermSingular: 'Itinerary',
    resourceTermPlural: 'Itineraries',
    bookingTermSingular: 'Package booking',
    bookingTermPlural: 'Package bookings',
    equipmentTerm: 'Package Inclusions',
    heroActionLabel: 'Review pending packages',
    icon: '🗺️',
    themeColor: '#A78BFA',
    kpis: [
      { id: 'pendingApproval', label: 'Pending approval', source: 'bookings', field: 'pending', sub: 'packages awaiting sign-off', tone: 'warning' },
      { id: 'confirmedRevenue', label: 'Confirmed revenue', source: 'bookings', field: 'confirmedRevenue', format: 'currency' },
      { id: 'avgValue', label: 'Avg package value', source: 'bookings', field: 'avgValue', format: 'currency' },
      { id: 'inProgress', label: 'Currently touring', source: 'bookings', field: 'inProgress', sub: 'packages under way' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Itinerary' },
      { key: 'capacity', label: 'Party size' },
      { key: 'specialty', label: 'Region' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'durationDays', icon: '📆', labelTemplate: '{value} days' },
      { key: 'hotelCategory', icon: '🏨', labelTemplate: '{value}' },
    ],
    bookingFormFields: [
      { key: 'startDate', label: 'Start date', type: 'date' },
      { key: 'partySize', label: 'Party size', type: 'numberStepper' },
      { key: 'itineraryRequests', label: 'Itinerary requests', type: 'textArea' },
      {
        key: 'hotelCategoryPreference',
        label: 'Hotel category',
        type: 'dropdown',
        options: ['Budget', 'Standard', 'Luxury'],
      },
    ],
    // Always: a multi-day package is too high-value to auto-confirm, which
    // is the same threshold reasoning as the >20-booking agent workflow.
    modules: { ...NO_MODULES, approvals: true },
  },

  // ── Accommodation ───────────────────────────────────────────────────
  accommodation: {
    subType: 'accommodation',
    label: TOURISM_SUB_TYPE_LABELS.accommodation,
    bookingUnit: 'night',
    resourceTermSingular: 'Room',
    resourceTermPlural: 'Rooms',
    bookingTermSingular: 'Stay',
    bookingTermPlural: 'Stays',
    equipmentTerm: 'Housekeeping Supplies',
    heroActionLabel: "Manage tonight's rooms",
    icon: '🛏️',
    themeColor: '#E040FB',
    kpis: [
      { id: 'occupancy', label: 'Occupancy tonight', source: 'bookings', field: 'occupancyTonight', format: 'percent', tone: 'good' },
      { id: 'adr', label: 'ADR', source: 'bookings', field: 'adr', format: 'currency', sub: 'average daily rate' },
      { id: 'revpar', label: 'RevPAR', source: 'bookings', field: 'revpar', format: 'currency', sub: 'revenue per available room' },
      { id: 'checkIns', label: 'Check-ins today', source: 'bookings', field: 'checkInsToday' },
      { id: 'checkOuts', label: 'Check-outs today', source: 'bookings', field: 'checkOutsToday' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Room' },
      { key: 'capacity', label: 'Sleeps' },
      { key: 'specialty', label: 'Room type' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'bedCount', icon: '🛏️', labelTemplate: '{value} beds' },
      { key: 'roomType', icon: '🏷️', labelTemplate: '{value}' },
    ],
    bookingFormFields: [
      {
        key: 'mealPlan',
        label: 'Meal plan',
        type: 'dropdown',
        options: ['Breakfast only', 'Half board', 'Full board'],
      },
      { key: 'extraBed', label: 'Extra bed', type: 'checkbox' },
      { key: 'extraBedCount', label: 'Extra beds', type: 'numberStepper' },
      { key: 'airportTransfer', label: 'Airport transfer', type: 'checkbox' },
      { key: 'specialRequests', label: 'Special requests', type: 'textArea' },
    ],
    modules: { ...NO_MODULES },
  },

  // ── Villa / Hotel ───────────────────────────────────────────────────
  villaHotel: {
    subType: 'villaHotel',
    label: TOURISM_SUB_TYPE_LABELS.villaHotel,
    bookingUnit: 'night',
    resourceTermSingular: 'Room',
    resourceTermPlural: 'Rooms & Villas',
    bookingTermSingular: 'Stay',
    bookingTermPlural: 'Stays',
    equipmentTerm: 'Housekeeping Supplies',
    heroActionLabel: "Manage tonight's rooms",
    icon: '🏝️',
    themeColor: '#F472B6',
    kpis: [
      { id: 'occupancy', label: 'Occupancy tonight', source: 'bookings', field: 'occupancyTonight', format: 'percent', tone: 'good' },
      { id: 'adr', label: 'ADR', source: 'bookings', field: 'adr', format: 'currency', sub: 'average daily rate' },
      { id: 'revpar', label: 'RevPAR', source: 'bookings', field: 'revpar', format: 'currency' },
      { id: 'checkIns', label: 'Check-ins today', source: 'bookings', field: 'checkInsToday' },
      { id: 'checkOuts', label: 'Check-outs today', source: 'bookings', field: 'checkOutsToday' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Room / villa' },
      { key: 'capacity', label: 'Sleeps' },
      { key: 'specialty', label: 'Type' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'bedCount', icon: '🛏️', labelTemplate: '{value} beds' },
      { key: 'poolAccess', icon: '🏊', labelTemplate: 'Pool: {value}' },
    ],
    bookingFormFields: [
      {
        key: 'mealPlan',
        label: 'Meal plan',
        type: 'dropdown',
        options: ['Breakfast only', 'Half board', 'Full board'],
      },
      { key: 'extraBed', label: 'Extra bed', type: 'checkbox' },
      { key: 'extraBedCount', label: 'Extra beds', type: 'numberStepper' },
      { key: 'airportTransfer', label: 'Airport transfer', type: 'checkbox' },
      { key: 'specialRequests', label: 'Special requests', type: 'textArea' },
    ],
    modules: { ...NO_MODULES },
  },

  // ── Vehicle rental / transport ──────────────────────────────────────
  vehicleRental: {
    subType: 'vehicleRental',
    label: TOURISM_SUB_TYPE_LABELS.vehicleRental,
    bookingUnit: 'dateRange',
    resourceTermSingular: 'Vehicle',
    resourceTermPlural: 'Fleet',
    bookingTermSingular: 'Rental',
    bookingTermPlural: 'Rentals',
    equipmentTerm: 'Vehicle Equipment',
    heroActionLabel: 'Manage the fleet',
    icon: '🛵',
    themeColor: '#67E8F9',
    kpis: [
      { id: 'fleetUtilisation', label: 'Fleet utilisation', source: 'resources', field: 'utilisation', format: 'percent', tone: 'good' },
      { id: 'dueBack', label: 'Due back today', source: 'bookings', field: 'endingToday', sub: 'vehicles returning', tone: 'warning' },
      { id: 'outNow', label: 'Out now', source: 'bookings', field: 'inProgress', sub: 'vehicles on hire' },
      { id: 'deposits', label: 'Deposit held', source: 'bookings', field: 'depositsHeld', format: 'currency' },
      { id: 'pendingApproval', label: 'Awaiting approval', source: 'bookings', field: 'pending', sub: 'rentals over 7 days', tone: 'warning' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Vehicle' },
      { key: 'capacity', label: 'Seats' },
      { key: 'specialty', label: 'Class' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'transmission', icon: '⚙️', labelTemplate: '{value}' },
      { key: 'fuelType', icon: '⛽', labelTemplate: '{value}' },
    ],
    bookingFormFields: [
      { key: 'licenseNumber', label: 'Driving licence number', type: 'text' },
      { key: 'licensePhoto', label: 'Licence photo', type: 'fileUpload', hint: 'Required before handover.' },
      { key: 'withDriver', label: 'With driver', type: 'checkbox' },
      { key: 'pickupDateTime', label: 'Pickup date & time', type: 'date' },
      { key: 'returnDateTime', label: 'Return date & time', type: 'date' },
    ],
    modules: { ...NO_MODULES, approvals: true },
  },

  // ── Wellness / Ayurveda ─────────────────────────────────────────────
  wellness: {
    subType: 'wellness',
    label: TOURISM_SUB_TYPE_LABELS.wellness,
    bookingUnit: 'slot',
    resourceTermSingular: 'Treatment',
    resourceTermPlural: 'Therapists & Rooms',
    bookingTermSingular: 'Appointment',
    bookingTermPlural: 'Appointments',
    equipmentTerm: 'Treatment Supplies',
    heroActionLabel: "Manage today's appointments",
    icon: '🧘',
    themeColor: '#86EFAC',
    kpis: [
      { id: 'today', label: 'Appointments today', source: 'bookings', field: 'today' },
      { id: 'roomUtilisation', label: 'Room utilisation', source: 'resources', field: 'utilisation', format: 'percent' },
      { id: 'revenue', label: 'Treatment revenue', source: 'bookings', field: 'revenue', format: 'currency' },
      { id: 'therapists', label: 'Therapists on shift', source: 'resources', field: 'availableStaff' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Therapist / room' },
      { key: 'capacity', label: 'Capacity' },
      { key: 'specialty', label: 'Speciality' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'practitioner', icon: '🧑‍⚕️', labelTemplate: 'with {value}' },
      { key: 'treatmentRoom', icon: '🚪', labelTemplate: '{value}' },
    ],
    bookingFormFields: [
      {
        key: 'treatmentType',
        label: 'Treatment',
        type: 'dropdown',
        options: ['Ayurveda Massage', 'Herbal Bath', 'Yoga Session', 'Shirodhara', 'Panchakarma'],
      },
      { key: 'duration', label: 'Duration', type: 'dropdown', options: ['30 min', '60 min', '90 min', '120 min'] },
      {
        key: 'therapistGenderPreference',
        label: 'Therapist gender preference',
        type: 'dropdown',
        options: ['No preference', 'Female', 'Male'],
      },
      { key: 'healthConditions', label: 'Health conditions or allergies', type: 'textArea' },
    ],
    modules: { ...NO_MODULES },
  },

  // ── Cycling tours ───────────────────────────────────────────────────
  cyclingTour: {
    subType: 'cyclingTour',
    label: TOURISM_SUB_TYPE_LABELS.cyclingTour,
    bookingUnit: 'slot',
    resourceTermSingular: 'Cycling Tour',
    resourceTermPlural: 'Guides & Bikes',
    bookingTermSingular: 'Tour booking',
    bookingTermPlural: 'Tour bookings',
    equipmentTerm: 'Bikes & Helmets',
    heroActionLabel: "Manage today's rides",
    icon: '🚴',
    themeColor: '#2DD4BF',
    kpis: [
      { id: 'today', label: 'Tours today', source: 'bookings', field: 'today' },
      { id: 'bikeUtilisation', label: 'Bike utilisation', source: 'resources', field: 'utilisation', format: 'percent' },
      { id: 'avgGroup', label: 'Avg group size', source: 'bookings', field: 'avgGroupSize' },
      { id: 'riders', label: 'Riders today', source: 'bookings', field: 'attendeesToday' },
    ],
    resourceColumns: [
      { key: 'name', label: 'Guide / bike' },
      { key: 'capacity', label: 'Group size' },
      { key: 'specialty', label: 'Route' },
      { key: 'status', label: 'Status' },
    ],
    cardFields: [
      { key: 'routeDifficulty', icon: '⛰️', labelTemplate: '{value}' },
      { key: 'bikeSize', icon: '🚲', labelTemplate: 'Size {value}' },
    ],
    bookingFormFields: [
      { key: 'riderHeightCm', label: 'Rider height (cm)', type: 'numberStepper', hint: 'Used to size the bike.' },
      {
        key: 'routeDifficulty',
        label: 'Route difficulty',
        type: 'dropdown',
        options: ['Leisure', 'Moderate', 'Challenging'],
      },
      { key: 'supportVehicle', label: 'Include support vehicle', type: 'checkbox' },
    ],
    modules: { ...NO_MODULES, weather: true },
  },
};

/* The fallback: what a tenant sees when its SubType is null, unrecognised,
 * or its BusinessType is not Tourism at all. Deliberately identical in
 * terminology to the dashboard that existed before this registry, so
 * nothing changes for a clinic or a restaurant. */
export const GENERIC_CONFIG: SubtypeDashboardConfig = {
  subType: 'generic',
  label: 'Dashboard',
  bookingUnit: 'slot',
  resourceTermSingular: 'Resource',
  resourceTermPlural: 'Resources',
  bookingTermSingular: 'Booking',
  bookingTermPlural: 'Bookings',
  equipmentTerm: 'Equipment',
  heroActionLabel: 'View bookings',
  icon: '📊',
  themeColor: 'var(--color-primary)',
  kpis: BASE_KPIS('bookings'),
  resourceColumns: [
    { key: 'name', label: 'Name' },
    { key: 'capacity', label: 'Capacity' },
    { key: 'specialty', label: 'Specialty' },
    { key: 'status', label: 'Status' },
  ],
  cardFields: [],
  bookingFormFields: [],
  modules: { ...NO_MODULES },
};

/** The config for a Tenant.SubType key, or the generic fallback.
 *  Never throws - an unknown sub-type is a dashboard choice, not an error. */
export function getSubtypeConfig(subType?: TourismSubType | null): SubtypeDashboardConfig {
  if (!subType) return GENERIC_CONFIG;
  return CONFIGS[subType] ?? GENERIC_CONFIG;
}

/** Every registered config, for tests and for the booking-type editor's
 *  sub-type picker. */
export const ALL_SUBTYPE_CONFIGS = CONFIGS;
