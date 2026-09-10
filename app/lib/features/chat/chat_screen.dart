import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
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
  Timer? _typingThrottle;
  int _lastReadSeq = 0;

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
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 17)),
            if (typing.isNotEmpty)
              Text('печатает…',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
              data: (list) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _markRead(list));
                if (list.isEmpty) return const _EmptyChat();

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final message = list[index];
                    return _Bubble(
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
          _Composer(
            controller: _input,
            onSend: _send,
            onChanged: _onTyping,
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

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.showSender,
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

    return Align(
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
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender && !isMine && senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(senderName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    )),
              ),
            for (final attachment in attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _Attachment(attachment: attachment),
              ),
            if (deleted)
              Text('Сообщение удалено',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ))
            else if (message.body.isNotEmpty)
              Text(message.body, style: const TextStyle(fontSize: 15.5)),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (message.editedAt != null && !deleted)
                  Text('изменено · ',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                Text(DateFormat.Hm().format(message.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  _StateIcon(state: message.sendState),
                ],
              ],
            ),
          ],
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
  const _StateIcon({required this.state});

  final SendState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (state) {
      SendState.pending => Icon(Icons.schedule,
          size: 13, color: theme.colorScheme.onSurfaceVariant),
      SendState.sent => Icon(Icons.done,
          size: 13, color: theme.colorScheme.onSurfaceVariant),
      SendState.failed =>
        Icon(Icons.error_outline, size: 13, color: theme.colorScheme.error),
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
        const Icon(Icons.insert_drive_file_outlined, size: 20),
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
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.arrow_upward),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                minimumSize: const Size(48, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text('Здесь пока ничего нет',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
