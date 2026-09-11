import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../ui/glass.dart';
import '../../ui/state_view.dart';
import '../../ui/theme.dart';

/// Переписка.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.chatId, required this.title, super.key});

  final String chatId;
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
    await ref.read(repositoryProvider)?.send(chatId: widget.chatId, text: text);
    // Скроллим после того, как база разбудит подписчиков и лента вырастет.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    if (_typingThrottle?.isActive ?? false) return;
    _typingThrottle = Timer(const Duration(seconds: 3), () {});
    ref.read(repositoryProvider)?.sendTyping(widget.chatId);
  }

  /// Отмечает прочитанным всё до последнего показанного сообщения.
  void _markRead(List<Message> messages) {
    final last = messages.where((m) => m.seq > 0).lastOrNull;
    if (last == null || last.seq <= _lastReadSeq) return;
    _lastReadSeq = last.seq;
    ref.read(repositoryProvider)?.markRead(widget.chatId, last.seq);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.chatId));
    final users = ref.watch(usersProvider).value ?? const {};
    final myUserId = ref.watch(sessionProvider).value?.userId ?? '';
    final typing = ref.watch(typingProvider)[widget.chatId] ?? const {};

    return Scaffold(
      // Лента уезжает под шапку и под поле ввода — иначе размывать нечего и
      // стекло выглядит просто матовой плашкой.
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 17),
            ),
            if (typing.isNotEmpty)
              Text(
                'печатает…',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: messages.when(
              loading: () => const StateView.loading(),
              error: (e, _) =>
                  StateView.error(e, title: 'Не удалось открыть переписку'),
              data: (list) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markRead(list);
                  _measureComposer();
                });
                if (list.isEmpty) {
                  return const StateView(
                    icon: Icons.chat_bubble_outline,
                    title: 'Здесь пока ничего нет',
                    description: 'Напишите первым — сообщение уйдёт сразу.',
                  );
                }

                return ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.only(
                    top: glassAppBarHeight(context, extra: 12),
                    bottom: _composerHeight + 12,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final message = list[index];
                    return _Bubble(
                      key: ValueKey(message.id),
                      message: message,
                      isMine: message.senderId == myUserId,
                      senderName: users[message.senderId]?.displayName ?? '',
                      showSender: !_isSameSenderAsPrevious(list, index),
                    );
                  },
                );
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
            ),
          ),
        ],
      ),
    );
  }

  /// Подряд идущие сообщения одного человека подписываются один раз.
  static bool _isSameSenderAsPrevious(List<Message> list, int index) {
    if (index == 0) return false;
    return list[index - 1].senderId == list[index].senderId;
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
      SendState.pending => Icon(Icons.schedule, size: 13, color: color),
      SendState.sent => Icon(Icons.done, size: 13, color: color),
      SendState.failed => Icon(
        Icons.error_outline,
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
        const Icon(Icons.description_outlined, size: 20),
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
    child: Center(child: Icon(Icons.broken_image_outlined)),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderSide: GlassBorder.top,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
          child: Icon(Icons.arrow_upward_rounded, size: 22, color: scheme.onPrimary),
        ),
      ),
    );
  }
}
