/// Настройки сборки.
///
/// Адрес сервера задаётся при сборке:
///   flutter run --dart-define=TITO_API=https://api.example.ru
/// Значение по умолчанию рассчитано на локальный сервер из Makefile.
class AppConfig {
  const AppConfig._();

  static const apiBase = String.fromEnvironment(
    'TITO_API',
    defaultValue: 'http://localhost:8080',
  );

  /// Адрес сокета выводится из адреса API: держать две настройки, которые
  /// обязаны указывать на одну машину, — способ однажды их рассинхронизировать.
  static String get wsUrl {
    final base = Uri.parse(apiBase);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme, path: '/v1/ws').toString();
  }

  /// Версия протокола. Должна совпадать с ws.Version на сервере.
  static const protocolVersion = 1;
}
