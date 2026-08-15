class AppNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      isRead: json['isRead'] as bool? ?? false,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}
