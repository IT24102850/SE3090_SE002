// Smoke test: the app boots under ProviderScope without crashing and shows
// its initial splash screen while auth restores from secure storage.
//
// This replaced the default Flutter counter-app template test, which was
// already stale (MyApp requires ProviderScope and has no counter UI).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sme_mobile/main.dart';

void main() {
  testWidgets('App boots under ProviderScope and shows the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
