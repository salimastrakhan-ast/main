import 'package:flutter_test/flutter_test.dart';
import 'package:mayak/ui/icons.dart';

void main() {
  group('Набор иконок', () {
    test('все из одного семейства', () {
      // Смешивать семейства нельзя: у иконок рядом разошёлся бы вес штриха,
      // и набор перестал бы выглядеть набором.
      for (final icon in MayakIcons.all) {
        expect(icon.fontFamily, 'Lucide',
            reason: 'иконка ${icon.codePoint} не из набора');
      }
    });

    test('шрифт свой, а не из пакета', () {
      // fontPackage непустой означал бы, что иконка тянется из зависимости.
      // Пакет Lucide кладёт в сборку шесть неиспользуемых начертаний на
      // 2.7 МБ, поэтому шрифт держим у себя.
      for (final icon in MayakIcons.all) {
        expect(icon.fontPackage, isNull,
            reason: 'иконка ${icon.codePoint} ссылается на пакет');
      }
    });

    test('ни одна иконка не повторяется', () {
      final codes = MayakIcons.all.map((i) => i.codePoint).toList();
      expect(codes.toSet().length, codes.length,
          reason: 'две роли указывают на одну картинку');
    });

    test('набор не пуст и покрывает все роли', () {
      expect(MayakIcons.all, hasLength(46));
    });
  });
}
