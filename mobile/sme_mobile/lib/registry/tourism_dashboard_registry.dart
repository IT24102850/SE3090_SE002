import 'package:flutter/material.dart';
import '../models/tourism_subtype.dart';
import '../models/subtype_dashboard_config.dart';

/// The single source of truth for "what makes each tourism business type
/// look and feel distinct". Adding a new sub-type = adding one entry here.
/// Nothing in the screen widgets needs to change.
class TourismDashboardRegistry {
  static final Map<TourismSubType, SubtypeDashboardConfig> _configs = {
    TourismSubType.diving: const SubtypeDashboardConfig(
      subType: TourismSubType.diving,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Dive Trip',
      resourceTermPlural: 'Dive Trips',
      heroActionLabel: 'Choose your dive trip',
      icon: Icons.scuba_diving,
      themeColor: Color(0xFF38BDF8),
      showWeatherBadge: true,
      cardFields: [
        ResourceCardField(key: 'capacity', icon: Icons.groups, labelTemplate: '{value} divers max'),
        ResourceCardField(key: 'depth', icon: Icons.waves, labelTemplate: 'Max depth {value}m'),
      ],
      bookingFormFields: [
        BookingFormField(
          key: 'certificationLevel',
          label: 'Your certification level',
          type: BookingFieldType.dropdown,
          options: ['None', 'Open Water', 'Advanced', 'Rescue Diver'],
        ),
        BookingFormField(key: 'groupSize', label: 'Number of divers', type: BookingFieldType.numberStepper),
        BookingFormField(key: 'equipmentRentalNeeded', label: 'Need equipment rental (BCD, wetsuit, regulator)', type: BookingFieldType.checkbox),
        BookingFormField(key: 'medicalDeclaration', label: 'I confirm I have no medical condition preventing diving', type: BookingFieldType.checkbox),
      ],
    ),

    TourismSubType.safari: const SubtypeDashboardConfig(
      subType: TourismSubType.safari,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Safari Drive',
      resourceTermPlural: 'Safari Drives',
      heroActionLabel: 'Pick a safari drive',
      icon: Icons.directions_car,
      themeColor: Color(0xFFF0A868),
      showWeatherBadge: true,
      cardFields: [
        ResourceCardField(key: 'capacity', icon: Icons.groups, labelTemplate: '{value} seats'),
        ResourceCardField(key: 'timeOfDay', icon: Icons.wb_sunny, labelTemplate: '{value}'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'groupSize', label: 'Number of adults', type: BookingFieldType.numberStepper),
        BookingFormField(key: 'childrenCount', label: 'Number of children (under 12)', type: BookingFieldType.numberStepper),
        BookingFormField(
          key: 'residencyStatus',
          label: 'Residency (park entry fees vary by residency)',
          type: BookingFieldType.dropdown,
          options: ['Foreign visitor', 'Sri Lankan resident', 'SAARC national'],
        ),
        BookingFormField(key: 'parkEntryIncluded', label: 'Include park entry fee', type: BookingFieldType.checkbox),
      ],
    ),

    TourismSubType.whaleWatching: const SubtypeDashboardConfig(
      subType: TourismSubType.whaleWatching,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Boat Trip',
      resourceTermPlural: 'Boat Trips',
      heroActionLabel: 'Choose a departure time',
      icon: Icons.sailing,
      themeColor: Color(0xFF8B5CF6),
      showWeatherBadge: true,
      cardFields: [
        ResourceCardField(key: 'capacity', icon: Icons.groups, labelTemplate: '{value} seats'),
        ResourceCardField(key: 'departureTime', icon: Icons.schedule, labelTemplate: 'Departs {value}'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'groupSize', label: 'Number of guests', type: BookingFieldType.numberStepper),
        BookingFormField(key: 'hotelPickupNeeded', label: 'Need hotel pickup & drop-off', type: BookingFieldType.checkbox),
      ],
    ),

    TourismSubType.surfSchool: const SubtypeDashboardConfig(
      subType: TourismSubType.surfSchool,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Surf Lesson',
      resourceTermPlural: 'Surf Lessons',
      heroActionLabel: 'Book a lesson',
      icon: Icons.surfing,
      themeColor: Color(0xFF22D3EE),
      cardFields: [
        ResourceCardField(key: 'instructor', icon: Icons.person, labelTemplate: 'with {value}'),
      ],
      bookingFormFields: [
        BookingFormField(
          key: 'skillLevel',
          label: 'Skill level',
          type: BookingFieldType.dropdown,
          options: ['Beginner', 'Intermediate', 'Advanced'],
        ),
        BookingFormField(key: 'boardRental', label: 'Rent a board', type: BookingFieldType.checkbox),
        BookingFormField(key: 'wetsuitRental', label: 'Rent a wetsuit', type: BookingFieldType.checkbox),
      ],
    ),

    TourismSubType.trekking: const SubtypeDashboardConfig(
      subType: TourismSubType.trekking,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Guided Trek',
      resourceTermPlural: 'Guided Treks',
      heroActionLabel: 'Choose your trek',
      icon: Icons.hiking,
      themeColor: Color(0xFF4ADE80),
      cardFields: [
        ResourceCardField(key: 'difficulty', icon: Icons.terrain, labelTemplate: '{value} difficulty'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'groupSize', label: 'Group size', type: BookingFieldType.numberStepper),
        BookingFormField(key: 'gearRentalNeeded', label: 'Need gear rental', type: BookingFieldType.checkbox),
        BookingFormField(
          key: 'preferredStartTime',
          label: 'Preferred start',
          type: BookingFieldType.dropdown,
          options: ['Sunrise hike (midnight start)', 'Daytime hike'],
        ),
        BookingFormField(key: 'porterNeeded', label: 'Need a porter for gear', type: BookingFieldType.checkbox),
      ],
    ),

    TourismSubType.culturalTour: const SubtypeDashboardConfig(
      subType: TourismSubType.culturalTour,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Guided Tour',
      resourceTermPlural: 'Guided Tours',
      heroActionLabel: 'Pick a tour',
      icon: Icons.museum,
      themeColor: Color(0xFFE0A87A),
      cardFields: [
        ResourceCardField(key: 'language', icon: Icons.language, labelTemplate: '{value}'),
      ],
      bookingFormFields: [
        BookingFormField(
          key: 'tourType',
          label: 'Private or group',
          type: BookingFieldType.dropdown,
          options: ['Private', 'Group'],
        ),
        BookingFormField(
          key: 'languagePreference',
          label: 'Guide language',
          type: BookingFieldType.dropdown,
          options: ['English', 'German', 'French', 'Chinese', 'Japanese', 'Other'],
        ),
        BookingFormField(key: 'entryTicketsIncluded', label: 'Include site entrance tickets', type: BookingFieldType.checkbox),
      ],
    ),

    TourismSubType.multiDayPackage: const SubtypeDashboardConfig(
      subType: TourismSubType.multiDayPackage,
      bookingUnit: BookingUnit.package,
      resourceTermSingular: 'Itinerary',
      resourceTermPlural: 'Itineraries',
      heroActionLabel: 'Choose your itinerary',
      icon: Icons.map,
      themeColor: Color(0xFFA78BFA),
      cardFields: [
        ResourceCardField(key: 'durationDays', icon: Icons.event, labelTemplate: '{value} days'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'groupSize', label: 'Number of travelers', type: BookingFieldType.numberStepper),
        BookingFormField(
          key: 'accommodationTier',
          label: 'Accommodation tier',
          type: BookingFieldType.dropdown,
          options: ['Budget', 'Standard', 'Luxury'],
        ),
        BookingFormField(
          key: 'mealPlanTier',
          label: 'Meal plan',
          type: BookingFieldType.dropdown,
          options: ['Room only', 'Half board', 'Full board'],
        ),
      ],
    ),

    TourismSubType.accommodation: const SubtypeDashboardConfig(
      subType: TourismSubType.accommodation,
      bookingUnit: BookingUnit.night,
      resourceTermSingular: 'Room',
      resourceTermPlural: 'Rooms',
      heroActionLabel: 'Select your room',
      icon: Icons.hotel,
      themeColor: Color(0xFFE040FB),
      cardFields: [
        ResourceCardField(key: 'bedCount', icon: Icons.bed, labelTemplate: '{value} beds'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'mealPlan', label: 'Include breakfast', type: BookingFieldType.checkbox),
        BookingFormField(key: 'guestCount', label: 'Number of guests', type: BookingFieldType.numberStepper),
        BookingFormField(
          key: 'bedTypePreference',
          label: 'Bed type preference',
          type: BookingFieldType.dropdown,
          options: ['Any', 'Twin', 'Double'],
        ),
        BookingFormField(key: 'specialRequests', label: 'Special requests (e.g. late check-in, allergies)', type: BookingFieldType.textArea),
      ],
    ),

    TourismSubType.villaHotel: const SubtypeDashboardConfig(
      subType: TourismSubType.villaHotel,
      bookingUnit: BookingUnit.night,
      resourceTermSingular: 'Room',
      resourceTermPlural: 'Rooms',
      heroActionLabel: 'Select your room',
      icon: Icons.villa,
      themeColor: Color(0xFFF472B6),
      cardFields: [
        ResourceCardField(key: 'bedCount', icon: Icons.bed, labelTemplate: '{value} beds'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'mealPlan', label: 'Include breakfast', type: BookingFieldType.checkbox),
        BookingFormField(key: 'guestCount', label: 'Number of guests', type: BookingFieldType.numberStepper),
        BookingFormField(
          key: 'bedTypePreference',
          label: 'Bed type preference',
          type: BookingFieldType.dropdown,
          options: ['Any', 'Twin', 'Double'],
        ),
        BookingFormField(key: 'poolAccess', label: 'Private pool access', type: BookingFieldType.checkbox),
        BookingFormField(key: 'airportPickupNeeded', label: 'Need airport pickup & drop-off', type: BookingFieldType.checkbox),
        BookingFormField(key: 'specialRequests', label: 'Special requests (e.g. late check-in, allergies)', type: BookingFieldType.textArea),
      ],
    ),

    TourismSubType.vehicleRental: const SubtypeDashboardConfig(
      subType: TourismSubType.vehicleRental,
      bookingUnit: BookingUnit.dateRange,
      resourceTermSingular: 'Vehicle',
      resourceTermPlural: 'Vehicles',
      heroActionLabel: 'Pick a vehicle',
      icon: Icons.two_wheeler,
      themeColor: Color(0xFF67E8F9),
      cardFields: [
        ResourceCardField(key: 'transmission', icon: Icons.settings, labelTemplate: '{value}'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'driverIncluded', label: 'Include a driver', type: BookingFieldType.checkbox),
        BookingFormField(key: 'drivingPermit', label: 'Upload driving permit', type: BookingFieldType.fileUpload),
        BookingFormField(key: 'childSeatNeeded', label: 'Need a child seat', type: BookingFieldType.checkbox),
      ],
    ),

    TourismSubType.wellness: const SubtypeDashboardConfig(
      subType: TourismSubType.wellness,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Treatment',
      resourceTermPlural: 'Treatments',
      heroActionLabel: 'Choose a treatment',
      icon: Icons.spa,
      themeColor: Color(0xFF86EFAC),
      cardFields: [
        ResourceCardField(key: 'practitioner', icon: Icons.person, labelTemplate: 'with {value}'),
      ],
      bookingFormFields: [
        BookingFormField(
          key: 'treatmentType',
          label: 'Treatment type',
          type: BookingFieldType.dropdown,
          options: ['Ayurveda Massage', 'Herbal Bath', 'Yoga Session'],
        ),
        BookingFormField(
          key: 'therapistGenderPreference',
          label: 'Therapist gender preference',
          type: BookingFieldType.dropdown,
          options: ['No preference', 'Female', 'Male'],
        ),
        BookingFormField(key: 'healthConditions', label: 'Any health conditions or allergies we should know about', type: BookingFieldType.textArea),
      ],
    ),

    TourismSubType.cyclingTour: const SubtypeDashboardConfig(
      subType: TourismSubType.cyclingTour,
      bookingUnit: BookingUnit.slot,
      resourceTermSingular: 'Cycling Tour',
      resourceTermPlural: 'Cycling Tours',
      heroActionLabel: 'Pick a route',
      icon: Icons.directions_bike,
      themeColor: Color(0xFF2DD4BF),
      cardFields: [
        ResourceCardField(key: 'routeDifficulty', icon: Icons.terrain, labelTemplate: '{value}'),
      ],
      bookingFormFields: [
        BookingFormField(key: 'bikeSize', label: 'Bike size', type: BookingFieldType.dropdown, options: ['S', 'M', 'L', 'XL']),
        BookingFormField(
          key: 'fitnessLevel',
          label: 'Fitness level',
          type: BookingFieldType.dropdown,
          options: ['Leisure', 'Moderate', 'Challenging'],
        ),
        BookingFormField(key: 'eBikeOption', label: 'Prefer an e-bike', type: BookingFieldType.checkbox),
      ],
    ),
  };

  static SubtypeDashboardConfig configFor(TourismSubType subType) {
    final config = _configs[subType];
    if (config == null) {
      throw StateError('No dashboard config registered for $subType');
    }
    return config;
  }
}
