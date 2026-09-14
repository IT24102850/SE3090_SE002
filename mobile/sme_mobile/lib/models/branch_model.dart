class Branch {
  final String id;
  final String name;
  final String address;
  final String phone;

  const Branch({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}
