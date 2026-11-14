import 'package:ai_tagebuch/l10n/app_localizations.dart';
import 'package:ai_tagebuch/shared/widgets/ai_consent_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Locale locale, void Function(bool?) onResult) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AiConsentSheet(),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

void _setScreen(WidgetTester tester, Size logicalSize) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = logicalSize * 3;
  addTearDown(tester.view.reset);
}

void main() {
  for (final locale in const [Locale('en'), Locale('de')]) {
    testWidgets('names Google and its services (${locale.languageCode})',
        (tester) async {
      await tester.pumpWidget(_host(locale, (_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Google Cloud Speech-to-Text'), findsOneWidget);
      expect(find.textContaining('Gemini'), findsOneWidget);
    });
  }

  testWidgets('agreeing and declining report different results', (tester) async {
    _setScreen(tester, const Size(430, 932));
    final results = <bool?>[];
    await tester.pumpWidget(_host(const Locale('en'), results.add));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();

    expect(results, [false, true]);
  });

  testWidgets('both choices are reachable on a small iPhone', (tester) async {
    _setScreen(tester, const Size(320, 568));
    final results = <bool?>[];
    await tester.pumpWidget(_host(const Locale('de'), results.add));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Zustimmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zustimmen'));
    await tester.pumpAndSettle();

    expect(results, [true]);
  });
}
