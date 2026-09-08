enum AppRole { admin, manager, staff }

extension AppRoleLabel on AppRole {
  String get wireValue => switch (this) {
        AppRole.admin => 'Admin',
        AppRole.manager => 'Manager',
        AppRole.staff => 'Staff',
      };

  String get label => wireValue;

  String get description => switch (this) {
        AppRole.admin => 'Full platform access & approvals',
        AppRole.manager => 'Inventory oversight & PO reviews',
        AppRole.staff => 'Stock counts & barcode scans',
      };

  String get defaultEmail => switch (this) {
        AppRole.admin => 'admin@upgradehub.lk',
        AppRole.manager => 'manager@upgradehub.lk',
        AppRole.staff => 'staff@upgradehub.lk',
      };

  static AppRole? fromClaim(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    if (normalized.isEmpty) return null;

    final parts = normalized.split(' ');
    if (parts.contains('admin') || parts.contains('administrator')) {
      return AppRole.admin;
    }
    if (parts.contains('manager')) {
      return AppRole.manager;
    }
    if (parts.contains('staff') || parts.contains('employee')) {
      return AppRole.staff;
    }

    return switch (normalized) {
      'admin' || 'administrator' => AppRole.admin,
      'manager' => AppRole.manager,
      'staff' || 'employee' => AppRole.staff,
      _ => null,
    };
  }
}
