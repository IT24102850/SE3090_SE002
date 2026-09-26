import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/providers/booking_providers.dart';
import 'package:sme_mobile/services/api_service.dart';

/// "Ask AI to book for you" reported every failure as "The AI planner could
/// not complete this request", including the ones where the planner was never
/// reached. A stopped API and a planner that genuinely refused looked
/// identical, which sends you to debug the AI when the server is simply down.
///
/// These pin each cause to a message that names it.
void main() {
  Dio dioRejectingWith(DioException Function(RequestOptions o) failure) {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:5298/api'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(failure(options)),
    ));
    return dio;
  }

  Future<AiPlanOutcome> run(Dio dio) => findAndBook(
        dio,
        objective: 'Book me the best available option this week',
        bookingTypeId: 'bt-1',
      );

  test('a server that is not running says so, rather than blaming the AI',
      () async {
    final outcome = await run(dioRejectingWith((o) => DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
          error: const SocketException('Connection refused'),
        )));

    expect(outcome.status, 'Rejected');
    expect(outcome.message, contains('Could not reach the server'));
    expect(outcome.message, isNot(contains('AI planner')));
  });

  test('a request that never got a response is also named as unreachable',
      () async {
    // DioExceptionType.unknown wrapping a SocketException is what actually
    // arrives on Android when the host is not listening.
    final outcome = await run(dioRejectingWith((o) => DioException(
          requestOptions: o,
          type: DioExceptionType.unknown,
          error: const SocketException('No route to host'),
        )));

    expect(outcome.message, contains('Could not reach the server'));
  });

  test('a timeout says the server was slow, not that the AI refused', () async {
    final outcome = await run(dioRejectingWith((o) => DioException(
          requestOptions: o,
          type: DioExceptionType.receiveTimeout,
        )));

    expect(outcome.message, contains('took too long'));
  });

  test('an expired session says to sign in again', () async {
    final outcome = await run(dioRejectingWith((o) => DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: o, statusCode: 401),
        )));

    expect(outcome.message, contains('session has expired'));
  });

  test('a server error reports the status instead of the AI', () async {
    final outcome = await run(dioRejectingWith((o) => DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: o, statusCode: 500),
        )));

    expect(outcome.message, contains('500'));
    expect(outcome.message, isNot(contains('AI planner')));
  });

  test("the planner's own refusal is shown word for word", () async {
    // The case the generic message was meant for: the API answered, and the
    // safety gate said no. That reason must survive to the screen.
    final outcome = await run(dioRejectingWith((o) => DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: o,
            statusCode: 422,
            data: const {
              'message': 'No Whale Watching departures have space this week.',
            },
          ),
        )));

    expect(outcome.status, 'Rejected');
    expect(outcome.message,
        'No Whale Watching departures have space this week.');
  });

  test('a 422 with no reason still falls back to the planner wording',
      () async {
    final outcome = await run(dioRejectingWith((o) => DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: o, statusCode: 422, data: null),
        )));

    expect(outcome.message, 'The AI planner could not complete this request.');
  });

  group('the AI call gets a budget that fits an LLM pipeline', () {
    test('find-and-book waits minutes, not the 15s CRUD default', () async {
      // The pipeline makes several Gemini calls and a dozen tool calls back
      // into the API. At 15s the client gave up while the server went on to
      // finish and return 200, so a planned booking was reported as a
      // failure. Anything under a minute reintroduces that.
      Duration? used;
      final dio = Dio(BaseOptions(
        baseUrl: 'http://localhost:5298/api',
        receiveTimeout: const Duration(seconds: 15),
      ));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          used = options.receiveTimeout;
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
        },
      ));

      await findAndBook(dio,
          objective: 'anything', bookingTypeId: 'bt-1');

      expect(used, isNotNull);
      expect(used!.inSeconds, greaterThanOrEqualTo(60),
          reason: 'an LLM pipeline routinely runs past a minute');
    });

    test('the shared option does not shorten the connect timeout', () {
      // Only the receive budget should grow: a genuinely unreachable host
      // must still fail fast rather than hang for three minutes.
      expect(ApiService.aiPipelineOptions.receiveTimeout, isNotNull);
    });
  });
}
