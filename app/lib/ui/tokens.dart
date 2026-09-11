import 'package:flutter/widgets.dart';

/// Токены оформления.
///
/// Сняты с веб-клиента — `web/src/styles.css`, — чтобы два клиента были
/// одним приложением, а не двумя похожими. Значения перенесены цвет в цвет:
/// ничего выведенного здесь нет.
///
/// Тема одна, тёмная. В источнике светлой нет вовсе — ни второго набора
/// переменных, ни `prefers-color-scheme`, ни `dark:`-вариантов, — и своя,
/// выведенная «по мотивам», здесь уже была: она и делала два клиента
/// разными на светлом устройстве. Светлую соберём, когда будет светлый
/// макет.
///
/// Контраст не подбирался на глаз, а считался:
///
///   * основной текст на полотне — 16.5:1;
///   * второстепенный — 6.7:1;
///   * приглушённый — 3.5:1. Это ниже 4.5:1 и потому отдано только
///     подсказкам в пустых полях: текста, который надо прочесть, там нет;
///   * тёмная надпись на акценте — 7.1:1. Белая дала бы 2.3:1, поэтому
///     кнопки подписаны почти чёрным;
///   * акцент как текст на полотне — 7.9:1.
abstract final class Tokens {
  // --- Поверхности ---

  /// Полотно приложения.
  static const bg = Color(0xFF0B1117);

  /// Боковая панель, шапки и поле ввода — на полтона светлее полотна.
  static const sidebar = Color(0xFF121A22);

  /// Поверхность карточек и наведённой строки списка.
  static const surface = Color(0xFF1A242E);

  /// Приподнятое: поля ввода, меню, подсказки, тумблеры, кружок аватара,
  /// кнопки без заливки.
  static const elevated = Color(0xFF222E3A);

  static const fg = Color(0xFFE8F0F6);
  static const muted = Color(0xFF8A9BB0);
  static const subtle = Color(0xFF5C6B7A);
  static const border = Color(0xFF24303C);

  /// Пузырь собеседника и свой.
  static const bubbleIn = Color(0xFF1C2732);
  static const bubbleOut = Color(0xFF164A4E);

  // --- Акцент ---

  static const accent = Color(0xFF3DB8B4);

  /// Надпись на акцентной заливке. Тёмная, а не белая: белая даёт 2.3:1.
  static const onAccent = Color(0xFF06201F);

  /// Наведение на акцентную кнопку.
  ///
  /// В источнике это `bg-accent/90` — акцент в девять десятых поверх
  /// полотна. Здесь он сведён к сплошному цвету: полупрозрачная заливка
  /// поверх пузыря или меню дала бы другой оттенок, чем поверх полотна.
  static const accentHover = Color(0xFF38A7A4);

  /// Кольцо фокуса. В источнике `--color-ring` — тот же акцент.
  static const ring = accent;

  /// Присутствие. В источнике это тот же акцент, не отдельный зелёный.
  static const online = accent;

  static const danger = Color(0xFFD45B5B);

  // --- Полотно переписки ---
  //
  // В источнике это `.chat-canvas`: подсвет акцентом из левого верхнего
  // угла и точечная сетка поверх полотна. Доли те же.

  /// Доля акцента в подсвете.
  static const canvasGlow = 0.05;

  /// Радиус подсвета — от ширины полотна.
  static const canvasGlowRadius = 0.38;

  /// Доля основного цвета в точке сетки и её шаг.
  static const canvasDot = 0.05;
  static const canvasDotStep = 24.0;

  // --- Скругления ---
  //
  // Шкала источника: xs 4, sm 8, md 12, lg 16, xl 22.

  static const br4 = 4.0;
  static const br8 = 8.0;
  static const br12 = 12.0;
  static const br16 = 16.0;
  static const br22 = 22.0;

  /// Радиус кнопок и панелей.
  static const radiusShell = 8.0;

  /// Радиус поля ввода.
  static const radiusInput = 12.0;

  // --- Границы ---

  static const borderXs = 0.5;
  static const borderSm = 1.0;
  static const borderMd = 1.5;
  static const borderLg = 2.0;

  // --- Тени ---
  //
  // В источнике их две: волосяная обводка вместо тени у полей, пузырей и
  // кнопок и глубокая мягкая — у всплывающего. Промежуточных нет, и
  // добавлять их здесь значило бы придумать то, чего в системе не
  // предусмотрено.

  /// `--shadow-border: 0 0 0 1px rgb(255 255 255 / 0.08)`.
  static const hairline = Color(0x14FFFFFF);

  static const shadowBorder = [
    BoxShadow(color: hairline, blurRadius: 0, spreadRadius: 1),
  ];
  static const shadowFloat = [
    BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 12)),
  ];

  // --- Движение ---

  /// Длительность переходов.
  static const duration = Duration(milliseconds: 200);

  /// Кривая из источника: cubic-bezier(0.22, 1, 0.36, 1) — быстрый старт и
  /// долгое мягкое торможение.
  static const easeOut = Cubic(0.22, 1, 0.36, 1);

  // --- Отступы ---
  //
  // Кратность четырём: в источнике отступы приходят утилитами Tailwind, а у
  // того шаг как раз четыре пикселя.

  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space8 = 32.0;

  /// Ширина боковой панели: `--width-sidebar: 22.5rem`.
  static const sidebarWidth = 360.0;

  /// Ширина, с которой панель и переписка стоят рядом. Точка `md` Tailwind.
  static const twoPaneFrom = 768.0;
}
