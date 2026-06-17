// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Relative import keeps this nested example analyzable from the monorepo root.
// ignore: avoid_relative_lib_imports
import '../lib/app.dart';

void main() {
  testWidgets('Verify Platform version', (WidgetTester tester) async {
    // PlaygroundPage is a Scaffold, so it needs a MaterialApp ancestor.
    await tester.pumpWidget(const MaterialApp(home: PlaygroundPage()));

    // Verify that platform version is retrieved.
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text && widget.data!.startsWith('Running on:'),
      ),
      findsOneWidget,
    );
  });
}
