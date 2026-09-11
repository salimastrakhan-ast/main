import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_client.dart';
import '../data/api/session_store.dart';
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
