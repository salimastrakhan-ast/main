import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tito/data/api/api_client.dart';
import 'package:tito/data/api/session_store.dart';
import 'package:tito/data/db/database.dart';
import 'package:tito/data/repo/message_repository.dart';
import 'package:tito/data/ws/envelope.dart';

import 'outbox_test.dart' show FakeTransport;

/// Закрепление и беззвучный режим.
///
/// Настройки личные: на сервере они лежат в строке участника, а не чата, и
/// у собеседника свои. Проверяем три вещи, каждая из которых однажды
/// ломалась в вебе: команда уходит в том виде, который сервер понимает;
/// список перестраивается сразу; отказ сервера не оставляет интерфейс
/// врущим о том, чего не произошло.
void main() {
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
      myUserId: 'user-me',
    );
    for (final id in ['chat-1', 'chat-2']) {
      await db.into(db.chats).insert(
        ChatsCompanion.insert(
          id: id,
          type: 'private',
          updatedAt: Value(
            DateTime.now().subtract(Duration(minutes: id == 'chat-1' ? 1 : 5)),
          ),
        ),
      );
    }
  });

  tearDown(() async {
    await transport.dispose();
    await db.close();
  });

  test('закреплённый чат поднимается наверх списка', () async {
    transport.handler = (_, _) => const {};

    var chats = await db.watchChats().first;
    expect(chats.first.id, 'chat-1', reason: 'сверху самый свежий');

    // Второй чат старее, но закреплён — значит, он первый.
    await repo.setPinned('chat-2', true);
    chats = await db.watchChats().first;
    expect(chats.first.id, 'chat-2');
    expect(chats.first.pinned, isTrue);
  });

  test('беззвучный режим уходит сроком, а не флагом', () async {
    transport.handler = (_, _) => const {};
    await repo.setMuted('chat-1', true);

    final sent = transport.sent.last;
    expect(sent['type'], Cmd.chatMute);
    // У сервера в кадре поле `until`; поля `muted` там нет вовсе, и раньше
    // клиент слал именно его — сервер молча игнорировал, звук не выключался.
    expect(sent.containsKey('muted'), isFalse);
    expect(
      DateTime.parse(sent['until'] as String).isAfter(DateTime.now().toUtc()),
      isTrue,
      reason: 'срок должен быть в будущем, иначе это «вернуть звук»',
    );

    // Возврат звука — пустой срок, а не `until` в прошлом.
    await repo.setMuted('chat-1', false);
    expect(transport.sent.last.containsKey('until'), isFalse);
  });

  test('отказ сервера возвращает переключатель как был', () async {
    // Сервер не ответил — связь пропала.
    transport.handler = (_, _) => null;

    await expectLater(
      repo.setPinned('chat-1', true),
      throwsA(isA<ProtocolException>()),
    );

    final chats = await db.watchChats().first;
    final chat = chats.firstWhere((c) => c.id == 'chat-1');
    expect(
      chat.pinned,
      isFalse,
      reason: 'иначе список показывает закрепление, которого на сервере нет',
    );
  });

  test('сервер приносит закрепление событием, а не только нашим нажатием', () async {
    // Закрепили с другого устройства: сюда это приезжает chat.update.
    transport.emit(
      const Envelope(
        type: Ev.chatUpdate,
        data: {
          'chat': {
            'chat': {'id': 'chat-3', 'type': 'private', 'last_seq': 0},
            'users': <dynamic>[],
            'members': <dynamic>[],
            'unread_count': 0,
            'pinned': true,
            'muted': true,
          },
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final chats = await db.watchChats().first;
    final chat = chats.firstWhere((c) => c.id == 'chat-3');
    expect(chat.pinned, isTrue);
    expect(chat.muted, isTrue);
  });
}
