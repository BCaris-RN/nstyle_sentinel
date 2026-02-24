import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nstyle_sentinel/presentation/splash_view.dart';

void main() {
  testWidgets(
    'SplashView adheres to NStyle typography and touch target constraints',
    (WidgetTester tester) async {
      var entered = false;

      await tester.pumpWidget(
        MaterialApp(home: SplashView(onEnter: () => entered = true)),
      );

      final displayFinder = find.text('NStyle\nSentinel');
      expect(displayFinder, findsOneWidget);

      final Text textWidget = tester.widget(displayFinder);
      expect(
        textWidget.style?.fontSize,
        64.0,
        reason: 'VIOLATION: Display text must be exactly 64px.',
      );

      final buttonFinder = find.byType(ElevatedButton);
      expect(buttonFinder, findsOneWidget);

      final buttonSize = tester.getSize(buttonFinder);
      expect(
        buttonSize.height,
        greaterThanOrEqualTo(44.0),
        reason: 'VIOLATION: Button fails 44px touch target minimum.',
      );

      await tester.tap(buttonFinder);
      expect(entered, true);
    },
  );
}
