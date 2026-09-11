import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tito/ui/theme.dart';

/// Цвет кольца фокуса у кнопки в заданном состоянии.
BorderSide? ringOf(ButtonStyle? style, Set<WidgetState> states) =>
    style?.side?.resolve(states);

Color? fillOf(ButtonStyle? style, Set<WidgetState> states) =>
    style?.backgroundColor?.resolve(states);

void main() {
  group('Кольцо фокуса', () {
    // Кольцо цветом акцента на кнопке того же акцента невидимо, и человек с
    // клавиатурой перестаёт понимать, где находится. Проверяем, что цвета
    // кольца и заливки различаются.
    test('на главной кнопке отличается от её заливки', () {
      for (final theme in [TitoTheme.light(), TitoTheme.dark()]) {
        final style = theme.filledButtonTheme.style;
        final focused = ringOf(style, {WidgetState.focused});
        final fill = fillOf(style, {});

        expect(focused, isNotNull, reason: 'кольцо фокуса не задано');
        expect(focused!.width, greaterThanOrEqualTo(2),
            reason: 'тонкое кольцо незаметно');
        expect(focused.color, isNot(equals(fill)),
            reason: 'кольцо сливается с заливкой кнопки');
      }
    });

    test('на вторичной кнопке заметнее обычного контура', () {
      for (final theme in [TitoTheme.light(), TitoTheme.dark()]) {
        final style = theme.outlinedButtonTheme.style;
        final rest = ringOf(style, {});
        final focused = ringOf(style, {WidgetState.focused});

        expect(focused!.color, isNot(equals(rest!.color)),
            reason: 'фокус не отличается от покоя');
        expect(focused.width, greaterThan(rest.width));
      }
    });

    test('заблокированная кнопка выглядит иначе активной', () {
      final theme = TitoTheme.light();
      final style = theme.filledButtonTheme.style;
      expect(fillOf(style, {WidgetState.disabled}), isNot(equals(fillOf(style, {}))));
    });
  });

  group('Палитра', () {
    test('светлая и тёмная схемы не совпадают', () {
      expect(TitoTheme.light().colorScheme.surface,
          isNot(equals(TitoTheme.dark().colorScheme.surface)));
    });

    test('акцент сохранён точно, без тонального пересчёта Material', () {
      // Ради этого схема собирается руками: ColorScheme.fromSeed прогнал бы
      // коралловый через свой алгоритм и выдал похожий, но другой цвет.
      const coral = Color(0xFFD97757);
      expect(TitoTheme.light().colorScheme.primary, coral);
      expect(TitoTheme.dark().colorScheme.primary, coral);
    });

    test('цвет аватара закреплён за человеком', () {
      final first = TitoTheme.accentFor('user-42');
      expect(TitoTheme.accentFor('user-42'), first,
          reason: 'цвет обязан быть одинаковым между запусками');
      expect(TitoTheme.accentFor('user-43'), isNot(equals(first)),
          reason: 'разные люди не должны сливаться в один цвет');
    });
  });
}
