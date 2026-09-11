import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tito/core/phone.dart';

/// Набирает номер по одной цифре, как это делает человек, и возвращает то,
/// что видно в поле. Проверять форматирование целой строкой недостаточно:
/// маска ломается именно посередине набора.
TextEditingValue _type(String keys) {
  const formatter = RuPhoneFormatter();
  // Не TextEditingValue.empty: у него курсора нет вовсе (offset -1), а
  // человек всегда печатает куда-то.
  var value = const TextEditingValue(
    selection: TextSelection.collapsed(offset: 0),
  );
  for (final key in keys.split('')) {
    final next = TextEditingValue(
      text: value.text.substring(0, value.selection.end) +
          key +
          value.text.substring(value.selection.end),
      selection: TextSelection.collapsed(offset: value.selection.end + 1),
    );
    value = formatter.formatEditUpdate(value, next);
  }
  return value;
}

/// Backspace в текущей позиции курсора.
TextEditingValue _backspace(TextEditingValue value) {
  const formatter = RuPhoneFormatter();
  final at = value.selection.end;
  if (at == 0) return value;
  return formatter.formatEditUpdate(
    value,
    TextEditingValue(
      text: value.text.substring(0, at - 1) + value.text.substring(at),
      selection: TextSelection.collapsed(offset: at - 1),
    ),
  );
}

void main() {
  group('Показ номера', () {
    test('девятка своя, код страны подставляется', () {
      expect(formatPhone('9'), '+7 (9');
      expect(formatPhone('939'), '+7 (939');
      expect(formatPhone('9392731111'), '+7 (939) 273-11-11');
    });

    test('восьмёрка и семёрка — это код страны, а не номер', () {
      expect(formatPhone('8'), '+7');
      expect(formatPhone('7'), '+7');
      expect(formatPhone('89392731111'), '+7 (939) 273-11-11');
      expect(formatPhone('79392731111'), '+7 (939) 273-11-11');
    });

    test('вставка из буфера в любом виде даёт один и тот же номер', () {
      const expected = '+7 (939) 273-11-11';
      expect(formatPhone('+7 939 273 11 11'), expected);
      expect(formatPhone('8 (939) 273-11-11'), expected);
      expect(formatPhone('+7(939)2731111'), expected);
    });

    test('лишние цифры не влезают', () {
      expect(formatPhone('939273111199999'), '+7 (939) 273-11-11');
    });

    test('чужой номер не ломается о российскую разметку', () {
      expect(formatPhone('+380501234567'), '+380501234567');
      expect(formatPhone('+1 202 555 0147'), '+12025550147');
    });

    test('готовность номера', () {
      expect(phoneIsComplete('+7 (939) 273-11-1'), isFalse);
      expect(phoneIsComplete('+7 (939) 273-11-11'), isTrue);
      expect(phoneIsComplete('89392731111'), isTrue);
      expect(phoneIsComplete('+380501234567'), isTrue);
      expect(phoneIsComplete('+38050'), isFalse);
    });

    test('для сервера номер уходит в одном виде', () {
      expect(phoneForServer('9392731111'), '+79392731111');
      expect(phoneForServer('8 (939) 273-11-11'), '+79392731111');
      expect(phoneForServer('+380501234567'), '+380501234567');
      expect(phoneForServer(''), '');
    });
  });

  group('Набор вживую', () {
    test('после первой девятки курсор стоит за ней, а не за кодом', () {
      final value = _type('9');
      expect(value.text, '+7 (9');
      expect(value.selection.end, 5);
    });

    test('восьмёрка исчезает, курсор ждёт номер', () {
      final value = _type('8');
      expect(value.text, '+7');
      expect(value.selection.end, 2);
    });

    test('весь номер по цифре — курсор в конце', () {
      final value = _type('89392731111');
      expect(value.text, '+7 (939) 273-11-11');
      expect(value.selection.end, value.text.length);
    });

    test('backspace через разделитель убирает цифру, а не только скобку', () {
      // `+7 (939) ` — курсор за пробелом, слева от него только разметка.
      var value = _type('9392');
      value = _backspace(value); // Снимаем `2`.
      expect(value.text, '+7 (939');
      value = _backspace(value); // Слева `)` и пробел — должна уйти `9`.
      expect(value.text, '+7 (93');
      expect(value.selection.end, value.text.length);
    });

    test('правка середины не выбрасывает курсор в конец', () {
      const formatter = RuPhoneFormatter();
      final full = _type('9392731111');
      expect(full.text, '+7 (939) 273-11-11');

      // Ставим курсор после `273` и дописываем цифру: человек ошибся в
      // середине и правит её, не стирая всё до конца.
      const at = 12;
      final edited = formatter.formatEditUpdate(
        full.copyWith(selection: const TextSelection.collapsed(offset: at)),
        TextEditingValue(
          text: '${full.text.substring(0, at)}5${full.text.substring(at)}',
          selection: const TextSelection.collapsed(offset: at + 1),
        ),
      );

      expect(edited.text, '+7 (939) 273-51-11');
      // 14 — сразу за вставленной пятёркой, а не перед ней: человек
      // продолжает набор с того места, где правил.
      expect(edited.selection.end, 14);
    });
  });
}
