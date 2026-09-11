import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/providers.dart';
import 'features/auth/phone_screen.dart';
import 'features/home/home_screen.dart';
import 'features/welcome/welcome_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Названия месяцев и дней недели по-русски. Без этого DateFormat с
  // локалью 'ru' падает, а разделители дат в ленте как раз на ней.
  await initializeDateFormatting('ru');
  runApp(const ProviderScope(child: MayakApp()));
}

class MayakApp extends ConsumerWidget {
  const MayakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return MaterialApp(
      title: 'Маяк',
      debugShowCheckedModeBanner: false,
      theme: MayakTheme.light(),
      darkTheme: MayakTheme.dark(),
      themeMode: mode,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

/// Развилка: вошедшего ведём в разделы, остальных — на вход, а тех, кто
/// здесь впервые, сначала на приветствие.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final welcomeSeen = ref.watch(welcomeSeenProvider);

    return session.when(
      loading: () => const _Splash(),
      error: (_, _) => const PhoneScreen(),
      data: (value) {
        if (value != null) {
          // Репозиторий и сокет поднимаются здесь: до входа им нечего делать.
          return const _Connected(child: HomeScreen());
        }
        return welcomeSeen.when(
          loading: () => const _Splash(),
          error: (_, _) => const PhoneScreen(),
          data: (seen) => seen ? const PhoneScreen() : const WelcomeScreen(),
        );
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
