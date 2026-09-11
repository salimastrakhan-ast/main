import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/icons.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';
import '../chat/chat_screen.dart';
import '../sidebar/sidebar_pane.dart';

/// Оболочка приложения: панель и переписка.
///
/// Устроена как в веб-клиенте. На широком экране обе части видны сразу, на
/// узком — по одной: панель, пока чат не выбран, и переписка после. Порог
/// тот же, что у них: 768 точек — ниже него две колонки по 360 не
/// помещаются, и вторая выродилась бы в щель.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Ширина, с которой панель и переписка встают рядом.
  static const twoPaneFrom = 768.0;

  /// Ширина панели — как `--width-sidebar` в источнике.
  static const sidebarWidth = 360.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= twoPaneFrom;
    final selected = ref.watch(selectedChatProvider);
    final draftPeer = ref.watch(draftPeerProvider);
    final showChat = selected != null || draftPeer != null;

    Widget pane() => ChatPane(
      key: ValueKey(selected ?? draftPeer),
      chatId: selected,
      peerId: draftPeer,
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            const SizedBox(width: sidebarWidth, child: SidebarPane()),
            VerticalDivider(
              width: Tokens.borderSm,
              thickness: Tokens.borderSm,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: showChat ? pane() : const _NoChatChosen()),
          ],
        ),
      );
    }

    // На узком экране «назад» снимает выбор чата, а не закрывает
    // приложение: переписка здесь не маршрут, и системная кнопка иначе
    // выбрасывала бы человека наружу прямо из чата.
    return PopScope(
      canPop: !showChat,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(selectedChatProvider.notifier).state = null;
        ref.read(draftPeerProvider.notifier).state = null;
      },
      child: Scaffold(body: showChat ? pane() : const SidebarPane()),
    );
  }
}

/// Правая часть, пока чат не выбран. Бывает только на широком экране.
class _NoChatChosen extends StatelessWidget {
  const _NoChatChosen();

  @override
  Widget build(BuildContext context) {
    return const StateView(
      icon: TitoIcons.chat,
      title: 'Выберите диалог',
      description: 'Или начните новый — кнопка в шапке панели.',
    );
  }
}
