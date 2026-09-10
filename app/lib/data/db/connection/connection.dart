/// Выбор бэкенда базы под платформу.
///
/// На телефонах и десктопе это нативный SQLite через FFI, в браузере — та же
/// SQLite, собранная в WebAssembly. Условный экспорт нужен потому, что
/// `dart:ffi` в вебе не существует вовсе, и обычный импорт ломает сборку
/// целиком, а не отключает одну ветку.
library;

export 'unsupported.dart'
    if (dart.library.ffi) 'native.dart'
    if (dart.library.js_interop) 'web.dart';
