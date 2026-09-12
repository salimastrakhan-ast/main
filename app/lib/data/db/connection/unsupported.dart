import 'package:drift/drift.dart';

/// Заглушка для платформ, где нет ни FFI, ни браузерных API.
/// Сюда попасть не должно — ветка существует ради корректного условного
/// экспорта.
QueryExecutor openConnection() {
  throw UnsupportedError('Платформа не поддерживает локальную базу');
}
