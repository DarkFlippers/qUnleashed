import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/widgets/progress_button.dart';

void main() {
  testWidgets('can restart indeterminate animation', (tester) async {
    Future<void> pumpButton(bool indeterminate) {
      return tester.pumpWidget(
        MaterialApp(
          home: ProgressButton(
            text: 'TEST',
            color: Colors.orange,
            indeterminate: indeterminate,
          ),
        ),
      );
    }

    await pumpButton(true);
    await pumpButton(false);
    await pumpButton(true);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
