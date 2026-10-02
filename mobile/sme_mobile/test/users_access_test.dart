import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/managed_user_model.dart';
import 'package:sme_mobile/providers/owner_providers.dart';
import 'package:sme_mobile/screens/owner/resources/users_access_screen.dart';
import 'package:sme_mobile/services/access_repository.dart';
import 'package:sme_mobile/widgets/ui/neon_button.dart';

/// Users & Access on the phone. What has to hold here is that the two states
/// which look alike stay apart — someone who can sign in, and someone who
/// registered and cannot — and that every change names who it affected.
class _Api implements HttpClientAdapter {
  _Api(this.answer);
  final (int, Object) Function(RequestOptions) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(options);
    final (status, body) = answer(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _user({
  required String id,
  required String name,
  String role = 'Staff',
  bool approved = true,
  String? branchId = 'br1',
}) =>
    {
      'id': id,
      'fullName': name,
      'email': '$id@tenant.test',
      'phone': '+94770000000',
      'role': role,
      'branchId': branchId,
      'isApproved': approved,
    };

/// Routes the three directory reads; anything else falls to the handler.
(int, Object) _directory(RequestOptions o, {(int, Object)? write}) {
  if (o.path == '/users/pending') {
    return (200, [_user(id: 'p1', name: 'Amara Perera', role: 'Manager', approved: false, branchId: null)]);
  }
  if (o.path == '/users/branches') {
    return (200, [
      {'id': 'br1', 'name': 'Mirissa Harbour'}
    ]);
  }
  if (o.path == '/users' && o.method == 'GET') {
    return (200, [_user(id: 'u1', name: 'Nihal Nandana', role: 'Manager')]);
  }
  return write ?? (200, {});
}

Widget _host(Dio dio) => ProviderScope(
      overrides: [accessRepositoryProvider.overrideWithValue(AccessRepository(dio))],
      child: const MaterialApp(home: UsersAccessScreen()),
    );

void main() {
  group('ManagedUser', () {
    test('defaults an unknown role to Staff rather than crashing', () {
      expect(ManagedUser.fromJson({'id': 'u1'}).role, 'Staff');
    });

    test('treats a missing isApproved as not approved', () {
      // Fail closed: an unreadable row must not look like someone with access.
      expect(ManagedUser.fromJson({'id': 'u1'}).isApproved, isFalse);
    });
  });

  group('accessErrorMessage', () {
    test('403 says who is allowed, not "Forbidden"', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/users'),
        response: Response(requestOptions: RequestOptions(path: '/users'), statusCode: 403),
      );
      expect(accessErrorMessage(error, 'fallback'), 'Only an Admin can manage users.');
    });
  });

  group('UsersAccessScreen', () {
    late _Api api;
    late Dio dio;

    Future<void> pump(WidgetTester tester, {(int, Object)? write}) async {
      api = _Api((o) => _directory(o, write: write));
      dio = Dio(BaseOptions(baseUrl: 'http://api.test/api'))..httpClientAdapter = api;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(600, 2600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(dio));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps people waiting for approval apart from people with access',
        (tester) async {
      await pump(tester);

      expect(find.text('WAITING FOR APPROVAL'), findsOneWidget);
      expect(find.text('Amara Perera'), findsOneWidget);
      expect(find.text('PEOPLE WITH ACCESS'), findsOneWidget);
      expect(find.text('Nihal Nandana'), findsOneWidget);
    });

    testWidgets('approving sends the role and a branch, and names the person',
        (tester) async {
      await pump(tester, write: (200, {}));

      await tester.tap(find.widgetWithText(NeonButton, 'Approve'));
      await tester.pumpAndSettle();

      final approved = api.requests.firstWhere((r) => r.path.contains('/approve'));
      final body = approved.data as Map<String, dynamic>;
      expect(approved.method, 'PUT');
      expect(body['role'], 'Manager');
      // The request had no branch, so the only branch there is gets used.
      expect(body['branchId'], 'br1');
      expect(find.textContaining('Amara Perera can now sign in'), findsOneWidget);
    });

    testWidgets('changing a role sends the whole user back with password null',
        (tester) async {
      await pump(tester, write: (200, {}));

      await tester.tap(find.byKey(const Key('role-u1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();

      final put = api.requests.firstWhere((r) => r.method == 'PUT');
      final body = put.data as Map<String, dynamic>;
      expect(body['role'], 'Admin');
      expect(body['fullName'], 'Nihal Nandana');
      // Omitting it would read as a password change.
      expect(body.containsKey('password'), isTrue);
      expect(body['password'], isNull);
    });

    testWidgets('removing someone asks first and does nothing if declined',
        (tester) async {
      await pump(tester, write: (200, {}));

      await tester.tap(find.byTooltip('Remove Nihal Nandana'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Nihal Nandana?'), findsOneWidget);

      await tester.tap(find.text('Keep them'));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });

    testWidgets('a non-Admin is told who is allowed, not shown a bare error',
        (tester) async {
      api = _Api((_) => (403, {'message': 'Forbidden'}));
      dio = Dio(BaseOptions(baseUrl: 'http://api.test/api'))..httpClientAdapter = api;
      await tester.pumpWidget(_host(dio));
      await tester.pumpAndSettle();

      expect(find.text('Only an Admin can manage users.'), findsOneWidget);
    });

    testWidgets('no pending requests means no waiting section at all', (tester) async {
      api = _Api((o) {
        if (o.path == '/users/pending') return (200, <dynamic>[]);
        return _directory(o);
      });
      dio = Dio(BaseOptions(baseUrl: 'http://api.test/api'))..httpClientAdapter = api;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(600, 2600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(dio));
      await tester.pumpAndSettle();

      expect(find.text('WAITING FOR APPROVAL'), findsNothing);
      expect(find.text('PEOPLE WITH ACCESS'), findsOneWidget);
    });
  });
}
