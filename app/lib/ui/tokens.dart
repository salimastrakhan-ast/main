import 'package:flutter/widgets.dart';

/// Токены оформления.
///
/// Значения не подобраны на глаз, а сняты с публичного CSS claude.com:
/// шкала серых, акценты с состояниями, скругления, тени, толщины границ и
/// длительности переходов. Поэтому здесь нет «примерно похожих» чисел —
/// каждое либо взято оттуда, либо помечено как наше решение.
///
/// Две вещи оттуда перенести нельзя, и обе отмечены на месте:
/// шрифты (лицензионные) и стекло (его там попросту нет).
abstract final class Tokens {
  // --- Серая шкала ---
  //
  // Двадцать одна ступень от белого до чёрного. Тёплая: это не серый, а
  // обесцвеченный бежевый, отсюда общее ощущение бумаги.

  static const gray000 = Color(0xFFFFFFFF);
  static const gray050 = Color(0xFFFAF9F5);
  static const gray100 = Color(0xFFF5F4ED);
  static const gray150 = Color(0xFFF0EEE6);
  static const gray200 = Color(0xFFE8E6DC);
  static const gray250 = Color(0xFFDEDCD1);
  static const gray300 = Color(0xFFD1CFC5);
  static const gray350 = Color(0xFFC2C0B6);
  static const gray400 = Color(0xFFB0AEA5);
  static const gray450 = Color(0xFF9C9A92);
  static const gray500 = Color(0xFF87867F);
  static const gray550 = Color(0xFF73726C);
  static const gray600 = Color(0xFF5E5D59);
  static const gray650 = Color(0xFF4D4C48);
  static const gray700 = Color(0xFF3D3D3A);
  static const gray750 = Color(0xFF30302E);
  static const gray800 = Color(0xFF262624);
  static const gray850 = Color(0xFF1F1E1D);
  static const gray900 = Color(0xFF1A1918);
  static const gray950 = Color(0xFF141413);
  static const gray1000 = Color(0xFF000000);

  // --- Акценты ---

  /// Основной акцент. В их системе называется clay.
  static const clay = Color(0xFFD97757);

  /// Наведение на акцентную кнопку.
  static const clayHover = Color(0xFFC6613F);

  /// Нажатие и кольцо фокуса — у них focus определён именно через него.
  static const clayDark = Color(0xFFC46849);

  static const sky = Color(0xFF6A9BCC);
  static const olive = Color(0xFF788C5D);
  static const error = Color(0xFFBF4D43);

  // --- Скругления ---
  //
  // Шкала из их CSS. В интерфейсе чаще всего встречаются 8, 12, 16 и 24.

  static const br2 = 2.0;
  static const br4 = 4.0;
  static const br6 = 6.0;
  static const br8 = 8.0;
  static const br12 = 12.0;
  static const br16 = 16.0;
  static const br24 = 24.0;
  static const br32 = 32.0;

  /// Радиус кнопок и панелей — у них это shell-radius.
  static const radiusShell = 8.0;

  /// Радиус поля ввода — отдельное значение, не из общей шкалы.
  static const radiusInput = 10.0;

  // --- Границы ---

  static const borderXs = 0.5;
  static const borderSm = 1.0;
  static const borderMd = 1.5;
  static const borderLg = 2.0;

  // --- Тени ---
  //
  // Очень мягкие: непрозрачность 0x0a — это четыре процента. Тень здесь
  // не отрывает элемент от фона, а лишь намекает на слой.

  static const shadowSm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const shadowMd = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 20, offset: Offset(0, 4)),
  ];
  static const shadowLg = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  // --- Движение ---

  /// Единственная длительность в их системе: почти все переходы — 0.2s.
  static const duration = Duration(milliseconds: 200);

  // --- Отступы ---
  //
  // Кратность четырём — это уже наше решение: в их CSS отступы приходят
  // утилитами Tailwind, а у того шаг как раз четыре пикселя.

  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
}
