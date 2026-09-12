import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_client.dart';
import '../data/api/session_store.dart';
import '../data/calls/call_service.dart';
import '../data/db/database.dart';
import '../data/repo/message_repository.dart';
import '../data/ws/ws_client.dart';

final sessionStoreProvider = Provider((ref) => SessionStore());

final apiProvider = Provider((ref) {
  final api = ApiClient(sessions: ref.watch(sessionStoreProvider));
  ref.onDispose(api.close);
  return api;
});

final databaseProvider = Provider((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Что показывает боковая панель.
enum SidebarView { chats, settings }

/// Открытый чат.
///
/// Состояние, а не маршрут: на широком экране панель и переписка видны
/// одновременно, и «открыть чат» не может быть переходом по стеку — иначе
/// переписка накрыла бы панель, которая должна остаться на месте.
final selectedChatProvider = StateProvider<String?>((ref) => null);

/// Собеседник, с которым переписки ещё нет.
///
/// На сервере личный чат заводится первым сообщением, а показать пустую
/// переписку надо раньше. Отдельно от `selectedChatProvider`, потому что
/// это разные вещи: там чат, здесь человек.
final draftPeerProvider = StateProvider<String?>((ref) => null);

/// Панель показывает список или настройки — как в веб-клиенте, где
/// настройки занимают её место, а не открываются поверх всего.
final sidebarViewProvider = StateProvider<SidebarView>(
  (ref) => SidebarView.chats,
);

/// Выбранная папка в панели.
enum ChatFolder { all, personal, groups }

final chatFolderProvider = StateProvider<ChatFolder>((ref) => ChatFolder.all);

/// Строка поиска в панели. Фильтрует список на месте, а не открывает
/// отдельный экран.
final sidebarSearchProvider = StateProvider<String>((ref) => '');

/// Ключи локальных настроек в одном месте: опечатка в строке иначе тихо
/// создаёт вторую настройку вместо чтения первой.
abstract final class PrefKeys {
  static const welcomeSeen = 'welcome.seen';
}

/// Видел ли человек экран приветствия. Показывается один раз: на второй
/// запуск он только мешает дойти до переписки.
final welcomeSeenProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(databaseProvider)
      .watchPref(PrefKeys.welcomeSeen)
      .map((value) => value == 'true');
});

/// Текущая сессия. Пока грузится — показываем заставку, дальше либо вход,
/// либо список чатов.
final sessionProvider = FutureProvider<Session?>((ref) {
  return ref.watch(sessionStoreProvider).read();
});

final wsProvider = Provider((ref) {
  final api = ref.watch(apiProvider);
  final ws = WsClient(tokenProvider: api.freshAccessToken);
  ref.onDispose(ws.dispose);
  return ws;
});

final connectionStateProvider = StreamProvider<WsStatus>((ref) {
  return ref.watch(wsProvider).state;
});

/// Репозиторий существует только при живой сессии: без вошедшего человека
/// ему нечего синхронизировать.
final repositoryProvider = Provider<MessageRepository?>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null) return null;

  final repo = MessageRepository(
    db: ref.watch(databaseProvider),
    ws: ref.watch(wsProvider),
    api: ref.watch(apiProvider),
    myUserId: session.userId,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// Звонки. Живут при любой сессии, отдельно от репозитория: разговор не
/// касается ни базы, ни очереди сообщений.
final callServiceProvider = Provider<CallService>((ref) {
  final service = CallService(
    ws: ref.watch(wsProvider),
    api: ref.watch(apiProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Текущий звонок или его отсутствие. На него смотрит оболочка приложения,
/// чтобы показать экран разговора поверх всего остального.
final currentCallProvider = StreamProvider<CallView?>((ref) {
  return ref.watch(callServiceProvider).calls;
});

final chatsProvider = StreamProvider<List<Chat>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo?.watchChats() ?? const Stream.empty();
});

final messagesProvider = StreamProvider.family<List<Message>, String>((
  ref,
  chatId,
) {
  final repo = ref.watch(repositoryProvider);
  return repo?.watchMessages(chatId) ?? const Stream.empty();
});

/// Профили всех, кого мы знаем, — картой для быстрого поиска по id.
final usersProvider = StreamProvider<Map<String, User>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final stream = repo?.watchUsers() ?? const Stream<List<User>>.empty();
  return stream.map((list) => {for (final u in list) u.id: u});
});

/// Адресная книга из локальной базы.
final contactsProvider = StreamProvider<List<User>>((ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const Stream<List<User>>.empty();
  return ref.watch(databaseProvider).watchContacts();
});

/// Личный чат с человеком — есть он уже или ещё нет.
final privateChatWithProvider = StreamProvider.family<String?, String>((
  ref,
  peerId,
) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const Stream<String?>.empty();
  return ref.watch(databaseProvider).watchPrivateChatWith(peerId);
});

/// Участники чата с профилями.
final chatMembersProvider =
    StreamProvider.family<List<({ChatMember member, User user})>, String>((
      ref,
      chatId,
    ) {
      final repo = ref.watch(repositoryProvider);
      if (repo == null) return const Stream.empty();
      return ref.watch(databaseProvider).watchMembers(chatId);
    });

/// Сообщения чата с вложениями — для экрана медиа.
final chatAttachmentsProvider = StreamProvider.family<List<Message>, String>((
  ref,
  chatId,
) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const Stream.empty();
  return ref.watch(databaseProvider).watchAttachments(chatId);
});

/// Один чат по идентификатору: экрану переписки нужен его тип.
final chatProvider = StreamProvider.family<Chat?, String>((ref, chatId) {
  final repo = ref.watch(repositoryProvider);
  final stream = repo?.watchChats() ?? const Stream<List<Chat>>.empty();
  return stream.map((list) {
    for (final chat in list) {
      if (chat.id == chatId) return chat;
    }
    return null;
  });
});

/// Собеседник в каждом личном чате: по нему подписана строка списка.
final chatPeersProvider = StreamProvider<Map<String, User>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo?.watchChatPeers() ?? const Stream.empty();
});

/// Последнее сообщение каждого чата — для второй строки в списке.
final lastMessagesProvider = StreamProvider<Map<String, LastMessage>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final stream = repo?.watchLastMessages() ?? const Stream<List<LastMessage>>.empty();
  return stream.map((list) => {for (final m in list) m.chatId: m});
});

/// Кто печатает в каком чате. Живёт в памяти: событие протухает за секунды.
final typingProvider =
    StateNotifierProvider<TypingNotifier, Map<String, Set<String>>>(
      (ref) => TypingNotifier(ref),
    );

class TypingNotifier extends StateNotifier<Map<String, Set<String>>> {
  TypingNotifier(this._ref) : super(const {}) {
    _ref.listen(typingEventsProvider, (_, __) {});
  }

  final Ref _ref;

  void add(String chatId, String userId) {
    state = {
      ...state,
      chatId: {...?state[chatId], userId},
    };
    // Сервер не присылает «перестал печатать»: индикатор гаснет сам.
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final rest = {...?state[chatId]}..remove(userId);
      state = {...state, chatId: rest};
    });
  }
}

/// Подписка на события «печатает» из сокета.
final typingEventsProvider = StreamProvider<void>((ref) {
  final ws = ref.watch(wsProvider);
  return ws.events.map((envelope) {
    if (envelope.type != 'typing') return;
    final data = envelope.data;
    if (data == null) return;
    ref
        .read(typingProvider.notifier)
        .add(data['chat_id'] as String, data['user_id'] as String);
  });
});
