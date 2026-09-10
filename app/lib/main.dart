import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/auth/phone_screen.dart';
import 'features/chats/chats_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ProviderScope(child: MayakApp()));
}

class MayakApp extends StatelessWidget {
  const MayakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Маяк',
      debugShowCheckedModeBanner: false,
      theme: MayakTheme.light(),
      darkTheme: MayakTheme.dark(),
      home: const _Root(),
    );
  }
}

/// Развилка: вошедшего ведём в чаты, остальных — на ввод номера.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const _Splash(),
      error: (_, __) => const PhoneScreen(),
      data: (value) {
        if (value == null) return const PhoneScreen();
        // Репозиторий и сокет поднимаются здесь: до входа им нечего делать.
        return const _Connected(child: ChatsScreen());
      },
    );
  }
}

/// Держит соединение живым, пока показан вложенный экран.
class _Connected extends ConsumerStatefulWidget {
  const _Connected({required this.child});

  final Widget child;

  @override
  ConsumerState<_Connected> createState() => _ConnectedState();
}

class _ConnectedState extends ConsumerState<_Connected>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Создание репозитория подписывает его на события сокета.
    ref.read(repositoryProvider);
    ref.read(typingEventsProvider);
    ref.read(wsProvider).connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Система рвёт сокеты у свёрнутых приложений. Возврат на экран — повод
    // проверить связь, не дожидаясь таймаута heartbeat.
    if (state == AppLifecycleState.resumed) {
      ref.read(wsProvider).connect();
      ref.read(repositoryProvider)?.drainOutbox();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
