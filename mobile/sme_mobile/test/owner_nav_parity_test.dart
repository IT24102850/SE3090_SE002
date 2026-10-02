import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/screens/owner/owner_nav.dart';

/// Guards the promise that the phone gives an owner everything the web
/// sidebar does.
///
/// This test used to hold a hand-copied list of the web's destinations, and
/// that is exactly how it failed: Disruption Recovery was added to the web
/// sidebar, no one updated the copy, and the test went on passing while the
/// app was missing a screen. A parity guard that is transcribed from the thing
/// it guards only catches the drift someone remembered to tell it about.
///
/// So it now reads `AppLayout.tsx` itself. If the file moves the test says so
/// rather than silently passing on an empty list — a guard that cannot find
/// its source is a guard that is not guarding.
void main() {
  /// Only the owner workspace. A destination the web shows to Customers alone
  /// belongs to the Flutter app's customer tabs, not to this navigation, and
  /// `Customer` is dropped even from entries that also serve staff.
  const ownerRoles = {'Admin', 'Manager', 'Staff'};

  final layout = File('../../frontend/src/shared/components/AppLayout.tsx');

  Map<String, Set<String>> webOwnerNav() {
    final source = layout.readAsStringSync();
    // { path: '/x', label: 'Y', icon: 'z', roles: ['Admin', 'Manager'] }
    final entry = RegExp(
      r"""label:\s*'([^']+)'\s*,\s*icon:\s*'[^']*'\s*,\s*roles:\s*\[([^\]]*)\]""",
    );
    final roleName = RegExp(r"'([A-Za-z]+)'");

    final found = <String, Set<String>>{};
    for (final match in entry.allMatches(source)) {
      final roles = roleName
          .allMatches(match.group(2)!)
          .map((m) => m.group(1)!)
          .where(ownerRoles.contains)
          .toSet();
      if (roles.isEmpty) continue;
      found[match.group(1)!] = roles;
    }
    return found;
  }

  Map<String, OwnerDestination> byLabel() => {
        for (final section in ownerSections)
          for (final destination in section.items) destination.label: destination,
      };

  test('the web sidebar is where it is expected to be', () {
    expect(layout.existsSync(), isTrue,
        reason: 'AppLayout.tsx was not found at ${layout.path}. '
            'Point this test at its new home - do not delete the check.');
    expect(webOwnerNav(), isNotEmpty,
        reason: 'Parsed no destinations out of AppLayout.tsx. The sidebar format '
            'changed and this test is no longer reading it.');
  });

  test('every owner destination in the web sidebar exists in the app', () {
    final app = byLabel();
    final missing = webOwnerNav().keys.where((label) => !app.containsKey(label)).toList();
    expect(missing, isEmpty, reason: 'These web destinations have no Flutter screen: $missing');
  });

  test('each destination is visible to the same roles as on the web', () {
    final app = byLabel();
    final wrong = <String>[];
    for (final entry in webOwnerNav().entries) {
      final destination = app[entry.key];
      if (destination == null) continue;
      for (final role in entry.value) {
        if (!destination.visibleTo(role)) wrong.add('${entry.key} is hidden from $role');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('; '));
  });

  test('an Admin can reach every destination a Manager or Staff member can', () {
    final admin = ownerDestinationsFor('Admin').map((d) => d.label).toSet();
    final others = {
      ...ownerDestinationsFor('Manager').map((d) => d.label),
      ...ownerDestinationsFor('Staff').map((d) => d.label),
    };
    // My Schedule is genuinely Staff-only on the web too: it lists the
    // bookings on the resource linked to that login, which an Admin has none of.
    expect(others.difference(admin), equals({'My Schedule'}));
  });

  test('a Customer sees none of the owner workspace', () {
    expect(ownerDestinationsFor('Customer'), isEmpty);
  });

  test('every destination builds a widget', () {
    for (final section in ownerSections) {
      for (final destination in section.items) {
        expect(destination.build(), isNotNull, reason: '${destination.label} did not build');
      }
    }
  });

  test('Disruption Recovery is reachable for the roles that can approve one', () {
    final destination = byLabel()['Disruption Recovery'];
    expect(destination, isNotNull, reason: 'The Disruption Recovery screen is not in the nav.');
    expect(destination!.visibleTo('Admin'), isTrue);
    expect(destination.visibleTo('Manager'), isTrue);
    // Applying a recovery moves other people's bookings; that is not a Staff
    // decision on the web either.
    expect(destination.visibleTo('Staff'), isFalse);
  });
}
