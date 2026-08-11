class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String tenantId;
  final String? branchId;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.tenantId,
    this.branchId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? '',
      role: json['role'] ?? 'Customer',
      tenantId: json['tenantId'] ?? '',
      branchId: json['branchId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'role': role,
      'tenantId': tenantId,
      'branchId': branchId,
    };
  }
}