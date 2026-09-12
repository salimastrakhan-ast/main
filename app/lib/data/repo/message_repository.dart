import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../contacts/device_contacts.dart';
import '../db/database.dart';
import '../ws/envelope.dart';
import '../ws/transport.dart';

/// Единственный источник правды для интерфейса.
///
/// Правило простое: UI читает только из локальной базы и пишет только через
/// репозиторий. Сокет никогда не разговаривает с экранами напрямую — он
/// пишет в базу, а база будит подписчиков.
///
/// Отсюда всё поведение, которого ждут от мессенджера: список чатов есть
/// сразу при запуске, отправленное видно мгновенно, а закрытое на середине
/// отправки приложение дошлёт написанное при следующем запуске.
class MessageRepository {
  MessageRepository({
    required this.db,
    required this.ws,
    required this.api,
    required this.myUserId,
  }) {
    _subscription = ws.events.listen(_onEvent);
    ws.onReady = _onConnected;
  }

  final AppDatabase db;
  final MessageTransport ws;
  final ApiClient api;
  final String myUserId;

  static const _uuid = Uuid();
  StreamSubscription<Envelope>? _subscription;
  bool _draining = false;
  bool _drainAgain = false;

  Stream<List<Chat>> watchChats() => db.watchChats();
  Stream<List<Message>> watchMessages(String chatId) =>
      db.watchMessages(chatId);
  Stream<List<User>> watchUsers() => db.watchUsers();
  Stream<Map<String, User>> watchChatPeers() => db.watchChatPeers(myUserId);
  Stream<List<LastMessage>> watchLastMessages() => db.watchLastMessages();

  // --- Отправка ---

  /// Кладёт сообщение в базу и в очередь, затем пытается отправить.
  ///
  /// Возврат происходит сразу после записи: человек видит своё сообщение
  /// мгновенно, а доставка — забота фоновой очереди.
  Future<void> send({
    String? chatId,
    String? peerId,
    required String text,
    String? replyToId,
    List<String> attachmentIds = const [],
  }) async {
    assert(chatId != null || peerId != null, 'нужен chatId или peerId');

    final clientMsgId = _uuid.v4();
    final now = DateTime.now();

    await db.transaction(() async {
      if (chatId != null) {
        // Пока чата нет (пишем новому собеседнику), рисовать сообщение
        // некуда — оно появится, когда сервер заведёт чат и вернёт его id.
        await db
            .into(db.messages)
            .insert(
              MessagesCompanion.insert(
                id: clientMsgId,
                chatId: chatId,
                senderId: myUserId,
                body: Value(text),
                replyToId: Value(replyToId),
                clientMsgId: clientMsgId,
                createdAt: now,
                sendState: const Value(SendState.pending),
              ),
            );
      }
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              clientMsgId: clientMsgId,
              chatId: Value(chatId),
              peerId: Value(peerId),
              body: Value(text),
              replyToId: Value(replyToId),
              attachmentIdsJson: Value(
                attachmentIds.isEmpty ? null : jsonEncode(attachmentIds),
              ),
              createdAt: now,
            ),
          );
    });

    unawaited(drainOutbox());
  }

  /// Дошлёт всё, что лежит в очереди.
  ///
  /// Вызывается после отправки, после подключения и при возврате в сеть.
  /// Флаг не даёт двум вызовам отправить одно и то же дважды.
  ///
  /// Ошибок наружу не выпускает: обрыв связи посреди отправки — обычное дело,
  /// и всплывать необработанным он не должен. На первом же таком обрыве
  /// перебор прекращается — во-первых, следующие всё равно не уйдут,
  /// во-вторых, так сохраняется порядок сообщений.
  Future<void> drainOutbox() async {
    if (ws.currentState != WsStatus.online) return;
    if (_draining) {
      // Кто-то уже разгребает. Просто выйти нельзя: он прочитал очередь до
      // того, как в неё легло новое сообщение, и оно осталось бы ждать
      // следующего повода. Просим его пройти ещё круг.
      _drainAgain = true;
      return;
    }

    _draining = true;
    try {
      do {
        _drainAgain = false;
        for (final item in await db.pendingOutbox()) {
          if (!await _trySend(item)) return;
        }
      } while (_drainAgain);
    } finally {
      _draining = false;
    }
  }

  /// Возвращает false, если связь пропала и продолжать перебор бессмысленно.
  Future<bool> _trySend(OutboxData item) async {
    try {
      final result = await ws.call(Cmd.messageSend, {
        if (item.chatId != null) 'chat_id': item.chatId,
        if (item.peerId != null) 'peer_id': item.peerId,
        'text': item.body,
        'client_msg_id': item.clientMsgId,
        if (item.replyToId != null) 'reply_to_id': item.replyToId,
        if (item.attachmentIdsJson != null)
          'attachment_ids': jsonDecode(item.attachmentIdsJson!),
      });

      final message = result['message'] as Map<String, dynamic>;
      await db.transaction(() async {
        // Черновик лежал под временным идентификатором — заменяем его
        // строкой с сервера, иначе сообщение задвоится в ленте.
        await (db.delete(
          db.messages,
        )..where((t) => t.id.equals(item.clientMsgId))).go();
        await _upsertMessage(message, state: SendState.sent);
        await (db.delete(
          db.outbox,
        )..where((t) => t.clientMsgId.equals(item.clientMsgId))).go();
      });
      return true;
    } on ProtocolException catch (e) {
      if (e.isPermanent) {
        // Например, выкинули из чата. Повторять нечего — показываем отказ,
        // дальше решает человек.
        await db.transaction(() async {
          await (db.update(
            db.messages,
          )..where((t) => t.id.equals(item.clientMsgId))).write(
            const MessagesCompanion(sendState: Value(SendState.failed)),
          );
          await (db.delete(
            db.outbox,
          )..where((t) => t.clientMsgId.equals(item.clientMsgId))).go();
        });
        return true;
      }
      // Связь пропала — оставляем в очереди, повторим при подключении.
      await (db.update(db.outbox)
            ..where((t) => t.clientMsgId.equals(item.clientMsgId)))
          .write(OutboxCompanion(attempts: Value(item.attempts + 1)));
      return false;
    }
  }

  Future<void> edit(String chatId, String messageId, String text) async {
    final result = await ws.call(Cmd.messageEdit, {
      'chat_id': chatId,
      'message_id': messageId,
      'text': text,
    });
    await _upsertMessage(result['message'] as Map<String, dynamic>);
  }

  Future<void> delete(String chatId, String messageId) async {
    final result = await ws.call(Cmd.messageDelete, {
      'chat_id': chatId,
      'message_id': messageId,
    });
    await _upsertMessage(result['message'] as Map<String, dynamic>);
  }

  Future<void> markRead(String chatId, int upToSeq) async {
    // Локально помечаем сразу: счётчик непрочитанного не должен ждать сети.
    await (db.update(db.chats)..where((t) => t.id.equals(chatId))).write(
      ChatsCompanion(lastReadSeq: Value(upToSeq), unreadCount: const Value(0)),
    );
    try {
      await ws.call(Cmd.read, {'chat_id': chatId, 'up_to_seq': upToSeq});
    } on ProtocolException {
      // Отметка не критична: она доедет со следующим открытием чата.
    }
  }

  void sendTyping(String chatId) => ws.notify(Cmd.typing, {'chat_id': chatId});

  /// Закрепляет чат или снимает закрепление.
  ///
  /// Настройка личная: на сервере она лежит в строке участника, и у
  /// собеседника своя. Локально пишем сразу — список должен перестроиться
  /// от нажатия, а не от ответа сервера.
  Future<void> setPinned(String chatId, bool pinned) async {
    await db.setChatPinned(chatId, pinned);
    try {
      await ws.call(Cmd.chatPin, {'chat_id': chatId, 'pinned': pinned});
    } on ProtocolException {
      // Связь пропала — вернём как было, иначе список врёт о том, чего на
      // сервере не произошло.
      await db.setChatPinned(chatId, !pinned);
      rethrow;
    }
  }

  /// «Без звука навсегда» в терминах срока: столетие вперёд.
  ///
  /// У сервера беззвучный режим со сроком — «на час» просят чаще вечной
  /// тишины, — а в интерфейсе тумблер. Отдельного «навсегда» в протоколе
  /// нет, и заводить его ради тумблера значило бы менять протокол под
  /// интерфейс.
  static Duration get _forever => const Duration(days: 365 * 100);

  Future<void> setMuted(String chatId, bool muted) async {
    await db.setChatMuted(chatId, muted);
    try {
      await ws.call(Cmd.chatMute, {
        'chat_id': chatId,
        if (muted)
          'until': DateTime.now().toUtc().add(_forever).toIso8601String(),
      });
    } on ProtocolException {
      await db.setChatMuted(chatId, !muted);
      rethrow;
    }
  }

  Future<String> createGroup(String title, List<String> memberIds) async {
    final result = await ws.call(Cmd.chatCreate, {
      'title': title,
      'member_ids': memberIds,
    });
    return (result['chat'] as Map<String, dynamic>)['id'] as String;
  }

  Future<void> leaveChat(String chatId) =>
      ws.call(Cmd.chatLeave, {'chat_id': chatId});

  /// Удаляет чат: у себя или, если это своя группа, у всех.
  Future<void> deleteChat(String chatId, {bool forEveryone = false}) =>
      ws.call(Cmd.chatDelete, {
        'chat_id': chatId,
        if (forEveryone) 'for_everyone': true,
      });

  /// Исключает участника из группы. Право проверяет сервер.
  Future<void> removeMember(String chatId, String userId) =>
      ws.call(Cmd.chatRemoveMember, {'chat_id': chatId, 'user_id': userId});

  /// Добавляет участников в группу.
  Future<void> addMembers(String chatId, List<String> userIds) =>
      ws.call(Cmd.chatAddMember, {'chat_id': chatId, 'user_ids': userIds});

  /// Догружает страницу истории вверх от самого старого известного сообщения.
  Future<int> loadOlder(String chatId) async {
    final oldest =
        await (db.select(db.messages)
              ..where(
                (t) => t.chatId.equals(chatId) & t.seq.isBiggerThanValue(0),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.seq)])
              ..limit(1))
            .getSingleOrNull();

    final page = await api.history(chatId, beforeSeq: oldest?.seq ?? 0);
    await db.transaction(() async {
      for (final raw in page) {
        await _upsertMessage(raw as Map<String, dynamic>);
      }
    });
    return page.length;
  }

  // --- Приём ---

  Future<void> _onConnected() async {
    await _sync();
    await drainOutbox();
  }

  /// Спрашивает у сервера всё, что пропустили, начиная с локальных курсоров.
  Future<void> _sync() async {
    final cursors = await db.syncCursors();
    final result = await ws.call(Cmd.sync, {'cursors': cursors});

    await db.transaction(() async {
      for (final raw in (result['chats'] as List<dynamic>? ?? const [])) {
        await _upsertSummary(raw as Map<String, dynamic>);
      }
      for (final raw in (result['deltas'] as List<dynamic>? ?? const [])) {
        final delta = raw as Map<String, dynamic>;
        final chatId = delta['chat_id'] as String;

        for (final m in (delta['messages'] as List<dynamic>? ?? const [])) {
          await _upsertMessage(m as Map<String, dynamic>);
        }

        // Курсор двигаем только если чат приехал целиком. При truncated
        // остаток надо дочитать через историю, и до тех пор в ленте дыра.
        final truncated = delta['truncated'] as bool? ?? false;
        if (!truncated) {
          await (db.update(db.chats)..where((t) => t.id.equals(chatId))).write(
            ChatsCompanion(syncedSeq: Value(delta['last_seq'] as int? ?? 0)),
          );
        }
      }
    });
  }

  void _onEvent(Envelope envelope) {
    switch (envelope.type) {
      case Ev.messageNew:
      case Ev.messageEdited:
      case Ev.messageDeleted:
        final message = envelope.data?['message'] as Map<String, dynamic>?;
        if (message != null) unawaited(_upsertMessage(message));
      case Ev.chatUpdate:
        unawaited(_onChatUpdate(envelope.data));
      case Ev.readUpdate:
        unawaited(_onReadUpdate(envelope.data));
      case Ev.presence:
        unawaited(_onPresence(envelope.data));
    }
  }

  Future<void> _onChatUpdate(Map<String, dynamic>? data) async {
    if (data == null) return;
    final summary = data['chat'] as Map<String, dynamic>?;
    if (summary == null) return;

    final chatId = (summary['chat'] as Map<String, dynamic>)['id'] as String;
    if (data['gone'] == true) {
      await db.transaction(() async {
        await (db.delete(
          db.messages,
        )..where((t) => t.chatId.equals(chatId))).go();
        await (db.delete(
          db.chatMembers,
        )..where((t) => t.chatId.equals(chatId))).go();
        await (db.delete(db.chats)..where((t) => t.id.equals(chatId))).go();
      });
      return;
    }
    await _upsertSummary(summary);
  }

  Future<void> _onReadUpdate(Map<String, dynamic>? data) async {
    if (data == null) return;
    await db
        .into(db.chatMembers)
        .insertOnConflictUpdate(
          ChatMembersCompanion.insert(
            chatId: data['chat_id'] as String,
            userId: data['user_id'] as String,
            lastReadSeq: Value(data['last_read_seq'] as int? ?? 0),
          ),
        );
  }

  Future<void> _onPresence(Map<String, dynamic>? data) async {
    if (data == null) return;
    final lastSeen = data['last_seen'] as String?;
    await (db.update(
      db.users,
    )..where((t) => t.id.equals(data['user_id'] as String))).write(
      UsersCompanion(
        online: Value(data['online'] as bool? ?? false),
        lastSeenAt: Value(lastSeen == null ? null : DateTime.parse(lastSeen)),
      ),
    );
  }

  // --- Запись в базу ---

  Future<void> _upsertMessage(
    Map<String, dynamic> raw, {
    SendState state = SendState.sent,
  }) async {
    final seq = raw['seq'] as int? ?? 0;
    final chatId = raw['chat_id'] as String;
    final attachments = raw['attachments'] as List<dynamic>?;

    await db
        .into(db.messages)
        .insertOnConflictUpdate(
          MessagesCompanion.insert(
            id: raw['id'] as String,
            chatId: chatId,
            seq: Value(seq),
            updatedSeq: Value(raw['updated_seq'] as int? ?? seq),
            senderId: raw['sender_id'] as String,
            body: Value(raw['text'] as String? ?? ''),
            replyToId: Value(raw['reply_to_id'] as String?),
            clientMsgId: raw['client_msg_id'] as String? ?? raw['id'] as String,
            createdAt: DateTime.parse(raw['created_at'] as String),
            editedAt: Value(_date(raw['edited_at'])),
            deletedAt: Value(_date(raw['deleted_at'])),
            attachmentsJson: Value(
              attachments == null || attachments.isEmpty
                  ? null
                  : jsonEncode(attachments),
            ),
            kind: Value(raw['kind'] as String? ?? 'text'),
            payloadJson: Value(
              raw['payload'] == null ? null : jsonEncode(raw['payload']),
            ),
            sendState: Value(state),
          ),
        );

    // Событие о новом сообщении двигает и курсор чата: иначе после
    // перезапуска клиент запросил бы то, что уже показывает. Заодно время
    // последней активности: по нему список и упорядочен.
    final createdAt = DateTime.parse(raw['created_at'] as String);
    await db.customStatement(
      'UPDATE chats SET last_seq = MAX(last_seq, ?), synced_seq = MAX(synced_seq, ?), '
      'updated_at = MAX(updated_at, ?) WHERE id = ?',
      [seq, seq, createdAt.millisecondsSinceEpoch ~/ 1000, chatId],
    );
  }

  Future<void> _upsertSummary(Map<String, dynamic> summary) async {
    final chat = summary['chat'] as Map<String, dynamic>;
    final chatId = chat['id'] as String;

    await db
        .into(db.chats)
        .insertOnConflictUpdate(
          ChatsCompanion.insert(
            id: chatId,
            type: chat['type'] as String,
            title: Value(chat['title'] as String? ?? ''),
            avatarUrl: Value(chat['avatar_url'] as String?),
            lastSeq: Value(chat['last_seq'] as int? ?? 0),
            lastReadSeq: Value(summary['last_read_seq'] as int? ?? 0),
            unreadCount: Value(summary['unread_count'] as int? ?? 0),
            pinned: Value(summary['pinned'] as bool? ?? false),
            muted: Value(summary['muted'] as bool? ?? false),
            updatedAt: Value(DateTime.now()),
          ),
        );

    for (final raw in (summary['users'] as List<dynamic>? ?? const [])) {
      await _upsertUser(raw as Map<String, dynamic>);
    }
    for (final raw in (summary['members'] as List<dynamic>? ?? const [])) {
      final member = raw as Map<String, dynamic>;
      await db
          .into(db.chatMembers)
          .insertOnConflictUpdate(
            ChatMembersCompanion.insert(
              chatId: chatId,
              userId: member['user_id'] as String,
              role: Value(member['role'] as String? ?? 'member'),
              lastReadSeq: Value(member['last_read_seq'] as int? ?? 0),
            ),
          );
    }

    final last = summary['last_message'] as Map<String, dynamic>?;
    if (last != null) await _upsertMessage(last);
  }

  /// Перечитывает адресную книгу с сервера.
  ///
  /// Отметку снимаем со всех и ставим заново тем, кто пришёл: иначе удалённый
  /// из книги контакт остался бы в списке навсегда. Избранное при этом не
  /// трогаем — это решение человека, а не свойство контакта.
  /// Отдаёт серверу адресную книгу телефона и забирает тех, кто в Tito.
  ///
  /// Возвращает, сколько знакомых нашлось. Ноль — либо в книге никого из
  /// зарегистрированных, либо человек не дал разрешение; для интерфейса это
  /// одно и то же состояние.
  Future<int> syncDeviceContacts() async {
    final book = await DeviceContacts.read();
    if (book.isEmpty) return 0;

    final found = await api.syncContacts(book);
    await db.transaction(() async {
      for (final raw in found) {
        final user = raw as Map<String, dynamic>;
        await _upsertUser(user);
        await (db.update(db.users)..where((t) => t.id.equals(user['id'] as String)))
            .write(const UsersCompanion(isContact: Value(true)));
      }
    });
    return found.length;
  }

  /// Ищет человека на сервере — по имени, нику или номеру целиком.
  ///
  /// Нужен, когда в книге его нет: например, номер продиктовали голосом.
  /// По куску номера сервер не ищет намеренно — иначе базу можно было бы
  /// перебрать.
  Future<List<User>> searchPeople(String query) async {
    final found = await api.searchUsers(query);
    await db.transaction(() async {
      for (final raw in found) {
        await _upsertUser(raw as Map<String, dynamic>);
      }
    });
    final ids = [for (final raw in found) (raw as Map<String, dynamic>)['id'] as String];
    if (ids.isEmpty) return const [];
    return (db.select(db.users)..where((t) => t.id.isIn(ids))).get();
  }

  Future<void> refreshContacts() async {
    final list = await api.contacts();
    await db.transaction(() async {
      await db.update(db.users).write(
        const UsersCompanion(isContact: Value(false)),
      );
      for (final raw in list) {
        final user = raw as Map<String, dynamic>;
        await _upsertUser(user);
        await (db.update(db.users)..where((t) => t.id.equals(user['id'] as String)))
            .write(const UsersCompanion(isContact: Value(true)));
      }
    });
  }

  /// Кладёт профиль в базу. Нужен экранам, которые получили его не из
  /// событий сокета, — например, после правки собственного имени.
  Future<void> upsertUser(Map<String, dynamic> raw) => _upsertUser(raw);

  Future<void> _upsertUser(Map<String, dynamic> raw) async {
    await db
        .into(db.users)
        .insertOnConflictUpdate(
          UsersCompanion.insert(
            id: raw['id'] as String,
            displayName: Value(raw['display_name'] as String? ?? ''),
            username: Value(raw['username'] as String?),
            avatarUrl: Value(raw['avatar_url'] as String?),
            phone: Value(raw['phone'] as String?),
            lastSeenAt: Value(_date(raw['last_seen_at'])),
          ),
        );
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  Future<void> dispose() async {
    ws.onReady = null;
    await _subscription?.cancel();
  }
}
