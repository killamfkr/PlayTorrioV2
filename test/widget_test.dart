import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:play_torrio_native/screens/main_screen.dart';

void main() {
  testWidgets('App shell loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainScreen(),
      ),
    );
    await tester.pump();
    expect(find.byType(MainScreen), findsOneWidget);
  });
}
