import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tito/ui/theme.dart';
import 'package:tito/ui/tokens.dart';

/// Значения сняты с `web/src/styles.css` — того же файла, по которому
/// живёт веб-клиент. Тест держит их на месте: если кто-то «поправит на
/// глаз», два клиента разъедутся, и увидят это не здесь, а на скриншотах
/// через полгода.
void main() {
  group('Токены совпадают с источником', () {
    test('акценты', () {
      expect(Tokens.accent, const Color(0xFF3DB8B4), reason: '--color-accent');
      expect(Tokens.onAccent, const Color(0xFF06201F), reason: '--color-accent-fg');
      expect(Tokens.online, Tokens.accent, reason: '--color-online');
      expect(Tokens.danger, const Color(0xFFD45B5B), reason: '--color-danger');
    });

    test('поверхности тёмной темы', () {
      expect(Tokens.bg, const Color(0xFF0B1117), reason: '--color-bg');
      expect(Tokens.sidebar, const Color(0xFF121A22), reason: '--color-sidebar');
      expect(Tokens.surface, const Color(0xFF1A242E), reason: '--color-surface');
      expect(Tokens.elevated, const Color(0xFF222E3A), reason: '--color-elevated');
      expect(Tokens.border, const Color(0xFF24303C), reason: '--color-border');
    });

    test('текст и пузыри', () {
      expect(Tokens.fg, const Color(0xFFE8F0F6), reason: '--color-fg');
      expect(Tokens.muted, const Color(0xFF8A9BB0), reason: '--color-muted');
      expect(Tokens.subtle, const Color(0xFF5C6B7A), reason: '--color-subtle');
      expect(Tokens.bubbleIn, const Color(0xFF1C2732), reason: '--color-bubble-in');
      expect(Tokens.bubbleOut, const Color(0xFF164A4E), reason: '--color-bubble-out');
    });

    test('границы и скругления', () {
      expect(Tokens.borderXs, 0.5);
      expect(Tokens.borderSm, 1.0);
      expect(Tokens.borderMd, 1.5);
      expect(Tokens.borderLg, 2.0);
      expect(Tokens.br4, 4.0, reason: '--radius-xs');
      expect(Tokens.br8, 8.0, reason: '--radius-sm');
      expect(Tokens.br12, 12.0, reason: '--radius-md');
      expect(Tokens.br16, 16.0, reason: '--radius-lg');
      expect(Tokens.br22, 22.0, reason: '--radius-xl');
      expect(Tokens.radiusShell, Tokens.br8);
      expect(Tokens.radiusInput, Tokens.br12);
    });

    test('переход — единственная длительность 200 мс', () {
      expect(Tokens.duration, const Duration(milliseconds: 200));
    });
  });

  group('Поверхности плоские', () {
    // В источнике нет ни одного backdrop-filter и ни одного blur.
    // Поверхности разделяются границей, а не размытием.
    test('вместо тени у полей — волосяная обводка', () {
      expect(Tokens.shadowBorder.single.blurRadius, 0,
          reason: '--shadow-border это обводка, а не тень');
      expect(Tokens.shadowBorder.single.spreadRadius, 1);
    });

    test('глубокая тень — только у всплывающего', () {
      expect(Tokens.shadowFloat.single.blurRadius, 40,
          reason: '--shadow-float');
      expect(Tokens.shadowFloat.single.offset.dy, 12);
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
      expect(bg.resolve({}), Tokens.accent);
      expect(bg.resolve({WidgetState.hovered}), Tokens.accentHover);
      expect(bg.resolve({WidgetState.pressed}), Tokens.accentInk);
    });

    test('скругление кнопок — радиус панелей', () {
      final shape = TitoTheme.light().filledButtonTheme.style!.shape!
          .resolve({}) as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, Tokens.radiusShell);
    });
  });

  group('Шрифты', () {
    // В вебе это Manrope; во Flutter-сборке лежит Roboto — он же системный
    // шрифт Android, и тянуть второе семейство ради совпадения начертаний
    // значит добавить мегабайт к каждой установке.
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
