class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String tenantId;
  final String? branchId;
  final String? phone;
  final String? address;
  final String? insuranceProvider;
  final String? insuranceNumber;
  final String? medicalNotes;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.tenantId,
    this.branchId,
    this.phone,
    this.address,
    this.insuranceProvider,
    this.insuranceNumber,
    this.medicalNotes,
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
      address: json['address']?.toString(),
      insuranceProvider: json['insuranceProvider']?.toString(),
      insuranceNumber: json['insuranceNumber']?.toString(),
      medicalNotes: json['medicalNotes']?.toString(),
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
      'address': address,
      'insuranceProvider': insuranceProvider,
      'insuranceNumber': insuranceNumber,
      'medicalNotes': medicalNotes,
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
    String? address,
    String? insuranceProvider,
    String? insuranceNumber,
    String? medicalNotes,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      tenantId: tenantId ?? this.tenantId,
      branchId: branchId ?? this.branchId,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      insuranceProvider: insuranceProvider ?? this.insuranceProvider,
      insuranceNumber: insuranceNumber ?? this.insuranceNumber,
      medicalNotes: medicalNotes ?? this.medicalNotes,
    );
  }
}
