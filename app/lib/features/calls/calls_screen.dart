import 'package:flutter/material.dart';

import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';

/// Звонки.
///
/// Экран есть, звонков нет: в сервере нет ни сигналинга, ни медиа — ни
/// команды на установление соединения, ни TURN, ни истории. Показывать
/// вместо этого выдуманный список было бы обманом: человек нажал бы на
/// строку и упёрся в пустоту.
///
/// Поэтому здесь честное пустое состояние. Когда появится звонковая часть,
/// на её место встанет список — вёрстка экрана уже под него сделана.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  static const _filters = ['Все', 'Пропущенные', 'Избранные'];

  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Звонки'),
        leading: const SizedBox.shrink(),
        bottomHeight: 34 + Tokens.space3,
        bottom: Column(
          children: [
            FilterChipsRow(
              labels: _filters,
              index: _filter,
              onSelect: (i) => setState(() => _filter = i),
            ),
            const SizedBox(height: Tokens.space3),
          ],
        ),
      ),
      body: StateView(
        icon: TitoIcons.calls,
        title: 'Звонков пока нет',
        description: 'Звонки появятся в следующей версии — '
            'сейчас в «Titoе» только переписка.',
        actionLabel: 'Что уже работает',
        onAction: () => showNotReady(context, 'Звонки'),
      ),
    );
  }
}
