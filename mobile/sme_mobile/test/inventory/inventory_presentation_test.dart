import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/inventory_loading_state.dart';
import 'package:sme_mobile/inventory/inventory_panel.dart';
import 'package:sme_mobile/inventory/inventory_scaffold.dart';

void main() {
  testWidgets('reduced motion stops loading pulse and keeps content visible',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: InventoryScaffold(child: InventoryLoadingState()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Loading inventory'), findsOneWidget);
    for (final opacity in tester.widgetList<Opacity>(find.byType(Opacity))) {
      expect(opacity.opacity, 1);
    }
  });

  testWidgets('animated panel invokes its action once and releases its press',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: InventoryScaffold(
        child: Center(
            child: InventoryPanel(
          onTap: () => taps++,
          child: const Text('Open stock'),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Open stock')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
