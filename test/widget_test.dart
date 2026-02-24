import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nstyle_sentinel/main.dart';

void main() {
  testWidgets('renders NStyle Sentinel dashboard shell', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const ProviderScope(child: NStyleSentinelApp()));
    expect(find.text('Initialize Secure System'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Initialize Secure System'),
    );
    await tester.pumpAndSettle();

    expect(find.text('NStyle Sentinel'), findsOneWidget);
    expect(find.text('Toney Approval Queue'), findsOneWidget);
    expect(find.text('Confirm'), findsWidgets);
  });
}
