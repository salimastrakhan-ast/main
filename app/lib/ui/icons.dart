import 'package:flutter/widgets.dart';

/// Иконки приложения — по роли, а не по картинке.
///
/// Экраны ссылаются на `MayakIcons.send`, а не на конкретную иконку набора.
/// Из-за этого смена набора — правка одного файла, а не поиск по всему
/// проекту; и по имени сразу видно, что элемент делает.
///
/// Набор — Lucide: геометрический штрих в два пикселя с круглыми концами,
/// ровно то спокойное начертание, к которому приведён остальной интерфейс.
///
/// Шрифт лежит в assets и объявлен в pubspec одним семейством. Пакет
/// lucide_icons_flutter не используется намеренно: он объявляет семь
/// семейств под разные толщины, и шесть неиспользуемых попадали в сборку
/// целиком — 2.7 МБ мёртвого веса при том, что нужный шрифт ужимается до
/// пяти килобайт. Для мессенджера на мобильных сетях это неприемлемо.
///
/// Каждая константа объявлена через `const IconData` полностью, без
/// вспомогательной функции: отсечение неиспользуемых глифов при сборке
/// работает только по константам, а через функцию в шрифт попал бы весь
/// набор целиком.
///
/// Lucide распространяется под лицензией ISC, отметка — в NOTICE.
abstract final class MayakIcons {
  // --- Навигация ---

  /// Назад. Подменяет стандартную стрелку Flutter: та из набора Material,
  /// и рядом с остальными иконками выдавала бы смесь двух наборов.
  static const back = IconData(57416, fontFamily: 'Lucide');

  /// Закрыть.
  static const close = IconData(57778, fontFamily: 'Lucide');

  // --- Действия ---

  /// Отправить сообщение.
  static const send = IconData(57418, fontFamily: 'Lucide');

  /// Выйти из аккаунта.
  static const logout = IconData(57614, fontFamily: 'Lucide');

  // --- Разделы ---

  /// Профиль в шапке.
  static const profile = IconData(58465, fontFamily: 'Lucide');

  /// Переписка: пустой чат.
  static const chat = IconData(57622, fontFamily: 'Lucide');

  /// Список диалогов: пусто.
  static const chats = IconData(58381, fontFamily: 'Lucide');

  // --- Поля ввода ---

  /// Номер телефона.
  static const phone = IconData(57651, fontFamily: 'Lucide');

  // --- Состояние связи ---

  /// На связи.
  static const online = IconData(57774, fontFamily: 'Lucide');

  /// Связи нет — он же значок ошибки загрузки.
  static const offline = IconData(57775, fontFamily: 'Lucide');

  // --- Состояние сообщения ---

  /// Ждёт отправки.
  static const pending = IconData(57479, fontFamily: 'Lucide');

  /// Отправлено.
  static const sent = IconData(57452, fontFamily: 'Lucide');

  /// Отправить не удалось.
  static const failed = IconData(57463, fontFamily: 'Lucide');

  // --- Вложения ---

  /// Файл.
  static const file = IconData(57548, fontFamily: 'Lucide');

  /// Картинку не удалось загрузить.
  static const brokenImage = IconData(57792, fontFamily: 'Lucide');

  /// Весь набор — для проверок в тестах.
  static const all = <IconData>[
    back,
    close,
    send,
    logout,
    profile,
    chat,
    chats,
    phone,
    online,
    offline,
    pending,
    sent,
    failed,
    file,
    brokenImage,
  ];
}
