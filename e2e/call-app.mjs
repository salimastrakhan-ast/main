// Звонок между приложением и веб-клиентом.
//
// Сборка Flutter для веба берёт тот же `CallService`, что и APK: разница
// только в реализации WebRTC под платформу. Поэтому проверка гоняет именно
// код приложения, а не его подобие.
//
//   make e2e-call-app   (нужны сервер, веб на 4173 и Flutter web на 8090)
import { chromium } from 'playwright';

const WEB = process.env.WEB ?? 'http://127.0.0.1:4173';
const FLUTTER = process.env.FLUTTER ?? 'http://127.0.0.1:8090';
const API = process.env.API ?? 'http://localhost:8080';
const OUT = process.env.SCRATCH
  ? `${process.env.SCRATCH}/callshots`
  : new URL('shots/callshots', import.meta.url).pathname;

const base = 9008000000 + Math.floor(Math.random() * 900000);
const phone = (n) => `+7${base + n}`;

let failures = 0;
const check = (what, ok, detail = '') => {
  console.log(`${ok ? '  ✓' : '  ✗'} ${what}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures++;
};
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

async function login(p) {
  const code = await (await fetch(`${API}/v1/auth/request-code`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p }),
  })).json();
  return (await fetch(`${API}/v1/auth/verify`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p, code: code.dev_code, platform: 'web', device: 'e2e' }),
  })).json();
}

/// Подменяет выдачу микрофона: звуковых устройств в сборочном контейнере
/// нет. Дорожка настоящая, от осциллятора; всё остальное в звонке идёт как
/// у людей.
const fakeMic = () => {
  const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
  navigator.mediaDevices.getUserMedia = async (constraints) => {
    try {
      return await real(constraints);
    } catch {
      const ctx = new AudioContext();
      const osc = ctx.createOscillator();
      const dest = ctx.createMediaStreamDestination();
      osc.frequency.value = 440;
      osc.connect(dest);
      osc.start();
      return dest.stream;
    }
  };
};

const browser = await chromium.launch({
  headless: false,
  executablePath: process.env.CHROME ?? '/opt/pw-browsers/chromium',
  args: [
    '--use-fake-device-for-media-capture',
    '--use-fake-ui-for-media-stream',
    '--autoplay-policy=no-user-gesture-required',
    '--no-sandbox',
  ],
});

try {
  const [appSession, webSession] = await Promise.all([login(phone(1)), login(phone(2))]);

  // --- Веб-клиент: он будет принимать звонок ---
  const webCtx = await browser.newContext({
    viewport: { width: 1100, height: 760 },
    permissions: ['microphone'],
  });
  const web = await webCtx.newPage();
  await web.addInitScript(() => {
    const Native = window.RTCPeerConnection;
    window.__pcs = [];
    window.RTCPeerConnection = function (...args) {
      const pc = new Native(...args);
      window.__pcs.push(pc);
      return pc;
    };
    window.RTCPeerConnection.prototype = Native.prototype;
  });
  await web.addInitScript(fakeMic);
  await web.goto(WEB);
  await web.evaluate((s) => localStorage.setItem('tito.session', JSON.stringify({
    accessToken: s.access_token,
    refreshToken: s.refresh_token,
    userId: s.user.id,
    expiresAt: Date.now() + (s.expires_in ?? 900) * 1000,
  })), webSession);
  await web.goto(WEB, { waitUntil: 'networkidle' });
  await pause(2500);

  // --- Приложение ---
  const appCtx = await browser.newContext({
    viewport: { width: 420, height: 880 },
    permissions: ['microphone'],
    serviceWorkers: 'block',
  });
  const app = await appCtx.newPage();
  app.on('pageerror', (e) => console.log('  [приложение] ошибка:', String(e).slice(0, 200)));
  await app.addInitScript(fakeMic);
  await app.goto(FLUTTER, { waitUntil: 'load' });
  await app.waitForSelector('flutter-view', { timeout: 60000 });
  await pause(2500);
  await app.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await pause(1500);

  const nodes = async () => {
    let found = await app.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')].map((e) => {
        const r = e.getBoundingClientRect();
        return { text: (e.textContent ?? '').trim(), role: e.getAttribute('role'), x: r.x, y: r.y, w: r.width, h: r.height };
      }).filter((n) => n.text && n.w > 0 && n.h > 0));
    if (found.length === 0) {
      await app.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      await pause(800);
      found = await app.evaluate(() =>
        [...document.querySelectorAll('flt-semantics')].map((e) => {
          const r = e.getBoundingClientRect();
          return { text: (e.textContent ?? '').trim(), role: e.getAttribute('role'), x: r.x, y: r.y, w: r.width, h: r.height };
        }).filter((n) => n.text && n.w > 0 && n.h > 0));
    }
    return found;
  };
  const screenText = async () => (await nodes()).map((n) => n.text).filter((t) => t.length < 60).join(' | ');
  // Flutter держит всплывающую подпись, пока указатель на кнопке, и она
  // становится отдельным узлом с тем же текстом — следующий клик уходит в
  // неё. Поэтому после каждого нажатия уводим мышь к правому краю.
  const unhover = async () => {
    await app.mouse.move(418, 440);
    await pause(350);
  };
  const press = async (label) => {
    for (let i = 0; i < 4; i++) {
      const hit = (await nodes()).filter((n) => n.role === 'button' && n.text === label && n.h >= 16).pop();
      if (hit) {
        await app.mouse.click(hit.x + hit.w / 2, hit.y + hit.h / 2);
        await pause(1000);
        await unhover();
        return true;
      }
      await pause(900);
    }
    console.log(`  промах по кнопке «${label}» — на экране: ${(await screenText()).slice(0, 200)}`);
    return false;
  };
  const tap = async (text) => {
    for (let i = 0; i < 4; i++) {
      const hit = (await nodes())
        .filter((n) => n.text.includes(text) && n.h >= 16 && n.h < 200)
        .sort((a, b) => a.w * a.h - b.w * b.h)[0];
      if (hit) {
        await app.mouse.click(hit.x + hit.w / 2, hit.y + hit.h / 2);
        await pause(1200);
        await unhover();
        return true;
      }
      await pause(900);
    }
    console.log(`  промах по «${text}» — на экране: ${(await screenText()).slice(0, 200)}`);
    return false;
  };

  // Вход в приложение.
  await tap('Начать');
  await pause(1500);
  const field = await app.evaluate(() => {
    const f = document.querySelector('input, textarea');
    if (!f) return null;
    const r = f.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height };
  });
  if (!field) throw new Error('поле номера не найдено');
  await app.mouse.click(field.x + field.w / 2, field.y + field.h / 2);
  await pause(500);

  // Маска подставит +7 сама — набираем только свои десять цифр.
  await app.keyboard.type(phone(1).slice(2), { delay: 30 });
  await pause(800);
  const typed = await app.evaluate(() => document.querySelector('input')?.value ?? '');
  check('маска собрала номер', /^\+7 \(\d{3}\) \d{3}-\d{2}-\d{2}$/.test(typed), typed);
  await press('Получить код');
  await pause(4000);
  await press('Войти');
  await pause(7000);

  // Находим собеседника по номеру и звоним, не написав ни слова.
  await tap('Новый чат');
  await pause(1200);
  const search = await app.evaluate(() => {
    const f = [...document.querySelectorAll('input, textarea')].at(-1);
    if (!f) return null;
    const r = f.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height };
  });
  if (search) {
    await app.mouse.click(search.x + search.w / 2, search.y + search.h / 2);
    await pause(400);
    await app.keyboard.type(phone(2), { delay: 25 });
    await pause(2500);
  }
  await app.screenshot({ path: `${OUT}/03-приложение-поиск.png` });
  const foundPeer = await tap('7900');
  check('человек нашёлся по номеру в приложении', foundPeer);

  const called = await press('Позвонить');
  check('кнопка звонка нашлась в шапке', called);

  await web.waitForSelector('text=Входящий звонок', { timeout: 20000 });
  check('веб-клиент услышал звонок из приложения', true);

  await web.getByRole('button', { name: 'Ответить' }).click();
  await pause(6000);
  await app.screenshot({ path: `${OUT}/04-приложение-разговор.png` });

  const talking = await app.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')].some((e) => /\d+:\d\d/.test(e.textContent ?? '')));
  check('в приложении пошёл счёт разговора', talking, await screenText().then((t) => t.slice(0, 120)));

  const received = await web.evaluate(async () => {
    let bytes = 0;
    for (const pc of window.__pcs ?? []) {
      const stats = await pc.getStats();
      stats.forEach((r) => {
        if (r.type === 'inbound-rtp' && r.kind === 'audio') bytes += r.bytesReceived ?? 0;
      });
    }
    return bytes;
  });
  check('звук из приложения дошёл до веба', received > 0, `${received} байт`);

  await press('Завершить');
  await web.waitForSelector('text=Звонок завершён', { timeout: 10000 });
  check('отбой из приложения слышен в вебе', true);
} finally {
  await browser.close();
}

console.log(failures === 0 ? '\nПриложение звонит.' : `\nНе сошлось: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
