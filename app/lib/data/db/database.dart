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

@DriftDatabase(tables: [Chats, Messages, Users, ChatMembers, Outbox])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  /// Курсоры для команды sync: по каждому чату — до какого номера мы всё
  /// знаем. Это первое, что клиент отправляет после подключения.
  Future<Map<String, int>> syncCursors() async {
    final rows = await select(chats).get();
    return {for (final c in rows) c.id: c.syncedSeq};
  }

  Stream<List<Chat>> watchChats() {
    return (select(chats)..orderBy([(t) => OrderingTerm.desc(t.lastSeq)]))
        .watch();
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

  Future<List<OutboxData>> pendingOutbox() {
    return (select(outbox)..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  Future<void> clearAll() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
}
