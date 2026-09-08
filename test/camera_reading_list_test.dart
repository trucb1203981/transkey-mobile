import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/features/translate/widgets/camera_reading_list.dart';
import 'package:transkey_mobile/l10n/generated/app_localizations.dart';

void main() {
  test('reading and copying retain untranslated menu notes in source order',
      () {
    final items = cameraReadingEntries(
        ['Curry', 'Contains peanuts', 'No service charge', ''],
        ['Ca ri', '', '']);
    expect(items.map((e) => e.original),
        ['Curry', 'Contains peanuts', 'No service charge']);
    expect(items.map((e) => e.copyText),
        ['Curry → Ca ri', 'Contains peanuts', 'No service charge']);
    expect(items[1].hasTranslation, isFalse);
  });

  testWidgets('large-font list keeps full notes and explains the source',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = List.filled(8, 'Contains peanuts and milk.').join(' ');
    String? explained;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
        child: CameraReadingList(
          items: cameraReadingEntries(['Curry', note], ['Ca ri', '']),
          onCopyAll: () {},
          onExplain: (source) => explained = source,
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text(note), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    final text = tester.widget<SelectableText>(find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == note));
    expect(text.maxLines, isNull);
    await tester.tap(find.byIcon(Icons.help_outline).first);
    expect(explained, 'Curry');
    expect(tester.takeException(), isNull);
  });
}
