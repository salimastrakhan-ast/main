import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// SQLite в браузере: та же база, собранная в WebAssembly.
///
/// Для работы в web/ должны лежать sqlite3.wasm и drift_worker.js — их кладёт
/// команда из README. Без них сборка соберётся, но база в браузере не
/// откроется.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'mayak',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
