import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Нативный SQLite: iOS, Android, десктоп.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    // createInBackground уводит запросы в отдельный изолят: иначе большая
    // выборка истории подвешивает кадры анимации.
    return NativeDatabase.createInBackground(
      File(p.join(dir.path, 'tito.sqlite')),
    );
  });
}
