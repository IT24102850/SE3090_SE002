import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_model.dart';
import 'api_service_provider.dart';

/// FR-C11/FR-AS21: in-app notifications (booking confirmations, reminders,
/// cancellations, workflow-approval pings). There's no Firebase/APNs
/// credential in this project, so this is genuinely in-app — fetched on
/// open/refresh, not real device push.
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/notifications');
  final data = response.data as Map<String, dynamic>;
  final items = data['items'] as List<dynamic>;
  return items.map((j) => AppNotification.fromJson(j as Map<String, dynamic>)).toList();
});

final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/notifications/unread-count');
  return ((response.data as Map<String, dynamic>)['count'] as num?)?.toInt() ?? 0;
});

Future<void> markNotificationRead(Dio dio, String id) async {
  await dio.put('/notifications/$id/read');
}
