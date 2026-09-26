import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/screens/owner/owner_nav.dart';

/// Guards the promise that the phone gives an owner everything the web
/// sidebar does. The expected list is copied from
/// `frontend/src/shared/components/AppLayout.tsx` — every NAV_SECTIONS entry
/// whose roles include Admin, Manager or Staff. The customer section is
/// deliberately absent: those destinations are the Flutter app's customer
/// tabs, not part of the owner workspace.
void main() {
  // label -> the roles the web sidebar shows it to.
  const webOwnerNav = <String, List<String>>{
    'Dashboard': ['Admin', 'Manager', 'Staff'],
    'Reports': ['Admin', 'Manager'],
    'Booking Manager': ['Admin', 'Manager', 'Staff'],
    'My Schedule': ['Staff'],
    'Multi-Branch Schedule': ['Admin', 'Manager'],
    'Booking Types': ['Admin', 'Manager'],
    'Billing Dashboard': ['Admin', 'Manager'],
    'Invoices': ['Admin', 'Manager', 'Staff'],
    'Subscriptions': ['Admin', 'Manager', 'Staff'],
    'Insurance Claims': ['Admin', 'Manager', 'Staff'],
    'Commission Rules': ['Admin', 'Manager', 'Staff'],
    'Billing Agent': ['Admin', 'Manager'],
    'Invoice Designer': ['Admin', 'Manager'],
    'Form Builder': ['Admin', 'Manager'],
    'Payment Gateways': ['Admin'],
    'Resource Manager': ['Admin', 'Manager'],
    'Staff': ['Admin', 'Manager'],
    'Branches': ['Admin'],
    'Inventory Manager': ['Admin', 'Manager', 'Staff'],
    'Stock Movements': ['Admin', 'Manager', 'Staff'],
    'Purchase Orders': ['Admin', 'Manager', 'Staff'],
    'Low Stock Alerts': ['Admin', 'Manager', 'Staff'],
    'Branch Overview': ['Admin', 'Manager', 'Staff'],
    'Inventory Analytics': ['Admin', 'Manager'],
    'Schedule Copilot': ['Admin', 'Manager'],
    'Agent Workflows': ['Admin', 'Manager', 'Staff'],
    'Business Profile': ['Admin', 'Manager'],
    'Business Settings': ['Admin'],
  };

  Map<String, OwnerDestination> byLabel() => {
        for (final section in ownerSections)
          for (final destination in section.items) destination.label: destination,
      };

  test('every owner destination in the web sidebar exists in the app', () {
    final app = byLabel();
    final missing = webOwnerNav.keys.where((label) => !app.containsKey(label)).toList();
    expect(missing, isEmpty, reason: 'These web destinations have no Flutter screen: $missing');
  });

  test('each destination is visible to the same roles as on the web', () {
    final app = byLabel();
    final wrong = <String>[];
    for (final entry in webOwnerNav.entries) {
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
}
