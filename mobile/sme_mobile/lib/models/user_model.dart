class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String tenantId;
  final String? branchId;
  final String? phone;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.tenantId,
    this.branchId,
    this.phone,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      role: json['role']?.toString() ?? 'Customer',
      tenantId: json['tenantId']?.toString() ?? '',
      branchId: json['branchId']?.toString(),
      phone: json['phone']?.toString(),
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
      'phone': phone,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    String? role,
    String? tenantId,
    String? branchId,
    String? phone,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      tenantId: tenantId ?? this.tenantId,
      branchId: branchId ?? this.branchId,
      phone: phone ?? this.phone,
    );
  }
}
