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

  // The whole point of the layout: it compresses to fit rather than scrolling.
  // On every viewport tall enough to hold the card, nothing may overflow and
  // no scroll view may exist to scroll.
  for (final size in const [
    Size(430, 932), // iPhone 15 Pro Max
    Size(393, 852), // Pixel 8
    Size(390, 844), // iPhone 13/14
    Size(360, 740), // common Android
  ]) {
    testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} with no overflow and no scrolling', (tester) async {
      await pumpLogin(tester, size: size);

      // A RenderFlex overflow surfaces here rather than as a failed matcher.
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNothing);

      // Both ends of the composition are actually on screen.
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Browse businesses without an account'), findsOneWidget);
    });
  }

  // Below ~720dp the card alone is taller than the viewport. Scrolling is the
  // honest fallback there - clipping the form would be worse - but it must
  // still never overflow.
  for (final size in const [
    Size(360, 640), // small Android
    Size(320, 568), // iPhone SE 1st gen
  ]) {
    testWidgets('degrades to scrolling, not overflow, at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pumpLogin(tester, size: size);

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Welcome Back'), findsOneWidget);
    });
  }

  testWidgets('scrolls only once the keyboard is up', (tester) async {
    await pumpLogin(tester, size: const Size(390, 844));
    expect(find.byType(SingleChildScrollView), findsNothing);

    // Simulate the keyboard claiming the bottom half of the viewport.
    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
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
