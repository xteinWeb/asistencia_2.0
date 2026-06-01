import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Simple compile and smoke test', (WidgetTester tester) async {
    // Build a simple scaffold to make sure the testing environment works.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('OK'),
          ),
        ),
      ),
    );
    expect(find.text('OK'), findsOneWidget);
  });
}
