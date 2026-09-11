import 'package:flutter/widgets.dart';

/// Иконки приложения — по роли, а не по картинке.
///
/// Экраны ссылаются на `TitoIcons.send`, а не на конкретную иконку набора.
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
abstract final class TitoIcons {
  // --- Навигация ---

  /// Назад. Подменяет стандартную стрелку Flutter: та из набора Material,
  /// и рядом с остальными иконками выдавала бы смесь двух наборов.
  static const back = IconData(57416, fontFamily: 'Lucide');

  /// Закрыть.
  static const close = IconData(57778, fontFamily: 'Lucide');

  /// Вглубь: строка списка, ведущая на другой экран.
  static const forward = IconData(57455, fontFamily: 'Lucide');

  /// Меню экрана — три точки в шапке.
  static const more = IconData(57527, fontFamily: 'Lucide');

  /// Настройки в шапке боковой панели.
  static const menu = IconData(57621, fontFamily: 'Lucide');

  // --- Разделы ---

  /// Переписки. Он же значок пустой переписки.
  static const chat = IconData(57622, fontFamily: 'Lucide');

  /// Список диалогов.
  static const chats = IconData(58381, fontFamily: 'Lucide');

  /// Контакты.
  static const contacts = IconData(58478, fontFamily: 'Lucide');

  /// Настройки.
  static const settings = IconData(57684, fontFamily: 'Lucide');

  /// Профиль в шапке.
  static const profile = IconData(58465, fontFamily: 'Lucide');

  // --- Действия ---

  /// Отправить сообщение.
  static const send = IconData(57418, fontFamily: 'Lucide');

  /// Новый чат.
  static const compose = IconData(57714, fontFamily: 'Lucide');

  /// Поиск.
  static const search = IconData(57681, fontFamily: 'Lucide');

  /// Прикрепить файл.
  static const attach = IconData(57661, fontFamily: 'Lucide');

  /// Эмодзи.
  static const emoji = IconData(57700, fontFamily: 'Lucide');

  /// Изменить.
  static const edit = IconData(57849, fontFamily: 'Lucide');

  /// Добавить человека.
  static const addPerson = IconData(57762, fontFamily: 'Lucide');

  /// Избранное.
  static const star = IconData(57718, fontFamily: 'Lucide');

  /// Выйти из аккаунта.
  static const logout = IconData(57614, fontFamily: 'Lucide');

  /// Удалить.
  static const delete = IconData(57742, fontFamily: 'Lucide');

  /// Копировать текст сообщения.
  static const copy = IconData(57502, fontFamily: 'Lucide');

  /// «Избранное» — заметки себе.
  static const saved = IconData(57440, fontFamily: 'Lucide');

  /// Закрепить чат и снять закрепление.
  static const pin = IconData(57945, fontFamily: 'Lucide');
  static const unpin = IconData(58038, fontFamily: 'Lucide');

  /// Беззвучный режим и возврат звука.
  static const mute = IconData(57434, fontFamily: 'Lucide');
  static const unmute = IconData(57771, fontFamily: 'Lucide');

  /// Живой перевод переписки.
  static const translate = IconData(57598, fontFamily: 'Lucide');

  // --- Разделы настроек ---

  /// Аккаунт.
  static const account = IconData(58472, fontFamily: 'Lucide');

  /// Уведомления.
  static const bell = IconData(57433, fontFamily: 'Lucide');

  /// Конфиденциальность.
  static const privacy = IconData(57611, fontFamily: 'Lucide');

  /// Данные и хранилище.
  static const storage = IconData(57581, fontFamily: 'Lucide');

  /// Язык.
  static const language = IconData(57576, fontFamily: 'Lucide');

  /// Помощь.
  static const help = IconData(57474, fontFamily: 'Lucide');

  // --- Поля ввода ---

  /// Номер телефона. Не та же трубка, что у звонков: рядом с полем ввода
  /// она читалась бы как «позвонить», а не как «сюда номер».
  static const phone = IconData(57699, fontFamily: 'Lucide');

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

  /// Прочитано.
  static const read = IconData(58254, fontFamily: 'Lucide');

  /// Отправить не удалось.
  static const failed = IconData(57463, fontFamily: 'Lucide');

  // --- Вложения ---

  /// Файл.
  static const file = IconData(57548, fontFamily: 'Lucide');

  /// Картинка.
  static const image = IconData(57590, fontFamily: 'Lucide');

  /// Ссылка.
  static const link = IconData(57602, fontFamily: 'Lucide');

  /// Голосовое сообщение.
  static const voice = IconData(57624, fontFamily: 'Lucide');

  /// Картинку не удалось загрузить.
  static const brokenImage = IconData(57792, fontFamily: 'Lucide');

  /// Весь набор — для проверок в тестах.
  static const all = <IconData>[
    back,
    close,
    forward,
    more,
    menu,
    chat,
    chats,
    contacts,
    settings,
    profile,
    send,
    compose,
    search,
    attach,
    emoji,
    edit,
    addPerson,
    star,
    logout,
    delete,
    copy,
    saved,
    pin,
    unpin,
    mute,
    unmute,
    translate,
    account,
    bell,
    privacy,
    storage,
    language,
    help,
    phone,
    online,
    offline,
    pending,
    sent,
    read,
    failed,
    file,
    image,
    link,
    voice,
    brokenImage,
  ];
}
