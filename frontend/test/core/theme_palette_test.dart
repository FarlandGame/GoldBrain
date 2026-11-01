import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/screens/selection_screen.dart';

void main() {
  test('pink and purple are complete and visually distinct palettes', () {
    final pink = themePalettes[GoldBrainTheme.pink];
    final purple = themePalettes[GoldBrainTheme.purple];

    expect(pink, isNotNull);
    expect(purple, isNotNull);
    expect(pink!.primary, isNot(purple!.primary));
    expect(pink.background, isNot(purple.background));
    expect(themePalettes.keys, containsAll(GoldBrainTheme.values));
  });

  test('white theme exposes an actual light accessible palette', () {
    final white = themePalettes[GoldBrainTheme.white];

    expect(white, isNotNull);
    expect(white!.isLight, isTrue);
    expect(white.background.computeLuminance(), greaterThan(0.8));
    expect(white.text.computeLuminance(), lessThan(0.05));
  });

  test('five additional themes use distinct real dark palettes', () {
    const additions = [
      GoldBrainTheme.black,
      GoldBrainTheme.red,
      GoldBrainTheme.orange,
      GoldBrainTheme.deepBlue,
      GoldBrainTheme.brown,
    ];
    final primaries = additions.map((theme) => themePalettes[theme]!.primary);
    expect(primaries.toSet(), hasLength(additions.length));
    for (final theme in additions) {
      final palette = themePalettes[theme]!;
      expect(palette.isLight, isFalse);
      expect(palette.background.computeLuminance(), lessThan(.08));
      expect(palette.text.computeLuminance(), greaterThan(.7));
    }
  });
}
