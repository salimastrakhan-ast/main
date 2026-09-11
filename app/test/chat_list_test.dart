import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mayak/core/providers.dart';
import 'package:mayak/data/api/session_store.dart';
import 'package:mayak/data/db/database.dart';
import 'package:mayak/data/ws/ws_client.dart';
import 'package:mayak/features/chats/chats_screen.dart';

/// Из чего складывается строка в списке диалогов.
///
/// Проверка появилась по следу настоящей ошибки: заголовок брался из общего
/// справочника пользователей — первым, кто не я. С одним собеседником это
/// совпадало с правдой, а с тремя все три строки показывали одно имя.
void main() {
  late AppDatabase db;
  const me = 'me';

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> addUser(String id, String name) => db
      .into(db.users)
      .insert(UsersCompanion.insert(id: id, displayName: Value(name)));

  Future<void> addChat(String id, List<String> members) async {
    await db.into(db.chats).insert(ChatsCompanion.insert(id: id, type: 'private'));
    for (final userId in members) {
      await db.into(db.chatMembers).insert(
        ChatMembersCompanion.insert(chatId: id, userId: userId),
      );
    }
  }

  Future<void> addMessage(
    String id,
    String chatId,
    String senderId,
    String body, {
    DateTime? at,
    bool deleted = false,
  }) => db.into(db.messages).insert(
    MessagesCompanion.insert(
      id: id,
      chatId: chatId,
      senderId: senderId,
      body: Value(body),
      clientMsgId: id,
      createdAt: at ?? DateTime(2026, 1, 1),
      deletedAt: Value(deleted ? DateTime(2026, 1, 2) : null),
    ),
  );

  test('у каждого чата свой собеседник, а не первый попавшийся', () async {
    await addUser(me, 'Я');
    await addUser('a', 'Анна');
    await addUser('b', 'Борис');
    await addChat('chat-a', [me, 'a']);
    await addChat('chat-b', [me, 'b']);

    final peers = await db.watchChatPeers(me).first;

    expect(peers['chat-a']?.displayName, 'Анна');
    expect(peers['chat-b']?.displayName, 'Борис');
  });

  test('себя в собеседники не берём', () async {
    await addUser(me, 'Я');
    await addChat('один', [me]);

    final peers = await db.watchChatPeers(me).first;

    expect(peers['один'], isNull);
  });

  test('подпись — последнее сообщение чата, а не первое', () async {
    await addChat('chat', [me, 'a']);
    await addMessage('m1', 'chat', 'a', 'Привет', at: DateTime(2026, 1, 1, 10));
    await addMessage('m2', 'chat', me, 'До завтра', at: DateTime(2026, 1, 1, 12));

    final last = await db.watchLastMessages().first;

    expect(last.single.chatId, 'chat');
    expect(last.single.body, 'До завтра');
    expect(last.single.senderId, me);
  });

  test('у каждого чата своя подпись', () async {
    await addChat('chat-a', [me, 'a']);
    await addChat('chat-b', [me, 'b']);
    await addMessage('m1', 'chat-a', 'a', 'Первый чат');
    await addMessage('m2', 'chat-b', 'b', 'Второй чат');

    final last = {for (final m in await db.watchLastMessages().first) m.chatId: m};

    expect(last['chat-a']?.body, 'Первый чат');
    expect(last['chat-b']?.body, 'Второй чат');
  });

  _screen();

  test('удалённое сообщение помечено, а не показано текстом', () async {
    await addChat('chat', [me, 'a']);
    await addMessage('m1', 'chat', 'a', 'Секрет', deleted: true);

    final last = await db.watchLastMessages().first;

    expect(last.single.deleted, isTrue);
  });
}

/// Тот же случай, но на экране: именно там ошибка и жила.
void _screen() {
  const me = 'me';

  Chat chat(String id) => Chat(
    id: id,
    type: 'private',
    title: '',
    lastSeq: 0,
    syncedSeq: 0,
    lastReadSeq: 0,
    unreadCount: 0,
    updatedAt: DateTime(2026, 1, 1, 12),
  );

  User user(String id, String name) => User(
    id: id,
    displayName: name,
    online: false,
    isContact: true,
    isFavorite: false,
  );

  Widget app({
    required List<Chat> chats,
    required Map<String, User> peers,
    required Map<String, LastMessage> lastMessages,
  }) {
    return ProviderScope(
      overrides: [
        sessionProvider.overrideWith(
          (ref) async => Session(
            accessToken: '',
            refreshToken: '',
            userId: me,
            expiresAt: DateTime(2027),
          ),
        ),
        chatsProvider.overrideWith((ref) => Stream.value(chats)),
        chatPeersProvider.overrideWith((ref) => Stream.value(peers)),
        lastMessagesProvider.overrideWith((ref) => Stream.value(lastMessages)),
        connectionStateProvider.overrideWith(
          (ref) => Stream.value(WsStatus.online),
        ),
      ],
      child: const MaterialApp(home: ChatsScreen()),
    );
  }

  testWidgets('каждая строка подписана своим собеседником', (tester) async {
    await tester.pumpWidget(
      app(
        chats: [chat('chat-a'), chat('chat-b')],
        peers: {'chat-a': user('a', 'Анна'), 'chat-b': user('b', 'Борис')},
        lastMessages: const {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Анна'), findsOneWidget);
    expect(find.text('Борис'), findsOneWidget);
  });

  testWidgets('своё сообщение подписано «Вы»', (tester) async {
    await tester.pumpWidget(
      app(
        chats: [chat('chat-a')],
        peers: {'chat-a': user('a', 'Анна')},
        lastMessages: const {
          'chat-a': LastMessage(
            chatId: 'chat-a',
            body: 'До завтра',
            senderId: me,
            deleted: false,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вы: До завтра'), findsOneWidget);
  });

  testWidgets('чужое сообщение — без подписи', (tester) async {
    await tester.pumpWidget(
      app(
        chats: [chat('chat-a')],
        peers: {'chat-a': user('a', 'Анна')},
        lastMessages: const {
          'chat-a': LastMessage(
            chatId: 'chat-a',
            body: 'Привет',
            senderId: 'a',
            deleted: false,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Привет'), findsOneWidget);
  });

  testWidgets('пустой чат подписан тем, что это за чат', (tester) async {
    await tester.pumpWidget(
      app(
        chats: [chat('chat-a')],
        peers: {'chat-a': user('a', 'Анна')},
        lastMessages: const {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Личный чат'), findsOneWidget);
  });
}
