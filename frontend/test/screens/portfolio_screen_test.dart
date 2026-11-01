import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/screens/portfolio_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';

void main() {
  testWidgets('portfolio is an honest disabled placeholder with no samples', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PortfolioScreen(
              palette: themePalettes[GoldBrainTheme.purple]!,
              selectedLanguage: GoldBrainLanguage.persian,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('در به‌روزرسانی اضافه می‌شود؛ درگاه داخلی هنوز ساخته نشده.'),
      findsOneWidget,
    );
    expect(find.textContaining('941,040,000'), findsNothing);
    expect(find.textContaining('10.14'), findsNothing);
    expect(find.textContaining('AI Score'), findsNothing);
  });
}
