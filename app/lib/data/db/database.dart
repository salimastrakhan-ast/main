import 'package:drift/drift.dart';

import 'connection/connection.dart';

part 'database.g.dart';

/// Локальная база — источник правды для интерфейса.
///
/// Экраны подписаны на её стримы, а не на сокет. Сокет только пишет сюда.
/// Отсюда мгновенный запуск, работа в метро и то, что сообщения не пропадают
/// при закрытии приложения.

/// Состояние отправки. Живёт только на устройстве: сервер о нём не знает.
enum SendState {
  /// Лежит в очереди, ждёт отправки. Рисуется часиками.
  pending,

  /// Ушло на сервер, номер получен.
  sent,

  /// Сервер отказал навсегда — например, выкинули из чата.
  /// Повторять бессмысленно, нужно решение человека.
  failed,
}

class Chats extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get avatarUrl => text().nullable()();

  /// Номер последнего изменения в чате на сервере.
  IntColumn get lastSeq => integer().withDefault(const Constant(0))();

  /// Курсор синхронизации: до какого номера мы всё знаем.
  ///
  /// Отдельно от lastSeq, потому что о существовании более свежих сообщений
  /// мы можем знать, ещё не получив их.
  IntColumn get syncedSeq => integer().withDefault(const Constant(0))();

  IntColumn get lastReadSeq => integer().withDefault(const Constant(0))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  /// Закреплён ли чат и выключен ли в нём звук.
  ///
  /// Настройка личная, а не общая для чата: на сервере она лежит в строке
  /// участника, и у собеседника своя.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get muted => boolean().withDefault(const Constant(false))();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  /// Идентификатор с сервера. У ещё не отправленных совпадает с clientMsgId,
  /// чтобы строку можно было положить в базу до ответа сервера.
  TextColumn get id => text()();
  TextColumn get chatId => text()();

  /// Ноль у неотправленных: настоящий номер выдаёт сервер.
  IntColumn get seq => integer().withDefault(const Constant(0))();
  IntColumn get updatedSeq => integer().withDefault(const Constant(0))();

  TextColumn get senderId => text()();

  /// Не `text`: так называется конструктор колонки у Drift, и getter с этим
  /// именем перекрыл бы его — таблица тихо не сгенерировалась бы.
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get replyToId => text().nullable()();
  TextColumn get clientMsgId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get editedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Вложения в JSON: их немного, отдельная таблица дала бы join на каждый
  /// экран ради двух-трёх строк.
  TextColumn get attachmentsJson => text().nullable()();

  IntColumn get sendState => intEnum<SendState>().withDefault(
    const Constant(1), // sent
  )();

  @override
  Set<Column> get primaryKey => {id};
}

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get username => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get phone => text().nullable()();
  BoolColumn get online => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  /// Есть ли он в моей адресной книге. Знать это надо и офлайн, поэтому
  /// отметка лежит рядом с профилем, а не запрашивается каждый раз.
  BoolColumn get isContact => boolean().withDefault(const Constant(false))();

  /// Избранное — решение человека, оно только на этом устройстве.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ChatMembers extends Table {
  TextColumn get chatId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  IntColumn get lastReadSeq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {chatId, userId};
}

/// Очередь отправки.
///
/// Сообщение попадает сюда до ухода на сервер и покидает очередь только по
/// подтверждению. Поэтому закрытое на середине отправки приложение
/// дошлёт написанное при следующем запуске.
class Outbox extends Table {
  TextColumn get clientMsgId => text()();
  TextColumn get chatId => text().nullable()();

  /// Заполнен, когда чата ещё нет: личный чат заведётся на сервере при
  /// первом сообщении.
  TextColumn get peerId => text().nullable()();

  /// См. Messages.body — имя `text` занято конструктором Drift.
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get replyToId => text().nullable()();
  TextColumn get attachmentIdsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {clientMsgId};
}

/// Настройки приложения — то, что человек выбрал сам.
///
/// Живут в той же базе, а не в отдельном хранилище: одно место для всего
/// локального состояния, одна очистка при выходе. Токены сюда не кладём —
/// им место в защищённом хранилище устройства.
class Prefs extends Table {
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {name};
}

/// Последнее сообщение чата в том виде, в каком его показывает список.
///
/// Отдельный тип, а не `Message`: списку нужны четыре поля из пяти
/// десятков, и тащить полную строку ради подписи незачем.
class LastMessage {
  const LastMessage({
    required this.chatId,
    required this.body,
    required this.senderId,
    required this.deleted,
  });

  final String chatId;
  final String body;
  final String senderId;
  final bool deleted;
}

@DriftDatabase(tables: [Chats, Messages, Users, ChatMembers, Outbox, Prefs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  /// Пересоздавать базу нельзя: в ней лежит вся переписка, и обновление
  /// приложения не повод её потерять. Поэтому каждая версия добавляет своё.
  ///
  ///   2 — таблица настроек, признаки контакта и избранного;
  ///   3 — закрепление и беззвучный режим чата.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(prefs);
        await m.addColumn(users, users.isContact);
        await m.addColumn(users, users.isFavorite);
      }
      if (from < 3) {
        await m.addColumn(chats, chats.pinned);
        await m.addColumn(chats, chats.muted);
      }
    },
  );

  /// Значение настройки. Отсутствие строки — это «не выбирал», и решение
  /// принимает вызывающий: у темы это «как в системе».
  Stream<String?> watchPref(String name) {
    return (select(prefs)..where((t) => t.name.equals(name)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  Future<void> setPref(String name, String value) {
    return into(
      prefs,
    ).insertOnConflictUpdate(PrefsCompanion.insert(name: name, value: value));
  }

  /// Курсоры для команды sync: по каждому чату — до какого номера мы всё
  /// знаем. Это первое, что клиент отправляет после подключения.
  Future<Map<String, int>> syncCursors() async {
    final rows = await select(chats).get();
    return {for (final c in rows) c.id: c.syncedSeq};
  }

  /// Список диалогов: сверху закреплённые, дальше тот, где последнее
  /// движение.
  ///
  /// Не по lastSeq: это номер внутри чата, и между чатами он несравним —
  /// переписка на пятьсот сообщений всегда оказывалась бы выше вчерашней
  /// на три, даже если в ней месяц тишины.
  Stream<List<Chat>> watchChats() {
    return (select(chats)..orderBy([
          (t) => OrderingTerm.desc(t.pinned),
          (t) => OrderingTerm.desc(t.updatedAt),
          (t) => OrderingTerm.desc(t.lastSeq),
        ]))
        .watch();
  }

  /// Закрепление и беззвучный режим. Пишутся сразу, не дожидаясь сервера:
  /// нажатие должно отзываться мгновенно, а команда уйдёт следом.
  Future<void> setChatPinned(String chatId, bool pinned) {
    return (update(chats)..where((t) => t.id.equals(chatId)))
        .write(ChatsCompanion(pinned: Value(pinned)));
  }

  Future<void> setChatMuted(String chatId, bool muted) {
    return (update(chats)..where((t) => t.id.equals(chatId)))
        .write(ChatsCompanion(muted: Value(muted)));
  }

  /// Лента чата. Неотправленные (seq == 0) идут в конце: их место в ленте
  /// определится, когда сервер выдаст номер.
  Stream<List<Message>> watchMessages(String chatId) {
    return (select(messages)
          ..where((t) => t.chatId.equals(chatId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.seq),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .watch();
  }

  Stream<List<User>> watchUsers() => select(users).watch();

  /// Адресная книга: те, кого человек знает. Сортировка по имени — список
  /// читают глазами сверху вниз, и порядок «как пришло с сервера» здесь
  /// ничем не оправдан.
  Stream<List<User>> watchContacts() {
    return (select(users)
          ..where((t) => t.isContact.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.displayName)]))
        .watch();
  }

  /// Личный чат с этим человеком, если он уже заведён.
  ///
  /// На сервере личный чат появляется при первом сообщении, а не при
  /// открытии экрана. Поэтому здесь бывает null, и экран переписки должен
  /// это пережить: пустая лента и поле ввода.
  Stream<String?> watchPrivateChatWith(String peerId) {
    final query = select(chatMembers).join([
      innerJoin(chats, chats.id.equalsExp(chatMembers.chatId)),
    ])..where(chatMembers.userId.equals(peerId) & chats.type.equals('private'));

    return query.watch().map(
      (rows) => rows.isEmpty ? null : rows.first.readTable(chats).id,
    );
  }

  /// Участники чата вместе с профилями.
  Stream<List<({ChatMember member, User user})>> watchMembers(String chatId) {
    final query = select(chatMembers).join([
      innerJoin(users, users.id.equalsExp(chatMembers.userId)),
    ])..where(chatMembers.chatId.equals(chatId));

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (member: row.readTable(chatMembers), user: row.readTable(users)),
      ],
    );
  }

  /// Вложения чата от свежих к старым — для экрана медиа.
  ///
  /// Ищем по непустому полю вложений, а не отдельной таблицей: вложений на
  /// сообщение два-три, и отдельная таблица дала бы join на каждый экран
  /// ради этих двух строк.
  Stream<List<Message>> watchAttachments(String chatId) {
    return (select(messages)
          ..where(
            (t) =>
                t.chatId.equals(chatId) &
                t.attachmentsJson.isNotNull() &
                t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Поиск по сообщениям — по локальной базе, не по серверу.
  ///
  /// Полнотекстового поиска на сервере пока нет, но всё, что человек видел,
  /// и так лежит здесь. Поэтому поиск работает офлайн и отвечает мгновенно;
  /// чего он не найдёт — то, что не успело синхронизироваться.
  Future<List<Message>> searchMessages(String needle, {int limit = 50}) {
    return (select(messages)
          ..where((t) => t.body.like('%$needle%') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> setFavorite(String userId, bool value) {
    return (update(users)..where((t) => t.id.equals(userId)))
        .write(UsersCompanion(isFavorite: Value(value)));
  }

  /// Собеседник каждого чата — по нему подписан личный диалог.
  ///
  /// Раньше список брал имя из общего справочника пользователей: первого,
  /// кто не я. При одном собеседнике это совпадало с правдой, при трёх все
  /// строки показывали одно и то же имя.
  Stream<Map<String, User>> watchChatPeers(String myUserId) {
    final query = select(chatMembers).join([
      innerJoin(users, users.id.equalsExp(chatMembers.userId)),
    ])..where(chatMembers.userId.equals(myUserId).not());

    return query.watch().map((rows) {
      final peers = <String, User>{};
      for (final row in rows) {
        // В группе тут окажется случайный участник, но её подписывает
        // собственное название, а не имя собеседника.
        peers.putIfAbsent(
          row.readTable(chatMembers).chatId,
          () => row.readTable(users),
        );
      }
      return peers;
    });
  }

  /// Последнее сообщение каждого чата — вторая строка в списке диалогов.
  ///
  /// `max(created_at)` рядом с голыми колонками — приём SQLite: значения
  /// берутся именно из той строки, на которой достигнут максимум. Иначе
  /// пришлось бы либо тянуть всю таблицу в память, либо делать подзапрос
  /// на каждый чат.
  Stream<List<LastMessage>> watchLastMessages() {
    return customSelect(
      'SELECT chat_id, body, sender_id, deleted_at, '
      'max(created_at) AS created_at FROM messages GROUP BY chat_id',
      readsFrom: {messages},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          LastMessage(
            chatId: row.read<String>('chat_id'),
            body: row.read<String>('body'),
            senderId: row.read<String>('sender_id'),
            deleted: row.read<DateTime?>('deleted_at') != null,
          ),
      ],
    );
  }

  Future<List<OutboxData>> pendingOutbox() {
    return (select(
      outbox,
    )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();
  }

  /// Стирает данные аккаунта при выходе: устройство может быть общим.
  ///
  /// Настройки при этом остаются. Тема и отметка о показанном приветствии —
  /// свойства устройства, а не аккаунта; сбрасывать их при выходе значит
  /// каждый раз возвращать человеку светлую тему, которую он менял.
  Future<void> clearAll() async {
    await transaction(() async {
      for (final table in allTables) {
        if (table.actualTableName == prefs.actualTableName) continue;
        await delete(table).go();
      }
    });
  }
}
