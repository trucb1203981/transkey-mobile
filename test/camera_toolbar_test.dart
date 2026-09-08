import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/features/translate/widgets/camera_toolbar.dart';

void main() {
  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all preview controls remain usable at $width / $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 812));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final tapped = <String>[];
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 812),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CameraToolbar(
                  sourceLabel: 'Automatically detect source language',
                  targetLabel: 'VI',
                  onClose: () => tapped.add('close'),
                  onSource: () => tapped.add('source'),
                  onTarget: () => tapped.add('target'),
                  onSettings: () => tapped.add('settings'),
                  onFlash: () => tapped.add('flash'),
                  onHelp: () => tapped.add('help'),
                  settingsTooltip: 'Camera settings',
                  helpTooltip: 'Camera tips',
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        final rectangles = <Rect>[];
        for (final name in [
          'close',
          'source',
          'target',
          'settings',
          'flash',
          'help'
        ]) {
          final control = find.byKey(ValueKey('camera-$name'));
          final rect = tester.getRect(control);
          expect(rect.left, greaterThanOrEqualTo(8));
          expect(rect.right, lessThanOrEqualTo(width - 8));
          expect(rect.height, greaterThanOrEqualTo(48));
          for (final other in rectangles) {
            // Ignore floating-point round-off at shared layout edges.
            expect(rect.deflate(0.001).overlaps(other.deflate(0.001)), isFalse,
                reason: '$name $rect overlaps $other');
          }
          rectangles.add(rect);
          await tester.tap(control);
        }
        expect(
            tapped, ['close', 'source', 'target', 'settings', 'flash', 'help']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'result toolbar keeps languages and settings without preview actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: CameraToolbar(
            sourceLabel: 'Auto Detect',
            targetLabel: 'ZH-HANT',
            onClose: () {},
            onSource: () {},
            onTarget: () {},
            onSettings: () {},
            settingsTooltip: 'Camera settings',
            helpTooltip: 'Camera tips',
          ),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('camera-help')), findsNothing);
    expect(find.byKey(const ValueKey('camera-flash')), findsNothing);
    expect(find.byKey(const ValueKey('camera-settings')), findsOneWidget);
    expect(tester.getSize(find.byType(CameraToolbar)).height, 48);
    expect(tester.takeException(), isNull);
  });
}
