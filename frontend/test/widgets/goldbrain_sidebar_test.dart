import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/widgets/goldbrain_sidebar.dart';

void main() {
  const items = [
    GoldBrainSidebarItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    GoldBrainSidebarItem(icon: Icons.show_chart_rounded, label: 'Markets'),
  ];

  Future<void> pumpSidebar(WidgetTester tester, {required bool expanded}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: GoldBrainSidebar(
              palette: themePalettes[GoldBrainTheme.gold]!,
              items: items,
              selectedIndex: 0,
              expanded: expanded,
              onToggleExpanded: () {},
              onSelected: (_) {},
              profileName: 'Test User',
              profileSubtitle: 'Test Profile',
              profileImagePath: '',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('sidebar never creates Tooltip overlays inside its ListView', (
    tester,
  ) async {
    await pumpSidebar(tester, expanded: false);
    expect(find.byType(Tooltip), findsNothing);

    await pumpSidebar(tester, expanded: true);
    await tester.pumpAndSettle();
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('collapsed sidebar keeps accessible navigation labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpSidebar(tester, expanded: false);

      expect(find.bySemanticsLabel('Dashboard'), findsOneWidget);
      expect(find.bySemanticsLabel('Markets'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
