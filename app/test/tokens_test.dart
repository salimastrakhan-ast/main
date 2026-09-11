import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tito/ui/theme.dart';
import 'package:tito/ui/tokens.dart';

/// Значения сняты с публичного CSS claude.com. Тест держит их на месте:
/// если кто-то «поправит на глаз», это сразу видно, а не всплывёт через
/// полгода расхождением по всему интерфейсу.
void main() {
  group('Токены совпадают с источником', () {
    test('акценты', () {
      expect(Tokens.clay, const Color(0xFFD97757), reason: '--color-clay');
      expect(Tokens.clayHover, const Color(0xFFC6613F), reason: '--color-clay-hover');
      expect(Tokens.clayDark, const Color(0xFFC46849), reason: '--color-clay-dark');
      expect(Tokens.sky, const Color(0xFF6A9BCC), reason: '--color-sky');
      expect(Tokens.olive, const Color(0xFF788C5D), reason: '--color-olive');
      expect(Tokens.error, const Color(0xFFBF4D43), reason: '--color-error');
    });

    test('края серой шкалы и опорные ступени', () {
      expect(Tokens.gray050, const Color(0xFFFAF9F5), reason: 'полотно');
      expect(Tokens.gray200, const Color(0xFFE8E6DC), reason: 'свой пузырь');
      expect(Tokens.gray400, const Color(0xFFB0AEA5), reason: 'границы');
      expect(Tokens.gray800, const Color(0xFF262624), reason: 'тёмная поверхность');
      expect(Tokens.gray950, const Color(0xFF141413), reason: 'текст и тёмное полотно');
    });

    test('границы и скругления', () {
      expect(Tokens.borderXs, 0.5);
      expect(Tokens.borderSm, 1.0);
      expect(Tokens.borderMd, 1.5);
      expect(Tokens.borderLg, 2.0);
      expect(Tokens.radiusShell, 8.0, reason: '--shell-radius');
      expect(Tokens.radiusInput, 10.0, reason: '--shell-radius-input');
    });

    test('переход — единственная длительность 200 мс', () {
      expect(Tokens.duration, const Duration(milliseconds: 200));
    });
  });

  group('Поверхности плоские', () {
    // У них в CSS нет ни одного backdrop-filter и ни одного blur.
    // Поверхности разделяются границей и очень мягкой тенью.
    test('тени едва заметны', () {
      expect(Tokens.shadowSm.single.color.a, closeTo(0.04, 0.01),
          reason: 'тень не должна отрывать элемент от фона');
      expect(Tokens.shadowMd.single.color.a, closeTo(0.04, 0.01));
    });

    test('окна и панели без подъёма', () {
      for (final theme in [TitoTheme.light(), TitoTheme.dark()]) {
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
      }
    });
  });

  group('Кнопки', () {
    test('наведение и нажатие берут их же цвета', () {
      final style = TitoTheme.light().filledButtonTheme.style!;
      final bg = style.backgroundColor!;
      expect(bg.resolve({}), Tokens.clay);
      expect(bg.resolve({WidgetState.hovered}), Tokens.clayHover);
      expect(bg.resolve({WidgetState.pressed}), Tokens.clayDark);
    });

    test('скругление кнопок — их shell-radius', () {
      final shape = TitoTheme.light().filledButtonTheme.style!.shape!
          .resolve({}) as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, Tokens.radiusShell);
    });
  });

  group('Шрифты', () {
    // Фирменные шрифты лицензионные. Их собственный запасной вариант —
    // system-ui; на телефонах это родной шрифт системы.
    test('одно семейство на весь интерфейс', () {
      for (final theme in [TitoTheme.light(), TitoTheme.dark()]) {
        final families = {
          theme.textTheme.headlineMedium?.fontFamily,
          theme.textTheme.bodyMedium?.fontFamily,
          theme.textTheme.labelSmall?.fontFamily,
        }..remove(null);
        expect(families.length, lessThanOrEqualTo(1),
            reason: 'в теме больше одного шрифта: $families');
      }
    });

    test('цифры одной ширины у меток', () {
      expect(TitoTheme.light().textTheme.labelSmall?.fontFeatures,
          TitoTheme.tabularFigures);
    });
  });
}
