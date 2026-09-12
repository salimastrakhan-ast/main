import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/repo/message_repository.dart';
import '../../data/ws/envelope.dart';
import '../../ui/icons.dart';
import '../../ui/glass.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import 'emoji_sheet.dart';
import '../../ui/voice.dart';
import '../chat_info/chat_info_screen.dart';

/// Открывает переписку с человеком.
///
/// Чата может ещё не быть: на сервере личный чат заводится первым
/// сообщением, а не открытием экрана. Поэтому сюда передаётся собеседник, а
/// экран сам подхватит чат, как только тот появится.
void openChatWith(BuildContext context, WidgetRef ref, User person) {
  // Если переписка уже была, открываем её, а не заводим черновик рядом с
  // ней: иначе получилось бы два места для одного человека.
  final existing = ref.read(privateChatWithProvider(person.id)).value;
  ref.read(selectedChatProvider.notifier).state = existing;
  ref.read(draftPeerProvider.notifier).state = existing == null
      ? person.id
      : null;
  // Возвращаемся к оболочке: выбранное покажет она сама.
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Переписка внутри оболочки: чат выбран в панели, а не открыт маршрутом.
///
/// Отдельное имя, потому что и ведёт себя иначе: на узком экране стрелка
/// «назад» снимает выбор, а не закрывает маршрут, которого нет.
class ChatPane extends ConsumerWidget {
  const ChatPane({this.chatId, this.peerId, super.key})
    : assert(chatId != null || peerId != null, 'нужен чат или собеседник');

  final String? chatId;
  final String? peerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 768;
    return ChatScreen(
      chatId: chatId,
      peerId: peerId,
      // На широком экране назад некуда: панель и так рядом.
      onBack: wide
          ? null
          : () {
              ref.read(selectedChatProvider.notifier).state = null;
              ref.read(draftPeerProvider.notifier).state = null;
            },
    );
  }
}

/// Переписка.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    this.title,
    this.chatId,
    this.peerId,
    this.onBack,
    super.key,
  }) : assert(
         chatId != null || peerId != null,
         'нужен либо чат, либо собеседник',
       );

  /// Чат, если он уже заведён.
  final String? chatId;

  /// Собеседник — когда чата ещё нет.
  final String? peerId;

  /// Заголовок, когда он известен заранее. Иначе берётся из самого чата.
  final String? title;

  /// Чем заканчивается «назад». Пусто — обычный возврат по маршруту.
  final VoidCallback? onBack;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();

  /// Фокус поля ввода: после «Ответить» клавиатура должна открыться сама —
  /// отвечают текстом, и лишнее нажатие тут ни к чему.
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _composerKey = GlobalKey();
  Timer? _typingThrottle;
  int _lastReadSeq = 0;

  /// Правящееся сообщение. Пока оно выбрано, поле ввода сохраняет правку, а
  /// не отправляет новое: перепутать эти два состояния — значит отправить
  /// исправленный текст второй строкой.
  Message? _editing;

  /// Сообщение, на которое отвечаем. С правкой не совмещается: нельзя
  /// одновременно исправлять своё и отвечать на чужое.
  Message? _replyingTo;

  /// Запись голосового.
  final _recorder = AudioRecorder();
  Timer? _recordTicker;
  int? _recordSeconds;

  /// Высота поля ввода. Лента уходит под него, и на этот отступ снизу она
  /// сдвигается, иначе последнее сообщение окажется под полем. Значение
  /// измеряется, а не задаётся: поле растёт до пяти строк.
  double _composerHeight = 76;

  /// Чат этого экрана. Пока переписки не было, он null — и это нормальное
  /// состояние, а не ошибка.
  String? get _chatId =>
      widget.chatId ?? ref.watch(privateChatWithProvider(widget.peerId!)).value;

  void _measureComposer() {
    final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if ((box.size.height - _composerHeight).abs() < 0.5) return;
    setState(() => _composerHeight = box.size.height);
  }

  @override
  void dispose() {
    _typingThrottle?.cancel();
    _recordTicker?.cancel();
    // Микрофон отпускаем явно: уход с экрана не повод оставлять его
    // включённым, а система показывает это человеку значком в шторке.
    unawaited(_recorder.dispose());
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Начинает запись голосового.
  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) showMessage(context, 'Нет доступа к микрофону');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      // AAC, а не opus: в вебе браузер пишет opus сам, а на телефонах
      // поддержка opus в контейнере зависит от версии системы, и там, где
      // её нет, запись молча не начинается.
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000),
      path: path,
    );

    setState(() => _recordSeconds = 0);
    _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds = (_recordSeconds ?? 0) + 1);
    });
  }

  Future<void> _finishRecording() async {
    final seconds = _recordSeconds ?? 0;
    _recordTicker?.cancel();
    final path = await _recorder.stop();
    if (mounted) setState(() => _recordSeconds = null);

    // Меньше секунды — случайное касание, а не сообщение.
    if (path == null || seconds < 1) return;

    final file = File(path);
    try {
      final attachment = await ref
          .read(apiProvider)
          .upload(
            fileName: 'голосовое.m4a',
            bytes: await file.readAsBytes(),
            mime: 'audio/mp4',
            duration: seconds,
          );
      await ref
          .read(repositoryProvider)
          ?.send(
            chatId: _chatId,
            peerId: _chatId == null ? widget.peerId : null,
            text: '',
            attachmentIds: [attachment['id'] as String],
          );
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) showMessage(context, 'Не удалось отправить голосовое');
    } finally {
      // Временный файл нужен был только до отправки.
      unawaited(file.delete().catchError((_) => file));
    }
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    final path = await _recorder.stop();
    if (path != null) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    if (mounted) setState(() => _recordSeconds = null);
  }

  /// Вставляет эмодзи туда, где стоит курсор.
  ///
  /// Не в конец: дописать знак в середину набранного — обычное дело, и
  /// выбрасывать его в хвост значит заставлять вырезать и переставлять.
  void _insertEmoji(String emoji) {
    final selection = _input.selection;
    final text = _input.text;
    final at = selection.isValid ? selection.start : text.length;
    final to = selection.isValid ? selection.end : text.length;

    _input.text = text.substring(0, at) + emoji + text.substring(to);
    _input.selection = TextSelection.collapsed(offset: at + emoji.length);
    setState(() {});
  }

  /// Берётся отвечать: над полем встаёт полоска с цитатой.
  void _startReply(Message message) {
    setState(() {
      _replyingTo = message;
      _editing = null;
    });
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  /// Берётся править: прежний текст встаёт в поле.
  void _startEditing(Message message) {
    setState(() {
      _editing = message;
      _replyingTo = null;
    });
    _input.text = message.body;
    _input.selection = TextSelection.collapsed(offset: message.body.length);
  }

  void _cancelEditing() {
    setState(() => _editing = null);
    _input.clear();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    final editing = _editing;
    if (editing != null) {
      _cancelEditing();
      try {
        await ref
            .read(repositoryProvider)
            ?.edit(editing.chatId, editing.id, text);
      } on ProtocolException catch (error) {
        if (mounted) showMessage(context, error.message);
      }
      return;
    }

    final replyTo = _replyingTo;
    _input.clear();
    if (replyTo != null) setState(() => _replyingTo = null);
    await ref
        .read(repositoryProvider)
        ?.send(
          chatId: _chatId,
          peerId: _chatId == null ? widget.peerId : null,
          text: text,
          replyToId: replyTo?.id,
        );
    // Скроллим после того, как база разбудит подписчиков и лента вырастет.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Спрашивает, что прикрепить.
  ///
  /// Раньше скрепка молча открывала галерею, и отправить документ с
  /// телефона было нельзя вовсе — притом что из браузера отправлялось что
  /// угодно. Теперь выбор: фотография ищется в галерее, остальное — в
  /// файлах.
  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(TitoIcons.image),
              title: const Text('Фото или видео'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(TitoIcons.file),
              title: const Text('Файл'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final file = choice == 'gallery'
        ? await _fromGallery()
        : await _fromFiles();
    if (file == null || !mounted) return;
    await _sendFile(file);
  }

  Future<_PickedFile?> _fromGallery() async {
    final picked = await ImagePicker().pickMedia();
    if (picked == null) return null;
    return _PickedFile(
      name: picked.name,
      bytes: await picked.readAsBytes(),
      mime: picked.mimeType ?? _mimeByName(picked.name),
    );
  }

  Future<_PickedFile?> _fromFiles() async {
    // withData: на вебе файла на диске нет вовсе, а нам нужны байты.
    final result = await FilePicker.platform.pickFiles(withData: true);
    // Без `singleOrNull`: он приходит расширением из чужого пакета, и
    // держаться за транзитивный экспорт — способ однажды не собраться.
    final files = result?.files ?? const [];
    if (files.isEmpty) return null;
    final picked = files.first;

    final bytes = picked.bytes;
    if (bytes == null) return null;
    return _PickedFile(
      name: picked.name,
      bytes: bytes,
      mime: _mimeByName(picked.name),
    );
  }

  /// Отправка: сначала уходит файл, потом сообщение со ссылкой на него.
  /// Порядок важен — сообщение без загруженного вложения сервер отвергнет,
  /// и оно осело бы в очереди навсегда.
  Future<void> _sendFile(_PickedFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final attachment = await ref
          .read(apiProvider)
          .upload(fileName: file.name, bytes: file.bytes, mime: file.mime);
      final text = _input.text.trim();
      _input.clear();
      await ref
          .read(repositoryProvider)
          ?.send(
            chatId: _chatId,
            peerId: _chatId == null ? widget.peerId : null,
            text: text,
            attachmentIds: [attachment['id'] as String],
          );
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      // Показываем отказ здесь, а не через очередь: файл не загрузился, и
      // повторять нечего — нужно решение человека.
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Не удалось отправить файл')),
        );
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// «Печатает» уходит не чаще раза в три секунды: на каждое нажатие клавиши
  /// это был бы поток кадров ради индикатора.
  void _onTyping() {
    final chatId = _chatId;
    if (chatId == null) return;
    if (_typingThrottle?.isActive ?? false) return;
    _typingThrottle = Timer(const Duration(seconds: 3), () {});
    ref.read(repositoryProvider)?.sendTyping(chatId);
  }

  /// Отмечает прочитанным всё до последнего показанного сообщения.
  void _markRead(String chatId, List<Message> messages) {
    final last = messages.where((m) => m.seq > 0).lastOrNull;
    if (last == null || last.seq <= _lastReadSeq) return;
    _lastReadSeq = last.seq;
    ref.read(repositoryProvider)?.markRead(chatId, last.seq);
  }

  @override
  Widget build(BuildContext context) {
    final chatId = _chatId;
    final users = ref.watch(usersProvider).value ?? const {};
    final chat = chatId == null ? null : ref.watch(chatProvider(chatId)).value;
    final isGroup = chat?.type == 'group';
    final myUserId = ref.watch(sessionProvider).value?.userId ?? '';
    final typing = chatId == null
        ? const <String>{}
        : ref.watch(typingProvider)[chatId] ?? const <String>{};

    final peer = widget.peerId != null
        ? users[widget.peerId]
        : (chatId == null ? null : ref.watch(chatPeersProvider).value?[chatId]);

    // «Избранное» — личный чат без собеседника: участник в нём один.
    final isSaved = !isGroup && chat != null && peer == null;
    final title =
        widget.title ??
        (isGroup
            ? (chat?.title.isNotEmpty ?? false ? chat!.title : 'Группа')
            : isSaved
            ? 'Избранное'
            : peer?.displayName ?? 'Чат');

    return Scaffold(
      // Лента уезжает под шапку и под поле ввода: иначе при прокрутке
      // содержимое обрывается ровно по краю панели.
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(TitoIcons.back),
                tooltip: 'К списку',
                onPressed: widget.onBack,
              ),
        title: _ChatTitle(
          id: chat?.id ?? peer?.id ?? title,
          name: title,
          isGroup: isGroup,
          isSaved: isSaved,
          peer: peer,
          typing: typing.isNotEmpty,
          onTap: chatId == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatInfoScreen(chatId: chatId),
                  ),
                ),
        ),
        actions: [
          // Трубки в образце нет — там в шапке только меню. Но звонок это
          // то, ради чего люди открывают мессенджер, и прятать его в меню
          // из трёх точек значит сделать вид, что его нет.
          //
          // Только в личной переписке: групповым нужен отдельный сервер
          // сведения потоков, и кнопка, которая всегда отвечает отказом,
          // хуже её отсутствия. В «Избранном» звонить некому.
          if (!isGroup && !isSaved && peer != null)
            _CallButton(peer: peer, chatId: chatId),
          if (chatId != null && chat != null)
            _ChatMenu(chat: chat)
          else
            const IconButton(
              icon: Icon(TitoIcons.more, size: 20),
              tooltip: 'Ещё',
              onPressed: null,
            ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: ChatCanvas()),
          Positioned.fill(
            child: chatId == null
                ? const _FirstMessage()
                : _Feed(
                    chatId: chatId,
                    myUserId: myUserId,
                    isGroup: isGroup,
                    users: users,
                    scroll: _scroll,
                    topPadding: glassAppBarHeight(context, extra: 12),
                    bottomPadding: _composerHeight + 12,
                    onRendered: (list) {
                      _markRead(chatId, list);
                      _measureComposer();
                    },
                    onEdit: _startEditing,
                    onReply: _startReply,
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Composer(
              focusNode: _inputFocus,
              onEmoji: () => showEmojiSheet(context, _insertEmoji),
              replyingTo: _replyingTo,
              onCancelReply: _cancelReply,
              key: _composerKey,
              controller: _input,
              onSend: _send,
              onChanged: _onTyping,
              onAttach: _attach,
              editing: _editing,
              onCancelEdit: _cancelEditing,
              recordSeconds: _recordSeconds,
              onStartRecording: _startRecording,
              onFinishRecording: _finishRecording,
              onCancelRecording: _cancelRecording,
            ),
          ),
        ],
      ),
    );
  }
}

/// Шапка переписки: аватар, имя и что с человеком сейчас.
class _ChatTitle extends StatelessWidget {
  const _ChatTitle({
    required this.id,
    required this.name,
    required this.isGroup,
    required this.isSaved,
    required this.peer,
    required this.typing,
    required this.onTap,
  });

  final String id;
  final String name;
  final bool isGroup;
  final bool isSaved;
  final User? peer;
  final bool typing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = switch (true) {
      _ when typing => ('печатает…', theme.colorScheme.primary),
      _ when isSaved => ('Заметки себе', theme.colorScheme.onSurfaceVariant),
      _ when isGroup => ('Группа', theme.colorScheme.onSurfaceVariant),
      _ when peer?.online ?? false => ('в сети', Tokens.online),
      _ => ('не в сети', theme.colorScheme.onSurfaceVariant),
    };

    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          PersonAvatar(
            id: id,
            name: name,
            radius: 17,
            photo: peer?.avatarUrl,
            online: peer?.online ?? false,
            saved: isSaved,
            icon: isGroup ? TitoIcons.contacts : null,
          ),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                ),
                Text(
                  status.$1,
                  style: theme.textTheme.labelSmall?.copyWith(color: status.$2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Лента сообщений с разделителями дат.
/// Меню переписки: закрепить, выключить звук, сведения о чате.
///
/// Те же пункты, что в веб-клиенте. Закрепление и беззвучный режим —
/// настройки участника, а не чата: у собеседника они свои.
class _ChatMenu extends ConsumerWidget {
  const _ChatMenu({required this.chat});

  final Chat chat;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(MessageRepository repo) action,
  ) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      await action(repo);
    } on ProtocolException catch (error) {
      if (context.mounted) showMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(TitoIcons.more, size: 20),
      tooltip: 'Ещё',
      onSelected: (value) async {
        switch (value) {
          case 'pin':
            await _run(
              context,
              ref,
              (repo) => repo.setPinned(chat.id, !chat.pinned),
            );
          case 'mute':
            await _run(
              context,
              ref,
              (repo) => repo.setMuted(chat.id, !chat.muted),
            );
          case 'info':
            if (context.mounted) {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatInfoScreen(chatId: chat.id),
                ),
              );
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          child: _MenuRow(
            icon: chat.pinned ? TitoIcons.unpin : TitoIcons.pin,
            label: chat.pinned ? 'Открепить' : 'Закрепить',
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: _MenuRow(
            icon: chat.muted ? TitoIcons.unmute : TitoIcons.mute,
            label: chat.muted ? 'Включить звук' : 'Без звука',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'info',
          child: _MenuRow(icon: TitoIcons.contacts, label: 'Сведения о чате'),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: Tokens.space3),
        Text(label),
      ],
    );
  }
}

/// Выбранный файл: то немногое, что нужно для отправки.
///
/// Своя запись вместо типов обоих сборщиков: у галереи и у файлового
/// выбора они разные, и тащить оба через половину экрана значит писать
/// одну и ту же ветку дважды.
class _PickedFile {
  const _PickedFile({
    required this.name,
    required this.bytes,
    required this.mime,
  });

  final String name;
  final List<int> bytes;
  final String mime;
}

/// Тип содержимого по расширению имени.
///
/// Файловый выбор его не сообщает, а сервер по нему решает, картинка это,
/// звук или документ — то есть как клиент нарисует вложение. Ошибиться
/// здесь значит показать фотографию строкой «файл».
String _mimeByName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'mp3' => 'audio/mpeg',
    'ogg' || 'oga' => 'audio/ogg',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'zip' => 'application/zip',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

/// Полотно переписки.
///
/// В образце это `.chat-canvas`: подсвет акцентом из левого верхнего угла и
/// точечная сетка поверх полотна. Ровная заливка выглядела бы плоско рядом
/// с ним, а разница в цвете фона — первое, что бросается в глаза при
/// сравнении двух клиентов.
class ChatCanvas extends StatelessWidget {
  const ChatCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: CustomPaint(
        painter: _CanvasPainter(accent: scheme.primary, dot: scheme.onSurface),
        // Красить нужно всю площадь, а не размер ребёнка: детей у полотна нет.
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({required this.accent, required this.dot});

  final Color accent;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    // Подсвет: круг от левого верхнего угла, сходящий на нет к 38 % ширины.
    final radius = size.width * Tokens.canvasGlowRadius;
    final origin = Offset(size.width * 0.16, 0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: Tokens.canvasGlow),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: origin, radius: radius)),
    );

    // Сетка: точка в пиксель с шагом 24, как `background-size: 24px 24px`.
    final paint = Paint()..color = dot.withValues(alpha: Tokens.canvasDot);
    for (var y = 1.0; y < size.height; y += Tokens.canvasDotStep) {
      for (var x = 1.0; x < size.width; x += Tokens.canvasDotStep) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.accent != accent || old.dot != dot;
}

/// Чьё сообщение цитируется. В личной переписке имя собеседника в шапке, и
/// в цитате важно лишь «вы или он»; в группе — имя.
String _quotedAuthor(
  Message reply,
  List<Message> all,
  Map<String, User> users,
  String myUserId,
) {
  final source = all.where((m) => m.id == reply.replyToId).firstOrNull;
  if (source == null) return '';
  if (source.senderId == myUserId) return 'Вы';
  return users[source.senderId]?.displayName ?? 'Собеседник';
}

class _Feed extends ConsumerWidget {
  const _Feed({
    required this.chatId,
    required this.myUserId,
    required this.isGroup,
    required this.users,
    required this.scroll,
    required this.topPadding,
    required this.bottomPadding,
    required this.onRendered,
    required this.onEdit,
    required this.onReply,
  });

  final String chatId;
  final String myUserId;
  final bool isGroup;
  final Map<String, User> users;
  final ScrollController scroll;
  final double topPadding;
  final double bottomPadding;
  final ValueChanged<List<Message>> onRendered;
  final ValueChanged<Message> onEdit;
  final ValueChanged<Message> onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider(chatId));

    return messages.when(
      loading: () => const StateView.loading(),
      error: (e, _) =>
          StateView.error(e, title: 'Не удалось открыть переписку'),
      data: (list) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onRendered(list));
        if (list.isEmpty) return const _FirstMessage();

        final rows = _rows(list);

        return ListView.builder(
          controller: scroll,
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row.divider != null) return _DateDivider(date: row.divider!);

            final message = row.message!;

            // Запись о звонке — не сообщение: её никто не писал, отвечать
            // и править нечего. Отдельной строкой посередине, как
            // разделитель даты, а не пузырём с хвостиком.
            if (message.kind == 'call') {
              return _CallRow(
                key: ValueKey(message.id),
                message: message,
                outgoing: message.senderId == myUserId,
              );
            }

            return _Bubble(
              key: ValueKey(message.id),
              message: message,
              isMine: message.senderId == myUserId,
              senderName: isGroup
                  ? users[message.senderId]?.displayName ?? ''
                  : '',
              showSender: row.startsBlock,
              onEdit: onEdit,
              onReply: onReply,
              quoted: message.replyToId == null
                  ? null
                  : list.where((m) => m.id == message.replyToId).firstOrNull,
              quotedAuthor: message.replyToId == null
                  ? ''
                  : _quotedAuthor(message, list, users, myUserId),
            );
          },
        );
      },
    );
  }

  /// Раскладка ленты: перед первым сообщением каждого дня — разделитель.
  ///
  /// Считается здесь, а не в билдере строки: там пришлось бы на каждую
  /// строку оглядываться на предыдущую, и разделители разъезжались бы при
  /// прокрутке длинной ленты.
  static List<_Row> _rows(List<Message> messages) {
    final rows = <_Row>[];
    DateTime? day;
    String? previousSender;

    for (final message in messages) {
      final at = message.createdAt;
      final messageDay = DateTime(at.year, at.month, at.day);
      if (day != messageDay) {
        rows.add(_Row.divider(messageDay));
        day = messageDay;
        previousSender = null;
      }
      rows.add(
        _Row.message(message, startsBlock: previousSender != message.senderId),
      );
      previousSender = message.senderId;
    }
    return rows;
  }
}

/// Строка ленты — либо сообщение, либо дата.
class _Row {
  const _Row.message(this.message, {required this.startsBlock})
    : divider = null;
  const _Row.divider(DateTime date)
    : divider = date,
      message = null,
      startsBlock = false;

  final Message? message;
  final DateTime? divider;

  /// Первое сообщение подряд идущих от одного человека: только у него
  /// показывается имя и увеличенный отступ сверху.
  final bool startsBlock;
}

/// Дата посреди ленты.
class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space3,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Tokens.br12),
          ),
          child: Text(
            _label(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  static String _label(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(date).inDays;

    if (days == 0) return 'Сегодня';
    if (days == 1) return 'Вчера';
    if (days < 7) return DateFormat.EEEE('ru').format(date);
    if (date.year == now.year) return DateFormat('d MMMM', 'ru').format(date);
    return DateFormat('d MMMM y', 'ru').format(date);
  }
}

/// Пустая переписка.
class _FirstMessage extends StatelessWidget {
  const _FirstMessage();

  @override
  Widget build(BuildContext context) {
    return const StateView(
      icon: TitoIcons.chat,
      title: 'Здесь пока ничего нет',
      description: 'Напишите первым — сообщение уйдёт сразу.',
    );
  }
}

/// Строка о звонке в ленте.
class _CallRow extends StatelessWidget {
  const _CallRow({required this.message, required this.outgoing, super.key});

  final Message message;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = _payload();
    final reason = call['reason'] as String? ?? 'hangup';
    final seconds = (call['seconds'] as num?)?.toInt() ?? 0;
    final missed = reason == 'missed' || reason == 'declined';

    // Пропущенный для того, кому звонили, — не то же, что для звонившего:
    // один не дозвонился, другой не услышал. Красным он только у второго.
    final alarming = missed && !outgoing;
    final color = alarming
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space3,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Tokens.radiusShell),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                missed
                    ? TitoIcons.callMissed
                    : outgoing
                    ? TitoIcons.callOut
                    : TitoIcons.callIn,
                size: 14,
                color: color,
              ),
              const SizedBox(width: Tokens.space2),
              Text(
                _label(reason, seconds),
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
              const SizedBox(width: Tokens.space2),
              Text(
                DateFormat.Hm().format(message.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _payload() {
    final raw = message.payloadJson;
    if (raw == null || raw.isEmpty) return const {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Подробности пропадут, сама запись останется: то, что звонок был,
      // важнее того, сколько он длился.
      return const {};
    }
  }

  String _label(String reason, int seconds) {
    if (reason == 'declined') {
      return outgoing ? 'Звонок отклонён' : 'Вы отклонили звонок';
    }
    if (reason == 'missed' || seconds == 0) {
      return outgoing ? 'Не ответили' : 'Пропущенный звонок';
    }
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '${outgoing ? 'Исходящий' : 'Входящий'} звонок · $minutes:$rest';
  }
}

/// Пузырь сообщения.
///
/// Появляется с коротким проявлением и сдвигом снизу. Не AnimatedList:
/// список приходит потоком из базы и перестраивается целиком, а AnimatedList
/// требует ручного учёта вставок — с потоком это источник рассинхронов.
class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.showSender,
    this.onEdit,
    this.onReply,
    this.quoted,
    this.quotedAuthor = '',
    super.key,
  });

  final Message message;
  final bool isMine;
  final String senderName;
  final bool showSender;

  /// Взяться править: экран подставит текст в поле ввода.
  final ValueChanged<Message>? onEdit;

  /// Взяться отвечать: над полем встанет цитата.
  final ValueChanged<Message>? onReply;

  /// Сообщение, на которое отвечали, и его автор. null — ответа не было.
  /// Может быть null и при заполненном replyToId: цитируемое могло не
  /// доехать при листании назад, и тогда цитата просто не рисуется.
  final Message? quoted;
  final String quotedAuthor;

  /// Меню сообщения по долгому нажатию.
  ///
  /// Править и удалять можно только своё — так же решает и сервер; здесь мы
  /// лишь не показываем заведомый отказ.
  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final deleted = message.deletedAt != null;
    if (deleted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(TitoIcons.reply),
              title: const Text('Ответить'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(TitoIcons.copy),
              title: const Text('Копировать'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (isMine) ...[
              ListTile(
                leading: const Icon(TitoIcons.edit),
                title: const Text('Изменить'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(
                  TitoIcons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Удалить у всех',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'reply':
        onReply?.call(message);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
        if (context.mounted) showMessage(context, 'Скопировано');
      case 'edit':
        onEdit?.call(message);
      case 'delete':
        try {
          await ref
              .read(repositoryProvider)
              ?.delete(message.chatId, message.id);
        } on ProtocolException catch (error) {
          if (context.mounted) showMessage(context, error.message);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final deleted = message.deletedAt != null;
    final attachments = _attachments();
    final onBubble = theme.colorScheme.onSurface;
    final subdued = theme.colorScheme.onSurfaceVariant;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: () => _menu(context, ref),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            margin: EdgeInsets.only(
              left: isMine ? 48 : 12,
              right: isMine ? 12 : 48,
              top: showSender ? 8 : 2,
              bottom: 2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isMine
                  ? TitoTheme.ownBubble(theme.colorScheme)
                  : TitoTheme.otherBubble(theme.colorScheme),
              // В образце обводки у пузырей нет — есть `--shadow-border`,
              // волосяная белая линия в восемь сотых. Она одинакова у обоих
              // пузырей, поэтому и здесь одна на оба.
              boxShadow: Tokens.shadowBorder,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 5),
                bottomRight: Radius.circular(isMine ? 5 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSender && !isMine && senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      senderName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        // В образце имя отправителя — акцент, один на всех.
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                // Цитата: на что отвечали. Без неё ответ в живой переписке
                // теряется — через десяток сообщений непонятно, к чему он.
                if (quoted != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.only(left: Tokens.space2),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          quotedAuthor,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          quoted!.body.isEmpty ? 'Вложение' : quoted!.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: subdued,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final attachment in attachments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _Attachment(attachment: attachment, isMine: isMine),
                  ),
                if (deleted)
                  Text(
                    'Сообщение удалено',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: subdued,
                    ),
                  )
                else if (message.body.isNotEmpty)
                  Text(
                    message.body,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.35,
                      color: onBubble,
                    ),
                  ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (message.editedAt != null && !deleted)
                      Text(
                        'изменено · ',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: subdued,
                        ),
                      ),
                    if (message.editedAt != null && !deleted) ...[
                      Text(
                        'изменено',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: subdued,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      DateFormat.Hm().format(message.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: subdued,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      _StateIcon(state: message.sendState, color: subdued),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _attachments() {
    final raw = message.attachmentsJson;
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }
}

/// Значок состояния отправки: часики, галочка или предупреждение.
class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state, required this.color});

  final SendState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      SendState.pending => Icon(TitoIcons.pending, size: 13, color: color),
      SendState.sent => Icon(TitoIcons.sent, size: 13, color: color),
      SendState.failed => Icon(
        TitoIcons.failed,
        size: 13,
        color: Theme.of(context).colorScheme.error,
      ),
    };
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.attachment, required this.isMine});

  final Map<String, dynamic> attachment;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final url = attachment['url'] as String?;
    final kind = attachment['kind'] as String?;

    // Звук не строка со скрепкой: его слушают, а не скачивают.
    if (kind == 'audio' && url != null) {
      return VoiceBubble(
        url: url,
        seconds: attachment['duration'] as int? ?? 0,
        isMine: isMine,
      );
    }

    if (kind == 'image' && url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _AttachmentStub(),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(TitoIcons.file, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            attachment['file_name'] as String? ?? 'Файл',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AttachmentStub extends StatelessWidget {
  const _AttachmentStub();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 120,
    child: Center(child: Icon(TitoIcons.brokenImage)),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onEmoji,
    required this.onSend,
    required this.onChanged,
    required this.onAttach,
    required this.recordSeconds,
    required this.onStartRecording,
    required this.onFinishRecording,
    required this.onCancelRecording,
    this.editing,
    this.onCancelEdit,
    this.replyingTo,
    this.onCancelReply,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onEmoji;
  final VoidCallback onSend;
  final VoidCallback onChanged;
  final VoidCallback onAttach;

  /// Правящееся сообщение — над полем показывается полоска с его текстом.
  final Message? editing;
  final VoidCallback? onCancelEdit;

  /// Сообщение, на которое отвечаем: та же полоска, но с цитатой.
  final Message? replyingTo;
  final VoidCallback? onCancelReply;

  /// Сколько секунд идёт запись. null — записи нет.
  final int? recordSeconds;
  final VoidCallback onStartRecording;
  final VoidCallback onFinishRecording;
  final VoidCallback onCancelRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = editing;

    return GlassSurface(
      borderSide: GlassBorder.top,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message != null)
              _ComposerStrip(
                icon: TitoIcons.edit,
                title: 'Правка сообщения',
                body: message.body,
                tooltip: 'Отменить правку',
                onCancel: onCancelEdit,
              ),
            if (replyingTo != null)
              _ComposerStrip(
                icon: TitoIcons.reply,
                title: 'Ответ на сообщение',
                body: replyingTo!.body.isEmpty
                    ? 'Вложение'
                    : replyingTo!.body,
                tooltip: 'Отменить ответ',
                onCancel: onCancelReply,
              ),
            if (recordSeconds != null)
              // Во время записи поле ввода уступает место счётчику: писать
              // и говорить одновременно нельзя, а показывать оба состояния
              // значит сбивать с толку.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        TitoIcons.delete,
                        size: 22,
                        color: scheme.error,
                      ),
                      tooltip: 'Отменить запись',
                      onPressed: onCancelRecording,
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Tokens.space2),
                    Text(
                      _recordTime(recordSeconds!),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: TitoTheme.tabularFigures,
                      ),
                    ),
                    const SizedBox(width: Tokens.space2),
                    Expanded(
                      child: Text(
                        'идёт запись',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _SendButton(onPressed: onFinishRecording),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(
                        TitoIcons.attach,
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                      tooltip: 'Прикрепить',
                      onPressed: onAttach,
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Сообщение',
                        ),
                        onChanged: (_) => onChanged(),
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        TitoIcons.emoji,
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                      tooltip: 'Эмодзи',
                      onPressed: onEmoji,
                    ),
                    const SizedBox(width: 4),
                    // Пустое поле — микрофон, набранный текст — отправка.
                    // Так устроено везде, и человек не ищет, куда делась
                    // кнопка.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) =>
                          value.text.trim().isEmpty && message == null
                          ? _MicButton(onPressed: onStartRecording)
                          : _SendButton(
                              onPressed: onSend,
                              editing: message != null,
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Секунды в «м:сс» для счётчика записи.
String _recordTime(int total) {
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Кнопка записи голосового. Стоит на месте отправки, пока поле пустое.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        icon: Icon(TitoIcons.voice, size: 22, color: scheme.onSurfaceVariant),
        tooltip: 'Записать голосовое',
        onPressed: onPressed,
      ),
    );
  }
}

/// Кнопка отправки.
///
/// Отдельным виджетом ради отклика на нажатие: кнопка слегка поджимается,
/// и палец получает подтверждение раньше, чем сообщение долетит до сервера.
class _SendButton extends StatefulWidget {
  const _SendButton({required this.onPressed, this.editing = false});

  final VoidCallback onPressed;

  /// В режиме правки кнопка сохраняет, а не отправляет: значок другой,
  /// иначе непонятно, что произойдёт от нажатия.
  final bool editing;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          // Здесь акценту и место: одна кнопка действия на экран.
          child: Icon(
            widget.editing ? TitoIcons.sent : TitoIcons.send,
            size: 22,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}


/// Кнопка звонка в шапке переписки.
///
/// Работает и до того, как переписка заведена: человека могли только что
/// найти в поиске, и требовать сначала написать «привет» — лишний шаг.
class _CallButton extends ConsumerWidget {
  const _CallButton({required this.peer, this.chatId});

  final User peer;
  final String? chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Пока идёт другой звонок, кнопка гаснет: второй означал бы два
    // открытых микрофона и путаницу, кому какой ответ.
    final busy = ref.watch(currentCallProvider).value != null;

    return IconButton(
      icon: const Icon(TitoIcons.callStart, size: 20),
      tooltip: 'Позвонить',
      onPressed: busy
          ? null
          : () async {
              try {
                final service = ref.read(callServiceProvider);
                await service.start(
                  peerId: peer.id,
                  peerName: peer.displayName,
                  chatId: chatId,
                );

                // Звонили из черновика — сервер завёл переписку, и
                // открытой должна стать она. Иначе после разговора человек
                // смотрит на пустой экран, хотя запись о звонке уже
                // пришла.
                final real = service.current?.chatId;
                if (chatId == null && real != null && real.isNotEmpty) {
                  ref.read(selectedChatProvider.notifier).state = real;
                  ref.read(draftPeerProvider.notifier).state = null;
                }
              } catch (_) {
                if (context.mounted) {
                  showMessage(context, 'Нет доступа к микрофону');
                }
              }
            },
    );
  }
}


/// Полоска над полем ввода: что сейчас делаем с сообщением.
///
/// Одна на правку и на ответ — у них одинаковая роль и одинаковый вид, а
/// две копии тридцати строк разметки разошлись бы при первой же правке.
class _ComposerStrip extends StatelessWidget {
  const _ComposerStrip({
    required this.icon,
    required this.title,
    required this.body,
    required this.tooltip,
    required this.onCancel,
  });

  final IconData icon;
  final String title;
  final String body;
  final String tooltip;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(TitoIcons.close, size: 18),
            tooltip: tooltip,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
