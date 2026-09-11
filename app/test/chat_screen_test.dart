import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tito/core/providers.dart';
import 'package:tito/data/api/session_store.dart';
import 'package:tito/data/db/database.dart';
import 'package:tito/features/chat/chat_screen.dart';

/// Подпись над пузырём.
///
/// В группе она нужна: собеседников много, и без имени непонятно, кто что
/// сказал. В личной переписке собеседник один и уже назван в шапке — там
/// подпись над каждым его словом только шумит.
void main() {
  const me = 'me';
  const chatId = 'chat-1';

  // Разделители дат в ленте пишутся по-русски, а названия месяцев для этого
  // нужно загрузить: в тестах main() приложения не выполняется.
  setUpAll(() => initializeDateFormatting('ru'));

  Message message(String id, String senderId, String body) => Message(
    id: id,
    chatId: chatId,
    seq: 1,
    updatedSeq: 1,
    senderId: senderId,
    body: body,
    clientMsgId: id,
    createdAt: DateTime(2026, 1, 1, 12),
    sendState: SendState.sent,
  );

  Chat chat(String type) => Chat(
    id: chatId,
    type: type,
    title: '',
    lastSeq: 1,
    syncedSeq: 1,
    lastReadSeq: 0,
    unreadCount: 0,
    updatedAt: DateTime(2026, 1, 1, 12),
  );

  Widget app(String type) => ProviderScope(
    overrides: [
      // Репозитория нет: экран обращается к нему через `?.`, а живой поднял
      // бы настоящую базу и сокет.
      repositoryProvider.overrideWithValue(null),
      sessionProvider.overrideWith(
        (ref) async => Session(
          accessToken: '',
          refreshToken: '',
          userId: me,
          expiresAt: DateTime(2027),
        ),
      ),
      chatProvider(chatId).overrideWith((ref) => Stream.value(chat(type))),
      messagesProvider(chatId).overrideWith(
        (ref) => Stream.value([
          message('m1', 'peer', 'Привет'),
          message('m2', me, 'И тебе'),
        ]),
      ),
      usersProvider.overrideWith(
        (ref) => Stream.value({
          'peer': const User(
            id: 'peer',
            displayName: 'Анна',
            online: false,
            isContact: true,
            isFavorite: false,
          ),
        }),
      ),
    ],
    child: const MaterialApp(
      home: ChatScreen(chatId: chatId, title: 'Анна'),
    ),
  );

  testWidgets('в личной переписке имени над пузырём нет', (tester) async {
    await tester.pumpWidget(app('private'));
    await tester.pumpAndSettle();

    expect(find.text('Привет'), findsOneWidget);
    // Имя есть только в шапке — второго вхождения быть не должно.
    expect(find.text('Анна'), findsOneWidget);
  });

  testWidgets('в группе имя над пузырём есть', (tester) async {
    await tester.pumpWidget(app('group'));
    await tester.pumpAndSettle();

    expect(find.text('Привет'), findsOneWidget);
    expect(find.text('Анна'), findsNWidgets(2));
  });
}
