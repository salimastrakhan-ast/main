import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tito/ui/emoji.dart';

/// Набор эмодзи повторён в двух клиентах, и разойтись он не должен:
/// отправленное с телефона обязано выглядеть в браузере тем же знаком.
void main() {
  group('Набор эмодзи', () {
    test('ни один знак не повторяется', () {
      final all = [for (final g in emojiGroups) ...g.items];
      expect(all.toSet().length, all.length,
          reason: 'один знак лежит в двух группах — в панели он задвоится');
    });

    test('в каждой группе есть что показать', () {
      for (final group in emojiGroups) {
        expect(group.items, isNotEmpty, reason: 'группа ${group.id} пуста');
        expect(group.title, isNotEmpty, reason: 'у группы ${group.id} нет названия');
      }
    });

    test('совпадает с набором веб-клиента', () {
      // Читаем исходник веба напрямую: сверять два списка глазами — значит
      // не сверять их вовсе.
      final web = File('../web/src/lib/emoji.ts');
      if (!web.existsSync()) {
        // В сборке без веб-клиента проверять нечего.
        return;
      }
      final source = web.readAsStringSync();

      final webGroups = RegExp(r'id: "(\w+)"').allMatches(source)
          .map((m) => m.group(1))
          .toList();
      expect(
        emojiGroups.map((g) => g.id).toList(),
        webGroups,
        reason: 'группы разошлись между клиентами',
      );

      final webItems = RegExp(r'items: \[(.*?)\]', dotAll: true)
          .allMatches(source)
          .expand((m) => RegExp(r'"([^"]+)"').allMatches(m.group(1)!))
          .map((m) => m.group(1))
          .toList();
      final ourItems = [for (final g in emojiGroups) ...g.items];
      expect(
        ourItems,
        webItems,
        reason: 'знаки разошлись между клиентами',
      );
    });
  });
}
