import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tito/core/providers.dart';
import 'package:tito/data/api/session_store.dart';
import 'package:tito/data/db/database.dart';
import 'package:tito/data/ws/ws_client.dart';
import 'package:tito/features/home/home_screen.dart';

/// Раскладка оболочки.
///
/// На широком экране панель и переписка стоят рядом, на узком видна одна
/// часть. Это не косметика: от ширины зависит, чем заканчивается «назад» и
/// нужна ли вообще стрелка в шапке.
void main() {
  const me = 'me';
  const chatId = 'chat-1';

  setUpAll(() => initializeDateFormatting('ru'));

  Chat chat(String id, {String type = 'private', String title = ''}) => Chat(
    id: id,
    type: type,
    title: title,
    lastSeq: 1,
    syncedSeq: 1,
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

  Widget app({List<Chat>? chats, String? selected}) {
    return ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(null),
        sessionProvider.overrideWith(
          (ref) async => Session(
            accessToken: '',
            refreshToken: '',
            userId: me,
            expiresAt: DateTime(2027),
          ),
        ),
        chatsProvider.overrideWith(
          (ref) => Stream.value(chats ?? [chat(chatId), chat('chat-2', type: 'group', title: 'Рабочий')]),
        ),
        chatPeersProvider.overrideWith(
          (ref) => Stream.value({chatId: user('a', 'Анна')}),
        ),
        lastMessagesProvider.overrideWith((ref) => Stream.value(const {})),
        usersProvider.overrideWith((ref) => Stream.value({'a': user('a', 'Анна')})),
        chatProvider(chatId).overrideWith((ref) => Stream.value(chat(chatId))),
        messagesProvider(chatId).overrideWith((ref) => Stream.value(const [])),
        connectionStateProvider.overrideWith((ref) => Stream.value(WsStatus.online)),
        if (selected != null)
          selectedChatProvider.overrideWith((ref) => selected),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  Future<void> setWidth(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('на широком экране панель и переписка стоят рядом', (tester) async {
    await setWidth(tester, 1280);
    await tester.pumpWidget(app(selected: chatId));
    await tester.pumpAndSettle();

    // Имя собеседника видно дважды: в строке списка и в шапке переписки.
    expect(find.text('Анна'), findsNWidgets(2));
  });

  testWidgets('на узком экране видна только переписка', (tester) async {
    await setWidth(tester, 430);
    await tester.pumpWidget(app(selected: chatId));
    await tester.pumpAndSettle();

    expect(find.text('Анна'), findsOneWidget);
    expect(find.text('Tito'), findsNothing, reason: 'шапка панели должна уйти');
  });

  testWidgets('без выбранного чата широкий экран зовёт выбрать', (tester) async {
    await setWidth(tester, 1280);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Выберите диалог'), findsOneWidget);
  });

  testWidgets('на узком экране без выбора видна панель', (tester) async {
    await setWidth(tester, 430);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Tito'), findsOneWidget);
    expect(find.text('Выберите диалог'), findsNothing);
  });

  testWidgets('папка «Группы» оставляет только групповые чаты', (tester) async {
    await setWidth(tester, 430);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Анна'), findsOneWidget);
    expect(find.text('Рабочий'), findsOneWidget);

    await tester.tap(find.text('Группы'));
    await tester.pumpAndSettle();

    expect(find.text('Рабочий'), findsOneWidget);
    expect(find.text('Анна'), findsNothing, reason: 'личный чат не групповой');
  });
}
