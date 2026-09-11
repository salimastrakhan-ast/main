import 'package:flutter/material.dart';

import '../../ui/icons.dart';
import '../../ui/nav.dart';
import '../calls/calls_screen.dart';
import '../chats/chats_screen.dart';
import '../contacts/contacts_screen.dart';
import '../settings/settings_screen.dart';

/// Разделы приложения под общей навигацией.
///
/// Экраны держатся в `IndexedStack`, а не пересоздаются при переключении:
/// иначе список диалогов каждый раз прокручивался бы в начало, а набранный
/// в поиске текст пропадал.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Ширина, с которой нижняя панель уступает место боковой рейке.
  ///
  /// 640 — это примерно планшет в портрете и любое окно браузера шире
  /// телефонного. Ниже панель внизу, у большого пальца; выше она уезжала бы
  /// к краю экрана, куда тянуться неудобно и незачем.
  static const railFrom = 640.0;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _items = [
    NavItem(icon: MayakIcons.chats, label: 'Чаты'),
    NavItem(icon: MayakIcons.contacts, label: 'Контакты'),
    NavItem(icon: MayakIcons.calls, label: 'Звонки'),
    NavItem(icon: MayakIcons.settings, label: 'Настройки'),
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= HomeScreen.railFrom;

    final content = IndexedStack(
      index: _index,
      children: const [
        ChatsScreen(),
        ContactsScreen(),
        CallsScreen(),
        SettingsScreen(),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            MayakNavRail(
              items: _items,
              index: _index,
              onSelect: (i) => setState(() => _index = i),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: MayakNavBar(
        items: _items,
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}
