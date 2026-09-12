import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/emoji.dart';
import '../../ui/tokens.dart';

/// Ключ настройки с недавними эмодзи.
///
/// В базе, а не в памяти экрана: недавние переживают перезапуск, иначе
/// каждое утро приходится заново искать те же пять знаков.
const _recentPref = 'emoji.recent';

/// Панель выбора эмодзи.
///
/// Шторкой снизу, а не окном: на телефоне она встаёт на место клавиатуры,
/// и рука остаётся там же, где была. Выбор не закрывает панель — знаки
/// ставят подряд, и закрывать её после каждого значило бы открывать снова.
Future<void> showEmojiSheet(
  BuildContext context,
  ValueChanged<String> onPick,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EmojiSheet(onPick: onPick),
  );
}

class _EmojiSheet extends ConsumerStatefulWidget {
  const _EmojiSheet({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  ConsumerState<_EmojiSheet> createState() => _EmojiSheetState();
}

class _EmojiSheetState extends ConsumerState<_EmojiSheet> {
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final raw = await ref.read(databaseProvider).watchPref(_recentPref).first;
    if (!mounted || raw == null || raw.isEmpty) return;
    setState(() => _recent = raw.split(' ').where((e) => e.isNotEmpty).toList());
  }

  Future<void> _pick(String emoji) async {
    widget.onPick(emoji);
    final next = [emoji, ..._recent.where((e) => e != emoji)]
        .take(emojiRecentLimit)
        .toList();
    setState(() => _recent = next);
    await ref.read(databaseProvider).setPref(_recentPref, next.join(' '));
  }

  @override
  Widget build(BuildContext context) {
    // Половина экрана: выше — закрывает переписку, ниже — в один ряд знаков
    // не поместится ничего.
    final height = MediaQuery.sizeOf(context).height * 0.45;

    return SizedBox(
      height: height,
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            if (_recent.isNotEmpty) ...[
              _label('Недавние'),
              _grid(_recent),
            ],
            for (final group in emojiGroups) ...[
              _label(group.title),
              _grid(group.items),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: Tokens.space4)),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.space4,
          Tokens.space3,
          Tokens.space4,
          Tokens.space1,
        ),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _grid(List<String> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space3),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 48,
          childAspectRatio: 1,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final emoji = items[index];
          return InkWell(
            onTap: () => _pick(emoji),
            borderRadius: BorderRadius.circular(Tokens.radiusShell),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          );
        },
      ),
    );
  }
}
