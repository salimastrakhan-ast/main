import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../ui/icons.dart';
import '../../ui/glass.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../chat_info/chat_info_screen.dart';

/// Открывает переписку с человеком.
///
/// Чата может ещё не быть: на сервере личный чат заводится первым
/// сообщением, а не открытием экрана. Поэтому сюда передаётся собеседник, а
/// экран сам подхватит чат, как только тот появится.
void openChatWith(BuildContext context, WidgetRef ref, User person) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatScreen(peerId: person.id, title: person.displayName),
    ),
  );
}

/// Переписка.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.title,
    this.chatId,
    this.peerId,
    super.key,
  }) : assert(
         chatId != null || peerId != null,
         'нужен либо чат, либо собеседник',
       );

  /// Чат, если он уже заведён.
  final String? chatId;

  /// Собеседник — когда чата ещё нет.
  final String? peerId;

  final String title;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _composerKey = GlobalKey();
  Timer? _typingThrottle;
  int _lastReadSeq = 0;

  /// Высота поля ввода. Лента уходит под него, и на этот отступ снизу она
  /// сдвигается, иначе последнее сообщение окажется под полем. Значение
  /// измеряется, а не задаётся: поле растёт до пяти строк.
  double _composerHeight = 76;

  /// Чат этого экрана. Пока переписки не было, он null — и это нормальное
  /// состояние, а не ошибка.
  String? get _chatId =>
      widget.chatId ??
      ref.watch(privateChatWithProvider(widget.peerId!)).value;

  void _measureComposer() {
    final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if ((box.size.height - _composerHeight).abs() < 0.5) return;
    setState(() => _composerHeight = box.size.height);
  }

  @override
  void dispose() {
    _typingThrottle?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    _input.clear();
    await ref.read(repositoryProvider)?.send(
      chatId: _chatId,
      peerId: _chatId == null ? widget.peerId : null,
      text: text,
    );
    // Скроллим после того, как база разбудит подписчиков и лента вырастет.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Картинка из галереи: сначала уходит файл, потом сообщение со ссылкой
  /// на него. Порядок важен — сообщение без загруженного вложения сервер
  /// отвергнет, и оно осело бы в очереди навсегда.
  Future<void> _attach() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await picked.readAsBytes();
      final attachment = await ref.read(apiProvider).upload(
        fileName: picked.name,
        bytes: bytes,
        mime: picked.mimeType ?? 'application/octet-stream',
      );
      final text = _input.text.trim();
      _input.clear();
      await ref.read(repositoryProvider)?.send(
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
    final chat = chatId == null
        ? null
        : ref.watch(chatProvider(chatId)).value;
    final isGroup = chat?.type == 'group';
    final myUserId = ref.watch(sessionProvider).value?.userId ?? '';
    final typing = chatId == null
        ? const <String>{}
        : ref.watch(typingProvider)[chatId] ?? const <String>{};

    final peer = widget.peerId != null
        ? users[widget.peerId]
        : (chatId == null ? null : ref.watch(chatPeersProvider).value?[chatId]);

    return Scaffold(
      // Лента уезжает под шапку и под поле ввода: иначе при прокрутке
      // содержимое обрывается ровно по краю панели.
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: _ChatTitle(
          id: chat?.id ?? peer?.id ?? widget.title,
          name: widget.title,
          isGroup: isGroup,
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
          IconButton(
            icon: const Icon(MayakIcons.call, size: 20),
            tooltip: 'Позвонить',
            onPressed: () => showNotReady(context, 'Звонки'),
          ),
          IconButton(
            icon: const Icon(MayakIcons.video, size: 20),
            tooltip: 'Видеозвонок',
            onPressed: () => showNotReady(context, 'Видеозвонки'),
          ),
          IconButton(
            icon: const Icon(MayakIcons.menu, size: 20),
            tooltip: 'Ещё',
            onPressed: chatId == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatInfoScreen(chatId: chatId),
                    ),
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
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
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Composer(
              key: _composerKey,
              controller: _input,
              onSend: _send,
              onChanged: _onTyping,
              onAttach: _attach,
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
    required this.peer,
    required this.typing,
    required this.onTap,
  });

  final String id;
  final String name;
  final bool isGroup;
  final User? peer;
  final bool typing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = switch (true) {
      _ when typing => ('печатает…', theme.colorScheme.primary),
      _ when isGroup => ('Группа', theme.colorScheme.onSurfaceVariant),
      _ when peer?.online ?? false => ('в сети', Tokens.olive),
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
            online: peer?.online ?? false,
            icon: isGroup ? MayakIcons.contacts : null,
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
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: status.$2,
                  ),
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
  });

  final String chatId;
  final String myUserId;
  final bool isGroup;
  final Map<String, User> users;
  final ScrollController scroll;
  final double topPadding;
  final double bottomPadding;
  final ValueChanged<List<Message>> onRendered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider(chatId));

    return messages.when(
      loading: () => const StateView.loading(),
      error: (e, _) => StateView.error(e, title: 'Не удалось открыть переписку'),
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
            return _Bubble(
              key: ValueKey(message.id),
              message: message,
              isMine: message.senderId == myUserId,
              senderName: isGroup
                  ? users[message.senderId]?.displayName ?? ''
                  : '',
              showSender: row.startsBlock,
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
  const _Row.message(this.message, {required this.startsBlock}) : divider = null;
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
      icon: MayakIcons.chat,
      title: 'Здесь пока ничего нет',
      description: 'Напишите первым — сообщение уйдёт сразу.',
    );
  }
}

/// Пузырь сообщения.
///
/// Появляется с коротким проявлением и сдвигом снизу. Не AnimatedList:
/// список приходит потоком из базы и перестраивается целиком, а AnimatedList
/// требует ручного учёта вставок — с потоком это источник рассинхронов.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.showSender,
    super.key,
  });

  final Message message;
  final bool isMine;
  final String senderName;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
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
                ? MayakTheme.ownBubble(theme.colorScheme)
                : MayakTheme.otherBubble(theme.colorScheme),
            // Своему пузырю граница не нужна: коралл сам себя очерчивает.
            border: isMine
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
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
                      color: MayakTheme.textAccentFor(message.senderId),
                    ),
                  ),
                ),
              for (final attachment in attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _Attachment(attachment: attachment),
                ),
              if (deleted)
                Text(
                  'Сообщение удалено',
                  style: TextStyle(fontStyle: FontStyle.italic, color: subdued),
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
                  Text(
                    DateFormat.Hm().format(message.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(color: subdued),
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
      SendState.pending => Icon(MayakIcons.pending, size: 13, color: color),
      SendState.sent => Icon(MayakIcons.sent, size: 13, color: color),
      SendState.failed => Icon(
        MayakIcons.failed,
        size: 13,
        color: Theme.of(context).colorScheme.error,
      ),
    };
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.attachment});

  final Map<String, dynamic> attachment;

  @override
  Widget build(BuildContext context) {
    final url = attachment['url'] as String?;
    final kind = attachment['kind'] as String?;

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
        const Icon(MayakIcons.file, size: 20),
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
    child: Center(child: Icon(MayakIcons.brokenImage)),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onChanged,
    required this.onAttach,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onChanged;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassSurface(
      borderSide: GlassBorder.top,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  MayakIcons.attach,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
                tooltip: 'Прикрепить',
                onPressed: onAttach,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Сообщение'),
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(onPressed: onSend),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка отправки.
///
/// Отдельным виджетом ради отклика на нажатие: кнопка слегка поджимается,
/// и палец получает подтверждение раньше, чем сообщение долетит до сервера.
class _SendButton extends StatefulWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback onPressed;

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
          // Здесь терракоту и место: одна кнопка действия на экран.
          child: Icon(MayakIcons.send, size: 22, color: scheme.onPrimary),
        ),
      ),
    );
  }
}
