import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/screens/unify_auth/unify_login_screen.dart';

/// Smoke coverage for the Unify sign-in screen. The hero animates forever, so
/// every wait here is an explicit [WidgetTester.pump] — `pumpAndSettle` would
/// spin until it timed out.
///
/// Nothing here signs in for real: that path goes through `authProvider` to
/// the backend, so these tests stop at the validation gate, which is the part
/// this screen actually owns.
void main() {
  /// The default 800x600 test surface is shorter than the screen's content, so
  /// the Sign In button ends up outside the render tree and taps miss it. Pump
  /// against a phone-shaped viewport instead.
  Future<void> pumpLogin(
    WidgetTester tester, {
    Size size = const Size(430, 1240),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: UnifyLoginScreen())),
    );
    await tester.pump();
  }

  testWidgets('renders the branding, hero and form', (tester) async {
    await pumpLogin(tester);

    expect(find.text('Enterprise Management System'), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Or continue with'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the account-free browse route reachable', (tester) async {
    await pumpLogin(tester);

    expect(find.text('Browse businesses without an account'), findsOneWidget);
  });

  testWidgets('scrolls rather than overflowing on a short viewport', (tester) async {
    await pumpLogin(tester, size: const Size(320, 560));

    expect(tester.takeException(), isNull);
    await tester.drag(find.text('Welcome Back'), const Offset(0, -300));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocks sign in until the email and password validate', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Enter your work email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('password visibility toggles', (tester) async {
    await pumpLogin(tester);

    EditableText passwordField() =>
        tester.widgetList<EditableText>(find.byType(EditableText)).last;

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('social buttons report that they are not wired up yet', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.byIcon(Icons.apple));
    await tester.pump();

    expect(find.textContaining('coming soon'), findsOneWidget);
  });
}
