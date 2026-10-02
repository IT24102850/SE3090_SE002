/// A person with a login on this tenant (api/users, Admin only) — the mobile
/// twin of the web app's Users & Access screen.
///
/// `isApproved` is the gate, not `isActive`: someone who registers themselves
/// exists immediately but cannot sign in until an Admin approves them and
/// gives them a role and a branch. That is why the screen has two lists.
class ManagedUser {
  final String id;
  final String fullName;
  final String email;
  final String phone;

  /// Admin | Manager | Staff — Customers are not managed here.
  final String role;
  final String? branchId;
  final bool isApproved;

  const ManagedUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.branchId,
    required this.isApproved,
  });

  static const roles = ['Admin', 'Manager', 'Staff'];

  ManagedUser copyWith({String? role, String? branchId, bool? isApproved}) => ManagedUser(
        id: id,
        fullName: fullName,
        email: email,
        phone: phone,
        role: role ?? this.role,
        branchId: branchId ?? this.branchId,
        isApproved: isApproved ?? this.isApproved,
      );

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
        id: (json['id'] ?? '').toString(),
        fullName: (json['fullName'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        role: (json['role'] ?? 'Staff').toString(),
        branchId: json['branchId'] as String?,
        isApproved: json['isApproved'] == true,
      );
}

/// Just enough of a branch to choose one when approving a request.
class AccessBranch {
  final String id;
  final String name;

  const AccessBranch({required this.id, required this.name});

  factory AccessBranch.fromJson(Map<String, dynamic> json) => AccessBranch(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );
}
