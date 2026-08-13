class Resource {
  final String id;
  final String tenantId;
  final String? branchId;
  final String name;
  final String? code;
  final String category;
  final String status;
  final String? description;
  final int? capacity;
  final double? hourlyRate;
  final String? specialty;

  const Resource({
    required this.id,
    required this.tenantId,
    this.branchId,
    required this.name,
    this.code,
    required this.category,
    required this.status,
    this.description,
    this.capacity,
    this.hourlyRate,
    this.specialty,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: json['id'].toString(),
      tenantId: json['tenantId'].toString(),
      branchId: json['branchId']?.toString(),
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString(),
      category: json['category']?.toString() ?? 'Other',
      status: json['status']?.toString() ?? 'Available',
      description: json['description']?.toString(),
      capacity: json['capacity'] == null ? null : (json['capacity'] as num).toInt(),
      hourlyRate: json['hourlyRate'] == null ? null : (json['hourlyRate'] as num).toDouble(),
      specialty: json['specialty']?.toString(),
    );
  }
}
