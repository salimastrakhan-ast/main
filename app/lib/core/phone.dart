import 'package:flutter/services.dart';

/// Ввод и показ телефонного номера.
///
/// Одно правило на оба клиента: те же функции повторены в
/// `web/src/lib/phone.ts`. Расхождение здесь человек замечает сразу — номер
/// он вводит на каждом устройстве и помнит, как это выглядело.
///
/// Страна одна — Россия. Это не упрощение «на потом»: мессенджер для России,
/// и номер без кода страны здесь означает российский. Чужие номера всё равно
/// принимаются, но без группировки — см. [formatPhone].

/// Длина национальной части российского номера: 9XX XXX-XX-XX.
const _ruNationalLength = 10;

/// Сервер принимает от 7 до 15 цифр (`auth.NormalizePhone`). Больше 15 не
/// бывает ни у одной страны — это предел плана нумерации E.164.
const _maxDigits = 15;

/// Только цифры. Всё остальное — оформление, и его в номере нет.
String phoneDigits(String text) => text.replaceAll(RegExp(r'\D'), '');

/// Российский ли номер набирают.
///
/// Явный `+` с чужим кодом страны — единственный способ сказать «не мой
/// случай». Всё остальное считается российским: человек, набирающий `9` в
/// приложении для России, набирает своё `+7 9…`, а не гвинейский номер.
bool _isForeign(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('+')) return false;
  final digits = phoneDigits(trimmed);
  return digits.isNotEmpty && !digits.startsWith('7');
}

/// Национальная часть: то, что останется после кода страны.
///
/// Ведущая `8` — междугородный префикс из телефонной эпохи, `7` — код
/// страны; и то и другое человек набирает вместо `+7`, и в обоих случаях
/// имеет в виду одно. Ведущая `9` — уже сам номер, её надо сохранить.
String _ruNational(String digits) {
  var rest = digits;
  if (rest.startsWith('8') || rest.startsWith('7')) {
    rest = rest.substring(1);
  }
  if (rest.length > _ruNationalLength) {
    rest = rest.substring(0, _ruNationalLength);
  }
  return rest;
}

/// Номер в том виде, в каком он показывается человеку.
///
/// `+7 (939) 273-11-11` — разделители дописываются по мере набора, поэтому
/// на полпути получается `+7 (939) 273-11`, а не заготовка с прочерками:
/// пустые места впереди курсора читаются как «тут ошибка», хотя человек
/// просто ещё не дописал.
String formatPhone(String text) {
  if (_isForeign(text)) {
    final digits = phoneDigits(text);
    return '+${digits.length > _maxDigits ? digits.substring(0, _maxDigits) : digits}';
  }

  final rest = _ruNational(phoneDigits(text));
  final out = StringBuffer('+7');
  if (rest.isEmpty) return out.toString();

  out.write(' (');
  out.write(rest.substring(0, rest.length.clamp(0, 3)));
  if (rest.length <= 3) return out.toString();

  out.write(') ');
  out.write(rest.substring(3, rest.length.clamp(0, 6)));
  if (rest.length <= 6) return out.toString();

  out.write('-');
  out.write(rest.substring(6, rest.length.clamp(0, 8)));
  if (rest.length <= 8) return out.toString();

  out.write('-');
  out.write(rest.substring(8));
  return out.toString();
}

/// Набрано ли достаточно, чтобы просить код.
///
/// Для России это ровно одиннадцать цифр с кодом страны — короче номера не
/// бывает, длиннее маска не пустит. Для чужого номера нижняя граница та же,
/// что у сервера: семь цифр.
bool phoneIsComplete(String text) {
  final digits = phoneDigits(text);
  if (_isForeign(text)) return digits.length >= 7;
  return _ruNational(digits).length == _ruNationalLength;
}

/// Приводит номер к виду для отправки на сервер.
///
/// Сервер и сам это делает (`auth.NormalizePhone`), но клиент шлёт нормальный
/// `+7…` не ради сервера: этот же номер уходит в поиск людей, и там `8939…`
/// и `+7939…` должны находить одного человека.
String phoneForServer(String text) {
  final digits = phoneDigits(text);
  if (_isForeign(text)) return '+$digits';
  final rest = _ruNational(digits);
  return rest.isEmpty ? '' : '+7$rest';
}

/// Форматирование прямо во время набора.
///
/// Две вещи, без которых маска мешает больше, чем помогает.
///
/// Курсор: после подстановки скобок строка удлиняется, и наивная реализация
/// отправляет курсор в конец — исправить опечатку в середине становится
/// нельзя. Поэтому считается число цифр до курсора, и он ставится после
/// такой же по счёту цифры в новой строке.
///
/// Backspace по разделителю: если удаление сняло только `)` или `-`,
/// форматирование вернёт их на место, и нажатие будет выглядеть
/// несработавшим. В этом случае снимается ещё и цифра перед разделителем —
/// то, что человек и хотел удалить.
class RuPhoneFormatter extends TextInputFormatter {
  const RuPhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    var caret = newValue.selection.end;

    final deleting = newValue.text.length < oldValue.text.length;
    if (deleting && caret >= 0 && caret <= text.length) {
      final removed = oldValue.text.substring(
        caret,
        caret + (oldValue.text.length - text.length),
      );
      if (phoneDigits(removed).isEmpty) {
        // Удалён только разделитель. Снимаем цифру левее — иначе маска
        // вернёт разделитель, и нажатие пропадёт впустую.
        final head = text.substring(0, caret);
        final lastDigit = head.lastIndexOf(RegExp(r'\d'));
        if (lastDigit >= 0) {
          text = head.substring(0, lastDigit) + text.substring(caret);
          caret = lastDigit;
        }
      }
    }

    final formatted = formatPhone(text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _caretFor(text, caret.clamp(0, text.length), formatted),
      ),
      // Пустая область композиции: иначе часть клавиатур Android считает,
      // что слово ещё набирается, и подставляет свой вариант поверх нашего.
      composing: TextRange.empty,
    );
  }

  /// Куда поставить курсор в отформатированной строке.
  ///
  /// Считаются не все цифры подряд: `+7` в начале — тоже цифра, но человек
  /// её не набирал и правит не её. Поэтому счёт идёт по цифрам
  /// национальной части, а код страны пропускается с обеих сторон.
  static int _caretFor(String raw, int caret, String formatted) {
    final before = phoneDigits(raw.substring(0, caret)).length;

    if (formatted.length < 2 || formatted[1] != '7') {
      // Чужой номер: `+` и цифры подряд, считать нечего.
      return (before + 1).clamp(0, formatted.length);
    }

    final all = phoneDigits(raw);
    final hasCountry = all.startsWith('7') || all.startsWith('8');
    final national = hasCountry ? (before - 1).clamp(0, before) : before;
    if (national <= 0) return 2; // Сразу после `+7`, левее курсору нечего делать.

    var seen = 0;
    for (var i = 2; i < formatted.length; i++) {
      if (_digit.hasMatch(formatted[i])) {
        seen++;
        if (seen == national) return i + 1;
      }
    }
    return formatted.length;
  }

  static final _digit = RegExp(r'\d');
}
