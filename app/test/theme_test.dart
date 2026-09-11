import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tito/ui/theme.dart';
import 'package:tito/ui/tokens.dart';

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
      final style = TitoTheme.dark().filledButtonTheme.style;
      final focused = ringOf(style, {WidgetState.focused});
      final fill = fillOf(style, {});

      expect(focused, isNotNull, reason: 'кольцо фокуса не задано');
      expect(focused!.width, greaterThanOrEqualTo(2),
          reason: 'тонкое кольцо незаметно');
      expect(focused.color, isNot(equals(fill)),
          reason: 'кольцо сливается с заливкой кнопки');
    });

    test('на вторичной кнопке заметнее обычного контура', () {
      final style = TitoTheme.dark().outlinedButtonTheme.style;
      final rest = ringOf(style, {});
      final focused = ringOf(style, {WidgetState.focused});

      expect(focused!.color, isNot(equals(rest!.color)),
          reason: 'фокус не отличается от покоя');
      expect(focused.width, greaterThan(rest.width));
    });

    test('цвет кольца — тот же, что у источника', () {
      // `--color-ring` в styles.css это сам акцент, а не затемнённый: тот
      // был выведен ради светлой темы, которой в источнике нет.
      final border = TitoTheme.dark()
          .inputDecorationTheme
          .focusedBorder as OutlineInputBorder;
      expect(border.borderSide.color, Tokens.ring);
      expect(Tokens.ring, Tokens.accent);
    });

    test('заблокированная кнопка выглядит иначе активной', () {
      final style = TitoTheme.dark().filledButtonTheme.style;
      expect(fillOf(style, {WidgetState.disabled}),
          isNot(equals(fillOf(style, {}))));
    });
  });

  group('Палитра', () {
    test('тема одна: светлой в источнике нет', () {
      // Светлая была нашей выдумкой, и на светлом устройстве приложение
      // открывалось в палитре, которой в образце не существует. Проверка
      // ловит попытку завести её обратно «по мотивам».
      expect(TitoTheme.dark().brightness, Brightness.dark);
      expect(TitoTheme.dark().colorScheme.brightness, Brightness.dark);
    });

    test('акцент сохранён точно, без тонального пересчёта Material', () {
      // Ради этого схема собирается руками: ColorScheme.fromSeed прогнал бы
      // бирюзовый через свой алгоритм и выдал похожий, но другой цвет — а
      // он обязан совпадать с веб-клиентом до байта.
      expect(TitoTheme.dark().colorScheme.primary, Tokens.accent);
    });

    test('роли поверхностей разложены по источнику', () {
      final scheme = TitoTheme.dark().colorScheme;
      expect(scheme.surface, Tokens.bg, reason: 'полотно');
      expect(scheme.surfaceContainer, Tokens.sidebar, reason: 'панель и шапки');
      expect(scheme.surfaceContainerHigh, Tokens.surface, reason: 'карточки');
      expect(scheme.surfaceContainerHighest, Tokens.elevated,
          reason: 'поля, меню, аватары');
    });

    test('поле ввода залито цветом полей, а не полотна', () {
      // Было `surfaceContainerLowest` — цвет полотна: поле сливалось с
      // фоном и читалось как вырез, а не как поле.
      expect(TitoTheme.dark().inputDecorationTheme.fillColor, Tokens.elevated);
    });

    test('пузыри взяты из источника', () {
      final scheme = TitoTheme.dark().colorScheme;
      expect(TitoTheme.ownBubble(scheme), Tokens.bubbleOut);
      expect(TitoTheme.otherBubble(scheme), Tokens.bubbleIn);
    });
  });
}
