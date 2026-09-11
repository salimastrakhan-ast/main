import 'package:flutter/widgets.dart';

/// Токены оформления.
///
/// Сняты с веб-клиента — `web/src/styles.css`, — чтобы два клиента были
/// одним приложением, а не двумя похожими. Тёмная тема перенесена цвет в
/// цвет; светлой в источнике нет вовсе, и она выведена здесь, о чём сказано
/// на месте.
///
/// Контраст не подбирался на глаз, а считался. Что из этого вышло:
///
///   * основной текст на полотне — 16.5:1 в тёмной и 17.1:1 в светлой;
///   * второстепенный — 6.7:1 и 5.9:1;
///   * приглушённый — 3.5:1 и 3.3:1. Это ниже 4.5:1 и потому отдано только
///     подсказкам в пустых полях: текста, который надо прочесть, там нет;
///   * тёмная надпись на акценте — 7.1:1. Белая дала бы 2.3:1, поэтому
///     кнопки подписаны почти чёрным;
///   * акцент как текст: на тёмном полотне 7.9:1, на светлом — 2.2:1.
///     Отсюда второй, затемнённый акцент для ссылок в светлой теме.
abstract final class Tokens {
  // --- Тёмная тема: перенесена из источника ---

  /// Полотно приложения.
  static const bg = Color(0xFF0B1117);

  /// Боковая панель и шапки — на полтона светлее полотна.
  static const sidebar = Color(0xFF121A22);

  /// Поверхность карточек и полей.
  static const surface = Color(0xFF1A242E);

  /// Приподнятое: меню, кнопки без заливки, кружок аватара без картинки.
  static const elevated = Color(0xFF222E3A);

  static const fg = Color(0xFFE8F0F6);
  static const muted = Color(0xFF8A9BB0);
  static const subtle = Color(0xFF5C6B7A);
  static const border = Color(0xFF24303C);

  /// Пузырь собеседника и свой.
  static const bubbleIn = Color(0xFF1C2732);
  static const bubbleOut = Color(0xFF164A4E);

  // --- Акцент: один и тот же в обеих темах ---

  static const accent = Color(0xFF3DB8B4);

  /// Надпись на акцентной заливке. Тёмная, а не белая: белая даёт 2.3:1.
  static const onAccent = Color(0xFF06201F);

  /// Наведение на акцентную кнопку.
  ///
  /// В источнике это `bg-accent/90` — акцент в девять десятых поверх
  /// полотна. Здесь он сведён к сплошному цвету: полупрозрачная заливка
  /// поверх пузыря или меню дала бы другой оттенок, чем поверх полотна.
  static const accentHover = Color(0xFF38A7A4);

  /// Акцент как текст на светлом полотне.
  ///
  /// Сам accent там даёт 2.2:1 и не читается — для ссылок и активных
  /// подписей в светлой теме нужен затемнённый.
  static const accentInk = Color(0xFF25706E);

  /// Присутствие. В источнике это тот же акцент, не отдельный зелёный.
  static const online = accent;

  static const danger = Color(0xFFD45B5B);

  /// То же для светлого полотна: исходный даёт 3.4:1.
  static const dangerInk = Color(0xFFB33A3A);

  // --- Светлая тема: наша производная ---
  //
  // В источнике светлой темы нет — он тёмный целиком. Ряд выведен из той же
  // холодной сине-серой гаммы и с тем же акцентом, чтобы переключение темы
  // не выглядело сменой приложения.

  static const lightBg = Color(0xFFF4F7F9);
  static const lightSidebar = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightElevated = Color(0xFFE7EEF3);
  static const lightFg = Color(0xFF0D151C);
  static const lightMuted = Color(0xFF4E6274);
  static const lightSubtle = Color(0xFF7A8B9B);
  static const lightBorder = Color(0xFFDDE5EB);
  static const lightBubbleIn = Color(0xFFFFFFFF);
  static const lightBubbleOut = Color(0xFFCDEBE9);

  // --- Заливки аватаров ---
  //
  // В источнике у людей фотографии, а подложка одна на всех. Пока фотографий
  // нет, одинаковые серые кружки превращают список в частокол, поэтому три
  // заливки из той же гаммы: по ним человек узнаётся в списке, не читая имя.
  // Все три держат букву на 5:1 и различимы на обоих полотнах.

  static const avatarTeal = Color(0xFF2A6F6D);
  static const avatarBlue = Color(0xFF3D6491);
  static const avatarSlate = Color(0xFF5B6473);

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
  // В источнике их две: волосяная обводка вместо тени у полей и кнопок и
  // глубокая мягкая — у всплывающего. Промежуточных нет, и добавлять их
  // здесь значило бы придумать то, чего в системе не предусмотрено.

  static const shadowBorder = [
    BoxShadow(color: Color(0x14FFFFFF), blurRadius: 0, spreadRadius: 1),
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
}
