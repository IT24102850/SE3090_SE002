import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_inventory_app/auth/auth_controller.dart';
import 'package:sme_inventory_app/auth/auth_repository.dart';
import 'package:sme_inventory_app/main.dart';

void main() {
  testWidgets('shows the sign-in form when no session exists', (tester) async {
    final auth = AuthController(
      AuthRepository(apiBaseUrl: 'http://localhost:5107'),
    );

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(auth: auth)),
    );

    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
