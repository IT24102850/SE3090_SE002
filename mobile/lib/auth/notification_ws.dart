import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// WebSocket notifications service - connects to the agent service and broadcasts events
class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  WebSocketChannel? _channel;

  void connect([String? wsUrl]) {
    if (kIsWeb) return;
    if (_channel != null || _reconnectTimer != null) return;

    final defaultUrl = 'ws://10.0.2.2:8000/ws/workflows';
    final url = wsUrl ?? defaultUrl;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return;
    }

    try {
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {
            // ignore malformed payloads
          }
        },
        onDone: _onDone,
        onError: (_) => _reconnect(),
      );
    } catch (_) {
      _channel = null;
      _reconnect();
    }
  }

  void _onDone() {
    _channel = null;
    _reconnect();
  }

  Timer? _reconnectTimer;
  void _reconnect() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      connect();
    });
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
