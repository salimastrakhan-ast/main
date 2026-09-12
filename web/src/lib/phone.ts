/// Ввод и показ телефонного номера.
///
/// Повторяет `app/lib/core/phone.dart` — те же правила, те же примеры в
/// тестах. Номер человек вводит на каждом устройстве и помнит, как это
/// выглядело: расхождение между клиентами здесь заметно сразу.
///
/// Страна одна — Россия. Это не упрощение «на потом»: мессенджер для России,
/// и номер без кода страны здесь означает российский. Чужие номера всё равно
/// принимаются, но без группировки — см. `formatPhone`.

/// Длина национальной части российского номера: 9XX XXX-XX-XX.
const RU_NATIONAL = 10;

/// Сервер принимает от 7 до 15 цифр (`auth.NormalizePhone`). Больше 15 не
/// бывает ни у одной страны — это предел плана нумерации E.164.
const MAX_DIGITS = 15;

/// Только цифры. Всё остальное — оформление, и его в номере нет.
export function phoneDigits(text: string): string {
  return text.replace(/\D/g, "");
}

/// Российский ли номер набирают.
///
/// Явный `+` с чужим кодом страны — единственный способ сказать «не мой
/// случай». Всё остальное считается российским: человек, набирающий `9` в
/// приложении для России, набирает своё `+7 9…`.
function isForeign(text: string): boolean {
  if (!text.trimStart().startsWith("+")) return false;
  const digits = phoneDigits(text);
  return digits.length > 0 && !digits.startsWith("7");
}

/// Национальная часть: то, что останется после кода страны.
///
/// Ведущая `8` — междугородный префикс из телефонной эпохи, `7` — код
/// страны; и то и другое человек набирает вместо `+7`. Ведущая `9` — уже сам
/// номер, её надо сохранить.
function ruNational(digits: string): string {
  const rest = /^[78]/.test(digits) ? digits.slice(1) : digits;
  return rest.slice(0, RU_NATIONAL);
}

/// Номер в том виде, в каком он показывается человеку.
///
/// Разделители дописываются по мере набора, поэтому на полпути получается
/// `+7 (939) 273-11`, а не заготовка с прочерками: пустые места впереди
/// курсора читаются как «тут ошибка», хотя человек просто ещё не дописал.
export function formatPhone(text: string): string {
  if (isForeign(text)) return "+" + phoneDigits(text).slice(0, MAX_DIGITS);

  const rest = ruNational(phoneDigits(text));
  if (rest.length === 0) return "+7";

  let out = "+7 (" + rest.slice(0, 3);
  if (rest.length <= 3) return out;
  out += ") " + rest.slice(3, 6);
  if (rest.length <= 6) return out;
  out += "-" + rest.slice(6, 8);
  if (rest.length <= 8) return out;
  return out + "-" + rest.slice(8);
}

/// Набрано ли достаточно, чтобы просить код.
///
/// Для России это ровно одиннадцать цифр с кодом страны — короче номера не
/// бывает, длиннее маска не пустит. Для чужого номера нижняя граница та же,
/// что у сервера: семь цифр.
export function phoneIsComplete(text: string): boolean {
  const digits = phoneDigits(text);
  if (isForeign(text)) return digits.length >= 7;
  return ruNational(digits).length === RU_NATIONAL;
}

/// Приводит номер к виду для отправки на сервер.
///
/// Сервер и сам это делает (`auth.NormalizePhone`), но клиент шлёт нормальный
/// `+7…` не ради сервера: этот же номер уходит в поиск людей, и там `8939…`
/// и `+7939…` должны находить одного человека.
export function phoneForServer(text: string): string {
  const digits = phoneDigits(text);
  if (isForeign(text)) return "+" + digits;
  const rest = ruNational(digits);
  return rest.length === 0 ? "" : "+7" + rest;
}

/// Результат набора: что показать и где оставить курсор.
export type PhoneEdit = { text: string; caret: number };

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
/// несработавшим. В этом случае снимается ещё и цифра перед разделителем.
export function editPhone(
  previous: string,
  next: string,
  caret: number,
): PhoneEdit {
  let text = next;
  let at = Math.max(0, Math.min(caret, text.length));

  if (next.length < previous.length) {
    const removed = previous.slice(at, at + (previous.length - next.length));
    if (phoneDigits(removed).length === 0) {
      const head = text.slice(0, at);
      const lastDigit = head.search(/\d(?=\D*$)/);
      if (lastDigit >= 0) {
        text = head.slice(0, lastDigit) + text.slice(at);
        at = lastDigit;
      }
    }
  }

  const formatted = formatPhone(text);
  return { text: formatted, caret: caretFor(text, at, formatted) };
}

/// Куда поставить курсор в отформатированной строке.
///
/// Считаются не все цифры подряд: `+7` в начале — тоже цифра, но человек её
/// не набирал и правит не её. Поэтому счёт идёт по цифрам национальной
/// части, а код страны пропускается с обеих сторон.
function caretFor(raw: string, caret: number, formatted: string): number {
  const before = phoneDigits(raw.slice(0, caret)).length;

  if (formatted.charAt(1) !== "7") {
    // Чужой номер: `+` и цифры подряд, считать нечего.
    return Math.min(before + 1, formatted.length);
  }

  const hasCountry = /^[78]/.test(phoneDigits(raw));
  const national = hasCountry ? Math.max(0, before - 1) : before;
  if (national === 0) return 2; // Сразу за `+7`: левее курсору делать нечего.

  let seen = 0;
  for (let i = 2; i < formatted.length; i++) {
    const ch = formatted.charAt(i);
    if (ch >= "0" && ch <= "9") {
      seen++;
      if (seen === national) return i + 1;
    }
  }
  return formatted.length;
}
