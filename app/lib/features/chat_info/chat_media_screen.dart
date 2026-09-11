import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';

/// Всё, чем обменивались в чате, кроме слов.
///
/// Читается из локальной базы: вложения уже лежат в сообщениях, отдельного
/// запроса к серверу не нужно, и список открывается офлайн.
class ChatMediaScreen extends ConsumerStatefulWidget {
  const ChatMediaScreen({required this.chatId, required this.title, super.key});

  final String chatId;
  final String title;

  @override
  ConsumerState<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends ConsumerState<ChatMediaScreen> {
  static const _tabs = ['Медиа', 'Файлы', 'Ссылки', 'Голосовые'];

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final messages =
        ref.watch(chatAttachmentsProvider(widget.chatId)).value ??
        const <Message>[];

    final items = _items(messages).where(_matchesTab).toList();

    return Scaffold(
      appBar: GlassAppBar(
        title: _Title(title: widget.title),
        bottomHeight: 34 + Tokens.space3,
        bottom: Column(
          children: [
            FilterChipsRow(
              labels: _tabs,
              index: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: Tokens.space3),
          ],
        ),
      ),
      body: items.isEmpty
          ? StateView(icon: _emptyIcon, title: _emptyTitle)
          : _tab == 0
          ? _Grid(items: items)
          : _Rows(items: items),
    );
  }

  bool _matchesTab(_Item item) => switch (_tab) {
    0 => item.kind == 'image' || item.kind == 'video',
    1 => item.kind == 'file' || item.kind == 'document',
    2 => item.kind == 'link',
    _ => item.kind == 'voice' || item.kind == 'audio',
  };

  IconData get _emptyIcon => switch (_tab) {
    0 => TitoIcons.image,
    1 => TitoIcons.file,
    2 => TitoIcons.link,
    _ => TitoIcons.voice,
  };

  String get _emptyTitle => switch (_tab) {
    0 => 'Фото и видео не отправляли',
    1 => 'Файлов не было',
    2 => 'Ссылок не было',
    _ => 'Голосовых не было',
  };

  /// Разворачивает сообщения в плоский список вложений: экран показывает
  /// именно их, а не сообщения, в которых они приехали.
  static List<_Item> _items(List<Message> messages) {
    final items = <_Item>[];
    for (final message in messages) {
      final raw = message.attachmentsJson;
      if (raw == null) continue;
      try {
        for (final entry in jsonDecode(raw) as List<dynamic>) {
          final attachment = entry as Map<String, dynamic>;
          items.add(
            _Item(
              kind: attachment['kind'] as String? ?? 'file',
              url: attachment['url'] as String?,
              name: attachment['file_name'] as String? ?? 'Файл',
              size: attachment['size'] as int?,
              at: message.createdAt,
            ),
          );
        }
      } catch (_) {
        // Битый JSON — пропускаем вложение, а не роняем экран.
      }
    }
    return items;
  }
}

class _Item {
  const _Item({
    required this.kind,
    required this.url,
    required this.name,
    required this.size,
    required this.at,
  });

  final String kind;
  final String? url;
  final String name;
  final int? size;
  final DateTime at;
}

class _Title extends StatelessWidget {
  const _Title({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
        ),
        Text(
          'Медиа',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Сетка картинок, разбитая по дням.
class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<_Item>>{};
    for (final item in items) {
      final day = DateTime(item.at.year, item.at.month, item.at.day);
      byDay.putIfAbsent(day, () => []).add(item);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Tokens.space6),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(_dayLabel(day)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: Tokens.space2,
                crossAxisSpacing: Tokens.space2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final item in byDay[day]!) _Tile(item: item),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ago = today.difference(day).inDays;
    if (ago == 0) return 'Сегодня';
    if (ago == 1) return 'Вчера';
    if (day.year == now.year) return DateFormat('d MMMM', 'ru').format(day);
    return DateFormat('d MMMM y', 'ru').format(day);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = item.url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.br8),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: url == null
            ? Icon(TitoIcons.brokenImage, color: scheme.outline)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(TitoIcons.brokenImage, color: scheme.outline),
              ),
      ),
    );
  }
}

/// Файлы, ссылки и голосовые — строками, а не плитками: у них нет вида,
/// который что-то говорит с первого взгляда.
class _Rows extends StatelessWidget {
  const _Rows({required this.items});

  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const RowDivider(),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              switch (item.kind) {
                'link' => TitoIcons.link,
                'voice' || 'audio' => TitoIcons.voice,
                _ => TitoIcons.file,
              },
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
          subtitle: Text(
            [
              if (item.size != null) _size(item.size!),
              DateFormat('d MMM', 'ru').format(item.at),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }
}
