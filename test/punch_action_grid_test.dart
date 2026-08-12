import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeiterfassung_terminal/ui/app_theme.dart';
import 'package:zeiterfassung_terminal/ui/widgets/punch_action_grid.dart';

void main() {
  testWidgets('compact landscape actions fit without scrolling or clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 950,
              height: 120,
              child: PunchActionGrid(
                canPunchIn: false,
                canPunchOut: true,
                canBreakStart: true,
                canBreakEnd: false,
                busy: false,
                compact: true,
                onPunchIn: () {},
                onPunchOut: () {},
                onBreakStart: () {},
                onBreakEnd: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Scrollable), findsNothing);
    final buttons = find.byType(FilledButton);
    expect(buttons, findsNWidgets(4));
    for (var index = 0; index < 4; index++) {
      expect(
        tester.getSize(buttons.at(index)).height,
        greaterThanOrEqualTo(50),
      );
    }
    for (final label in ['Kommen', 'Gehen', 'Pause Start', 'Pause Ende']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(340));
      expect(rect.bottom, lessThanOrEqualTo(460));
    }
    expect(tester.takeException(), isNull);
  });
}
