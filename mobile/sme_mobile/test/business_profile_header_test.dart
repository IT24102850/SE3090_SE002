import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/tenant_profile_model.dart';
import 'package:sme_mobile/widgets/business_profile_header.dart';

TenantProfile _profile({
  String? logoUrl,
  String? coverImageUrl,
  List<String> galleryImageUrls = const [],
  int reviewCount = 0,
  double? averageRating,
  List<BusinessHourEntry> businessHours = const [],
}) {
  return TenantProfile(
    tenantId: 't1',
    name: 'Weligama Bay Dive Center',
    businessType: 'Tourism',
    logoUrl: logoUrl,
    coverImageUrl: coverImageUrl,
    galleryImageUrls: galleryImageUrls,
    description: 'A great dive center.',
    shortTagline: 'PADI 5-Star Dive Center',
    amenities: const ['Free WiFi', 'Parking'],
    contactPhone: null,
    contactEmail: null,
    website: null,
    socialLinks: const {},
    businessHours: businessHours,
    averageRating: averageRating,
    reviewCount: reviewCount,
    address: null,
  );
}

Future<void> pumpHeader(WidgetTester tester, TenantProfile profile, {DateTime? now}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: BusinessProfileHeader(
          businessName: profile.name,
          profile: profile,
          themeColor: const Color(0xFF0077B6),
          themeIcon: Icons.scuba_diving,
          now: now,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders cover image, logo, and gallery from mock data', (tester) async {
    final profile = _profile(
      logoUrl: 'https://example.com/logo.jpg',
      coverImageUrl: 'https://example.com/cover.jpg',
      galleryImageUrls: ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    );
    await pumpHeader(tester, profile);

    final networkImages = tester.widgetList<Image>(find.byType(Image)).where((w) => w.image is NetworkImage).map((w) => (w.image as NetworkImage).url).toList();

    expect(networkImages, contains('https://example.com/logo.jpg'));
    expect(networkImages, contains('https://example.com/cover.jpg'));
    expect(networkImages, contains('https://example.com/1.jpg'));
    expect(networkImages, contains('https://example.com/2.jpg'));
  });

  testWidgets('rating row is hidden when reviewCount is 0', (tester) async {
    await pumpHeader(tester, _profile(reviewCount: 0));
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('rating row is shown when reviewCount is greater than 0', (tester) async {
    await pumpHeader(tester, _profile(reviewCount: 42, averageRating: 4.8));
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('(42)'), findsOneWidget);
  });

  testWidgets('shows "Open now" when the mock time is within today\'s hours', (tester) async {
    // A Wednesday at 10:00, with Wednesday hours 09:00-17:00.
    final wednesday10am = DateTime(2026, 8, 19, 10, 0); // 2026-08-19 is a Wednesday
    expect(wednesday10am.weekday, DateTime.wednesday);

    final profile = _profile(businessHours: [
      const BusinessHourEntry(dayOfWeek: 'Wednesday', openTime: '09:00', closeTime: '17:00', isClosed: false),
    ]);
    await pumpHeader(tester, profile, now: wednesday10am);

    expect(find.text('Open now'), findsOneWidget);
    expect(find.text('Closed now'), findsNothing);
  });

  testWidgets('shows "Closed now" when the mock time is outside today\'s hours', (tester) async {
    final wednesday9pm = DateTime(2026, 8, 19, 21, 0); // after the 17:00 close
    expect(wednesday9pm.weekday, DateTime.wednesday);

    final profile = _profile(businessHours: [
      const BusinessHourEntry(dayOfWeek: 'Wednesday', openTime: '09:00', closeTime: '17:00', isClosed: false),
    ]);
    await pumpHeader(tester, profile, now: wednesday9pm);

    expect(find.text('Closed now'), findsOneWidget);
    expect(find.text('Open now'), findsNothing);
  });

  testWidgets('missing logoUrl/coverImageUrl falls back to the theme icon/color, not a broken image', (tester) async {
    final profile = _profile(logoUrl: null, coverImageUrl: null);
    await pumpHeader(tester, profile);

    // No NetworkImage should be attempted for logo/cover when both are null.
    final networkImages = tester.widgetList<Image>(find.byType(Image)).where((w) => w.image is NetworkImage).toList();
    expect(networkImages, isEmpty);

    // The passed-in fallback icon must be shown instead.
    expect(find.byIcon(Icons.scuba_diving), findsOneWidget);
  });

  testWidgets('shows a skeleton, not a blank screen, while profile is loading', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BusinessProfileHeader(
          businessName: 'Loading Co',
          profile: null,
          themeColor: Color(0xFF0077B6),
          themeIcon: Icons.scuba_diving,
        ),
      ),
    ));
    await tester.pump();

    // No exception thrown, and the loading UI renders something (skeleton boxes).
    expect(tester.takeException(), isNull);
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('shows a retry button on error without crashing', (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessProfileHeader(
          businessName: 'Error Co',
          profile: null,
          hasError: true,
          onRetry: () => retried = true,
          themeColor: const Color(0xFF0077B6),
          themeIcon: Icons.scuba_diving,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
