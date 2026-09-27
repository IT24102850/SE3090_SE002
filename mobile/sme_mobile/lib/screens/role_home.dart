import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'owner/owner_home_screen.dart';

/// Where a signed-in user belongs, decided in one place.
///
/// This used to be decided in main.dart only, and every other screen that
/// finished a sign-in - the old login, business registration - pushed
/// [DashboardScreen] itself. That is how a freshly registered business owner
/// ended up on the customer-shaped dashboard whose management tiles are
/// "coming soon" stubs, with no way through to the workspace that was built
/// for them. Anything that signs someone in calls [roleHome] instead.
const ownerRoles = {'Admin', 'Manager', 'Staff'};

/// Admin, Manager and Staff open on the workspace - the same set of
/// destinations the web sidebar gives them. Customers keep the
/// business-facing dashboard they have always had.
Widget roleHome(String? role) =>
    ownerRoles.contains(role) ? const OwnerHomeScreen() : const DashboardScreen();
