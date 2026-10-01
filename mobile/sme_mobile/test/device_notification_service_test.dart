import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/services/device_notification_service.dart';
import 'package:sme_mobile/services/notification_stream_service.dart';

class _FakePresenter implements NotificationPresenter {
  int inits = 0;
  final shown = <(int, String, String)>[];
  bool failInit = false;

  @override
  Future<void> init() async {
    inits++;
    if (failInit) throw Exception('no plugin');
  }

  @override
  Future<void> show(int id, String title, String body) async => shown.add((id, title, body));
}

LiveNotification _n(String id, {String title = 'Booking approved', String message = 'See you at 10:00'}) =>
    LiveNotification(id: id, type: 'Booking', title: title, message: message, createdAt: DateTime(2026));

void main() {
  late StreamController<LiveNotification> source;
  late _FakePresenter presenter;
  late int starts, stops;
  late DeviceNotificationService service;

  setUp(() {
    source = StreamController<LiveNotification>.broadcast();
    presenter = _FakePresenter();
    starts = 0;
    stops = 0;
    service = DeviceNotificationService(
      presenter: presenter,
      source: source.stream,
      startStream: () async => starts++,
      stopStream: () async => stops++,
    );
  });

  tearDown(() => source.close());

  test('raises a device notification for each live notification', () async {
    await service.start();

    source.add(_n('a'));
    source.add(_n('b', title: 'Low stock', message: 'Gloves below reorder level'));
    await pumpEventQueue();

    expect(presenter.shown.map((s) => s.$2), ['Booking approved', 'Low stock']);
    expect(presenter.shown.last.$3, 'Gloves below reorder level');
    expect(starts, 1);
  });

  test('shows a replayed notification only once', () async {
    await service.start();

    source.add(_n('a'));
    source.add(_n('a'));
    await pumpEventQueue();

    expect(presenter.shown, hasLength(1));
  });

  test('starting twice does not double-subscribe or re-initialise', () async {
    await service.start();
    await service.start();

    source.add(_n('a'));
    await pumpEventQueue();

    expect(presenter.shown, hasLength(1));
    expect(presenter.inits, 1);
    expect(starts, 1);
  });

  test('after sign-out nothing more is shown', () async {
    await service.start();
    await service.stop();

    source.add(_n('a'));
    await pumpEventQueue();

    expect(presenter.shown, isEmpty);
    expect(stops, 1);
    expect(service.isRunning, isFalse);
  });

  test('a failed plugin start never blocks the stream', () async {
    presenter.failInit = true;

    await service.start();

    expect(service.isRunning, isTrue);
    expect(starts, 1);
  });

  test('a blank title falls back to the app name', () async {
    await service.start();

    source.add(_n('a', title: '  '));
    await pumpEventQueue();

    expect(presenter.shown.single.$2, 'Unify');
  });
}
