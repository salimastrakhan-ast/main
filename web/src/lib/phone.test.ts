import { describe, expect, it } from "vitest";
import {
  editPhone,
  formatPhone,
  phoneForServer,
  phoneIsComplete,
} from "./phone";

/// Набирает номер по одной цифре, как это делает человек, и возвращает то,
/// что видно в поле. Проверять форматирование целой строкой недостаточно:
/// маска ломается именно посередине набора.
function type(keys: string) {
  let text = "";
  let caret = 0;
  for (const key of keys) {
    const next = text.slice(0, caret) + key + text.slice(caret);
    const edit = editPhone(text, next, caret + 1);
    text = edit.text;
    caret = edit.caret;
  }
  return { text, caret };
}

function backspace(state: { text: string; caret: number }) {
  if (state.caret === 0) return state;
  const next =
    state.text.slice(0, state.caret - 1) + state.text.slice(state.caret);
  return editPhone(state.text, next, state.caret - 1);
}

describe("показ номера", () => {
  it("девятка своя, код страны подставляется", () => {
    expect(formatPhone("9")).toBe("+7 (9");
    expect(formatPhone("939")).toBe("+7 (939");
    expect(formatPhone("9392731111")).toBe("+7 (939) 273-11-11");
  });

  it("восьмёрка и семёрка — это код страны, а не номер", () => {
    expect(formatPhone("8")).toBe("+7");
    expect(formatPhone("7")).toBe("+7");
    expect(formatPhone("89392731111")).toBe("+7 (939) 273-11-11");
    expect(formatPhone("79392731111")).toBe("+7 (939) 273-11-11");
  });

  it("вставка из буфера в любом виде даёт один и тот же номер", () => {
    const expected = "+7 (939) 273-11-11";
    expect(formatPhone("+7 939 273 11 11")).toBe(expected);
    expect(formatPhone("8 (939) 273-11-11")).toBe(expected);
    expect(formatPhone("+7(939)2731111")).toBe(expected);
  });

  it("лишние цифры не влезают", () => {
    expect(formatPhone("939273111199999")).toBe("+7 (939) 273-11-11");
  });

  it("чужой номер не ломается о российскую разметку", () => {
    expect(formatPhone("+380501234567")).toBe("+380501234567");
    expect(formatPhone("+1 202 555 0147")).toBe("+12025550147");
  });

  it("готовность номера", () => {
    expect(phoneIsComplete("+7 (939) 273-11-1")).toBe(false);
    expect(phoneIsComplete("+7 (939) 273-11-11")).toBe(true);
    expect(phoneIsComplete("89392731111")).toBe(true);
    expect(phoneIsComplete("+380501234567")).toBe(true);
    expect(phoneIsComplete("+38050")).toBe(false);
  });

  it("для сервера номер уходит в одном виде", () => {
    expect(phoneForServer("9392731111")).toBe("+79392731111");
    expect(phoneForServer("8 (939) 273-11-11")).toBe("+79392731111");
    expect(phoneForServer("+380501234567")).toBe("+380501234567");
    expect(phoneForServer("")).toBe("");
  });
});

describe("набор вживую", () => {
  it("после первой девятки курсор стоит за ней, а не за кодом", () => {
    expect(type("9")).toEqual({ text: "+7 (9", caret: 5 });
  });

  it("восьмёрка исчезает, курсор ждёт номер", () => {
    expect(type("8")).toEqual({ text: "+7", caret: 2 });
  });

  it("весь номер по цифре — курсор в конце", () => {
    const state = type("89392731111");
    expect(state.text).toBe("+7 (939) 273-11-11");
    expect(state.caret).toBe(state.text.length);
  });

  it("backspace через разделитель убирает цифру, а не только скобку", () => {
    let state = type("9392");
    state = backspace(state); // Снимаем `2`.
    expect(state.text).toBe("+7 (939");
    state = backspace(state); // Слева `)` и пробел — должна уйти `9`.
    expect(state.text).toBe("+7 (93");
    expect(state.caret).toBe(state.text.length);
  });

  it("правка середины не выбрасывает курсор в конец", () => {
    const full = type("9392731111");
    expect(full.text).toBe("+7 (939) 273-11-11");

    // Курсор после `273`: человек ошибся в середине и правит её, не стирая
    // всё до конца.
    const at = 12;
    const edited = editPhone(
      full.text,
      full.text.slice(0, at) + "5" + full.text.slice(at),
      at + 1,
    );
    expect(edited.text).toBe("+7 (939) 273-51-11");
    // 14 — сразу за вставленной пятёркой, а не перед ней.
    expect(edited.caret).toBe(14);
  });
});
