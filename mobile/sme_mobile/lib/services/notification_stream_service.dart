import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'secure_storage_service.dart';

/// One notification, as the server pushes it.
class LiveNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final DateTime createdAt;

  const LiveNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  factory LiveNotification.fromJson(Map<String, dynamic> j) => LiveNotification(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        message: (j['message'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      );
}

enum StreamStatus { connecting, live, offline }

/// Live notifications over Server-Sent Events, from the same ASP.NET Core API
/// everything else uses.
///
/// This replaces a WebSocket client that pointed at ws://10.0.2.2:8000/ws/workflows
/// - a port and a route that do not exist in this system - so the phone was in
/// practice waiting for its next manual refresh. SSE also keeps the spec's
/// rule that the app talks only to ASP.NET Core: the notification never comes
/// from the Python agent service directly.
///
/// The durable record is still the Notifications table. A phone that was in a
/// tunnel misses nothing permanently: it refetches the list on reconnect.
class NotificationStreamService {
  NotificationStreamService._internal();
  static final NotificationStreamService _instance = NotificationStreamService._internal();
  factory NotificationStreamService() => _instance;

  static const _retryBase = Duration(seconds: 1);
  static const _retryMax = Duration(seconds: 30);

  final _notifications = StreamController<LiveNotification>.broadcast();
  final _status = StreamController<StreamStatus>.broadcast();

  /// Every notification for the signed-in user, as it is committed.
  Stream<LiveNotification> get notifications => _notifications.stream;

  /// Connection state, for a "live" dot in the UI.
  Stream<StreamStatus> get status => _status.stream;

  CancelToken? _cancel;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _running = false;

  /// Safe to call repeatedly - a second call while connected does nothing.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _attempt = 0;
    await _connect();
  }

  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancel?.cancel('stopped');
    _cancel = null;
    _status.add(StreamStatus.offline);
  }

  Future<void> _connect() async {
    if (!_running) return;

    final token = await SecureStorageService.getToken();
    if (token == null || token.isEmpty) {
      // Not signed in yet: stay quiet rather than hammering a 401.
      _status.add(StreamStatus.offline);
      _running = false;
      return;
    }

    _status.add(StreamStatus.connecting);
    _cancel = CancelToken();

    try {
      final response = await Dio().get<ResponseBody>(
        '${ApiService.baseUrl}/notifications/stream',
        cancelToken: _cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Authorization': 'Bearer $token', 'Accept': 'text/event-stream'},
          // The whole point is that this connection stays open, so the
          // read timeout that protects ordinary requests must not apply.
          receiveTimeout: Duration.zero,
        ),
      );

      _attempt = 0;
      _status.add(StreamStatus.live);

      var buffer = '';
      await for (final chunk in response.data!.stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);

        // Frames are separated by a blank line, and a chunk can split one
        // anywhere, so an incomplete tail waits for the next chunk.
        var split = buffer.indexOf('\n\n');
        while (split != -1) {
          _handleFrame(buffer.substring(0, split));
          buffer = buffer.substring(split + 2);
          split = buffer.indexOf('\n\n');
        }
      }
      throw StateError('stream closed by server');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (e.response?.statusCode == 401) {
        // The session is gone; the auth interceptor handles the sign-out.
        _running = false;
        _status.add(StreamStatus.offline);
        return;
      }
      _scheduleRetry();
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _handleFrame(String frame) {
    if (frame.startsWith(':')) return; // ": keep-alive"

    var event = 'message';
    final data = <String>[];
    for (final line in frame.split('\n')) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trim());
      }
    }
    if (event != 'notification' || data.isEmpty) return;

    try {
      final decoded = jsonDecode(data.join('\n'));
      if (decoded is Map<String, dynamic>) {
        _notifications.add(LiveNotification.fromJson(decoded));
      }
    } catch (e) {
      // A malformed frame must not take the connection down with it.
      debugPrint('Ignored a malformed notification frame: $e');
    }
  }

  void _scheduleRetry() {
    if (!_running) return;
    _status.add(StreamStatus.offline);
    _attempt++;
    // Exponential backoff, capped: a backend restart should not be met by
    // every phone reconnecting on the same tick.
    final ms = (_retryBase.inMilliseconds * (1 << (_attempt - 1))).clamp(
      _retryBase.inMilliseconds,
      _retryMax.inMilliseconds,
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: ms), _connect);
  }
}
