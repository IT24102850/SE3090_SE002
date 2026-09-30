import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/screens/dashboard_screen.dart';
import 'package:sme_mobile/screens/owner/owner_home_screen.dart';
import 'package:sme_mobile/screens/role_home.dart';

/// Navigation after sign-in: every role lands on the home built for it, and
/// anything unrecognised falls back to the customer dashboard - never to the
/// business workspace.
void main() {
  for (final role in ['Admin', 'Manager', 'Staff']) {
    test('$role opens on the business workspace', () {
      expect(roleHome(role), isA<OwnerHomeScreen>());
    });
  }

  test('Customer opens on the customer dashboard', () {
    expect(roleHome('Customer'), isA<DashboardScreen>());
  });

  for (final role in [null, '', 'SuperAdmin', 'admin']) {
    test('unrecognised role "$role" never reaches the workspace', () {
      expect(roleHome(role), isA<DashboardScreen>());
    });
  }
}
