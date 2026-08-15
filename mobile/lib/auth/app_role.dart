enum AppRole { admin, manager, staff }

extension AppRoleLabel on AppRole {
  String get wireValue => switch (this) {
        AppRole.admin => 'Admin',
        AppRole.manager => 'Manager',
        AppRole.staff => 'Staff',
      };

  static AppRole? fromClaim(String value) => switch (value) {
        'Admin' => AppRole.admin,
        'Manager' => AppRole.manager,
        'Staff' => AppRole.staff,
        _ => null,
      };
}
