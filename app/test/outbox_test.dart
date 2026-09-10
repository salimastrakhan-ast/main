import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mayak/data/api/api_client.dart';
import 'package:mayak/data/api/session_store.dart';
import 'package:mayak/data/db/database.dart';
import 'package:mayak/data/repo/message_repository.dart';
import 'package:mayak/data/ws/envelope.dart';
import 'package:mayak/data/ws/transport.dart';

/// Поддельный транспорт: сервера и сети нет, поведение задаётся тестом.
class FakeTransport implements MessageTransport {
  FakeTransport({this.status = WsStatus.online});

  final _events = StreamController<Envelope>.broadcast();
  final sent = <Map<String, dynamic>>[];

  WsStatus status;

  /// Что вернуть на очередную команду. Возврат null означает, что сервер не
  /// ответил, — так выглядит пропавшая связь.
  Map<String, dynamic>? Function(String type, Map<String, dynamic> data)? handler;

  @override
  Stream<Envelope> get events => _events.stream;

  @override
  WsStatus get currentState => status;

  @override
  Future<void> Function()? onReady;

  @override
  Future<Map<String, dynamic>> call(String type, Map<String, dynamic> data) async {
    sent.add({'type': type, ...data});
    final result = handler?.call(type, data);
    if (result == null) {
      throw const ProtocolException('offline', 'Нет соединения');
    }
    return result;
  }

  @override
  void notify(String type, Map<String, dynamic> data) {
    sent.add({'type': type, ...data});
  }

  void emit(Envelope envelope) => _events.add(envelope);

  Future<void> dispose() => _events.close();
}

/// Ответ сервера на message.send.
Map<String, dynamic> serverMessage({
  required String chatId,
  required String clientMsgId,
  required String senderId,
  required int seq,
  String text = '',
}) => {
  'message': {
    'id': 'srv-$seq',
    'chat_id': chatId,
    'seq': seq,
    'updated_seq': seq,
    'sender_id': senderId,
    'text': text,
    'client_msg_id': clientMsgId,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  },
};

/// Даёт фоновой отправке доработать: send возвращается сразу, а очередь
/// разгребается следом.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  const myId = 'user-me';
  const chatId = 'chat-1';

  late AppDatabase db;
  late FakeTransport transport;
  late MessageRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = FakeTransport();
    repo = MessageRepository(
      db: db,
      ws: transport,
      api: ApiClient(sessions: SessionStore()),
      myUserId: myId,
    );
    // Чат должен существовать, чтобы сообщение было куда положить.
    await db.into(db.chats).insert(
      ChatsCompanion.insert(id: chatId, type: 'private'),
    );
  });

  tearDown(() async {
    await repo.dispose();
    await transport.dispose();
    await db.close();
  });

  test('сообщение видно сразу, ещё до ответа сервера', () async {
    // Сервер молчит — как при плохой связи.
    transport.handler = (_, __) => null;

    await repo.send(chatId: chatId, text: 'привет');
    await settle();

    final messages = await db.watchMessages(chatId).first;
    expect(messages, hasLength(1), reason: 'сообщение должно появиться в ленте сразу');
    expect(messages.single.body, 'привет');
    expect(messages.single.sendState, SendState.pending,
        reason: 'до подтверждения сообщение помечено часиками');
  });

  test('неотправленное остаётся в очереди и уходит при возврате связи', () async {
    transport.handler = (_, __) => null;
    await repo.send(chatId: chatId, text: 'в метро');
    await settle();

    expect(await db.pendingOutbox(), hasLength(1),
        reason: 'без подтверждения сообщение обязано остаться в очереди');

    // Связь вернулась.
    transport.handler = (type, data) => serverMessage(
      chatId: chatId,
      clientMsgId: data['client_msg_id'] as String,
      senderId: myId,
      seq: 7,
      text: data['text'] as String,
    );
    await repo.drainOutbox();

    expect(await db.pendingOutbox(), isEmpty,
        reason: 'после подтверждения очередь должна опустеть');

    final messages = await db.watchMessages(chatId).first;
    expect(messages, hasLength(1), reason: 'сообщение не должно задвоиться');
    expect(messages.single.seq, 7, reason: 'номер приходит от сервера');
    expect(messages.single.sendState, SendState.sent);
  });

  test('черновик заменяется строкой сервера, а не дублируется', () async {
    transport.handler = (type, data) => serverMessage(
      chatId: chatId,
      clientMsgId: data['client_msg_id'] as String,
      senderId: myId,
      seq: 1,
      text: data['text'] as String,
    );

    await repo.send(chatId: chatId, text: 'привет');
    await settle();

    final messages = await db.watchMessages(chatId).first;
    expect(messages, hasLength(1));
    expect(messages.single.id, 'srv-1',
        reason: 'в базе должна остаться строка с идентификатором сервера');
  });

  test('окончательный отказ снимает сообщение с очереди и помечает ошибкой', () async {
    // Например, человека выкинули из чата, пока сообщение лежало в очереди.
    transport.handler = (_, __) => throw const ProtocolException(
      'forbidden',
      'Нет доступа',
    );

    await repo.send(chatId: chatId, text: 'уже не участник');
    await settle();

    expect(await db.pendingOutbox(), isEmpty,
        reason: 'повторять запрещённую отправку бессмысленно');
    final messages = await db.watchMessages(chatId).first;
    expect(messages.single.sendState, SendState.failed);
  });

  test('очередь переживает перезапуск приложения', () async {
    transport.handler = (_, __) => null;
    await repo.send(chatId: chatId, text: 'не успел уйти');
    await settle();

    // Приложение закрыли и открыли заново: тот же файл базы, новый
    // репозиторий и новое соединение.
    await repo.dispose();
    final revived = MessageRepository(
      db: db,
      ws: transport,
      api: ApiClient(sessions: SessionStore()),
      myUserId: myId,
    );
    addTearDown(revived.dispose);

    expect(await db.pendingOutbox(), hasLength(1),
        reason: 'написанное до закрытия не должно пропасть');

    transport.handler = (type, data) => serverMessage(
      chatId: chatId,
      clientMsgId: data['client_msg_id'] as String,
      senderId: myId,
      seq: 3,
      text: data['text'] as String,
    );
    await revived.drainOutbox();

    expect(await db.pendingOutbox(), isEmpty);
    final messages = await db.watchMessages(chatId).first;
    expect(messages.single.body, 'не успел уйти');
  });

  test('входящее событие кладёт сообщение в базу и двигает курсор', () async {
    transport.emit(Envelope(
      type: Ev.messageNew,
      data: serverMessage(
        chatId: chatId,
        clientMsgId: 'c-1',
        senderId: 'user-other',
        seq: 12,
        text: 'от собеседника',
      ),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final messages = await db.watchMessages(chatId).first;
    expect(messages, hasLength(1));
    expect(messages.single.body, 'от собеседника');

    // Курсор обязан подтянуться: иначе после перезапуска клиент запросил бы
    // то, что уже показывает.
    expect(await db.syncCursors(), {chatId: 12});
  });

  test('повторное событие о том же сообщении не создаёт второе', () async {
    final payload = serverMessage(
      chatId: chatId,
      clientMsgId: 'c-1',
      senderId: 'user-other',
      seq: 5,
      text: 'дубль',
    );
    transport.emit(Envelope(type: Ev.messageNew, data: payload));
    transport.emit(Envelope(type: Ev.messageNew, data: payload));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await db.watchMessages(chatId).first, hasLength(1));
  });

  test('пока связи нет, очередь не разгребается', () async {
    transport.status = WsStatus.offline;
    transport.handler = (_, __) => serverMessage(
      chatId: chatId, clientMsgId: 'c', senderId: myId, seq: 1);

    await repo.send(chatId: chatId, text: 'подождёт');
    await repo.drainOutbox();

    expect(transport.sent, isEmpty,
        reason: 'без соединения отправлять некуда');
    expect(await db.pendingOutbox(), hasLength(1));
  });
}
