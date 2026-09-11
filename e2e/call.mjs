// Звонок в вебе: два окна, настоящий сервер, настоящий WebRTC.
//
// Проверяется не «кнопка нажалась», а то, ради чего звонок существует:
// у собеседника звонит телефон, после ответа встаёт соединение и по нему
// идёт звук в обе стороны. Последнее видно только по счётчикам RTP —
// соединение умеет встать и молчать.
//
//   make e2e-call     (нужны поднятые сервер и веб, см. e2e/README.md)
import { chromium } from 'playwright';

const WEB = process.env.WEB ?? 'http://127.0.0.1:4173';
const API = process.env.API ?? 'http://localhost:8080';
const OUT = process.env.SCRATCH
  ? `${process.env.SCRATCH}/callshots`
  : new URL('shots/callshots', import.meta.url).pathname;

const base = 9007000000 + Math.floor(Math.random() * 900000);
const phone = (n) => `+7${base + n}`;

let failures = 0;
function check(what, ok, detail = '') {
  console.log(`${ok ? '  ✓' : '  ✗'} ${what}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures++;
}

async function login(p) {
  const code = await (await fetch(`${API}/v1/auth/request-code`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p }),
  })).json();
  const s = await (await fetch(`${API}/v1/auth/verify`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p, code: code.dev_code, platform: 'web', device: 'e2e' }),
  })).json();
  return {
    accessToken: s.access_token,
    refreshToken: s.refresh_token,
    userId: s.user.id,
    expiresAt: Date.now() + (s.expires_in ?? 900) * 1000,
  };
}

async function open(browser, session, who) {
  const context = await browser.newContext({
    viewport: { width: 1100, height: 760 },
    permissions: ['microphone'],
  });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.log(`  [${who}] ошибка:`, String(e).slice(0, 200)));

  await page.addInitScript(() => {
    // Соединения запоминаются, чтобы потом спросить у них статистику:
    // только она доказывает, что по звонку пошёл звук.
    const Native = window.RTCPeerConnection;
    window.__pcs = [];
    window.RTCPeerConnection = function (...args) {
      const pc = new Native(...args);
      window.__pcs.push(pc);
      return pc;
    };
    window.RTCPeerConnection.prototype = Native.prototype;

    // В сборочном контейнере нет ни одного звукового устройства, и
    // подменённое флагами Chromium там тоже не появляется. Подменяем только
    // выдачу устройства — дорожка настоящая, собранная осциллятором. Всё
    // остальное в звонке идёт как у людей.
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
  });

  await page.goto(WEB);
  await page.evaluate((s) => localStorage.setItem('tito.session', JSON.stringify(s)), session);
  await page.goto(WEB, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2500);
  return { page, context };
}

/// Сколько байт звука ушло и пришло. Ноль принятых означает, что канал
/// встал, но молчит, — и это не работающий звонок.
const traffic = (app) =>
  app.page.evaluate(async () => {
    const out = { sent: 0, received: 0 };
    for (const pc of window.__pcs ?? []) {
      const stats = await pc.getStats();
      stats.forEach((r) => {
        if (r.type === 'outbound-rtp' && r.kind === 'audio') out.sent += r.bytesSent ?? 0;
        if (r.type === 'inbound-rtp' && r.kind === 'audio') out.received += r.bytesReceived ?? 0;
      });
    }
    return out;
  });

const browser = await chromium.launch({
  // С экраном, а не headless: в старом headless getUserMedia отказывает
  // даже с подменённым устройством. Запускать через xvfb-run.
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
  const [anyaSession, boryaSession] = await Promise.all([login(phone(1)), login(phone(2))]);
  const anya = await open(browser, anyaSession, 'Аня');
  const borya = await open(browser, boryaSession, 'Боря');

  // Аня находит Борю по номеру — переписки с ним ещё нет.
  await anya.page.locator('button[aria-label="Новое сообщение"]:visible').first().click();
  await anya.page.waitForTimeout(900);
  await anya.page.locator('input[placeholder*="Найти"]').first().fill(phone(2));
  await anya.page.waitForTimeout(2000);
  check('человек нашёлся по номеру', (await anya.page.locator('ul li button').count()) > 0);
  await anya.page.locator('ul li button').first().click();
  await anya.page.waitForTimeout(1200);
  check('найденного можно выбрать и открыть переписку',
    (await anya.page.locator('textarea').count()) > 0);

  // Звоним, не написав ни слова: чат заведёт сервер.
  await anya.page.locator('button[aria-label="Позвонить"]').first().click();
  await borya.page.waitForSelector('text=Входящий звонок', { timeout: 15000 });
  check('у собеседника зазвонило', true);
  await borya.page.screenshot({ path: `${OUT}/01-входящий.png` });

  await borya.page.getByRole('button', { name: 'Ответить' }).click();
  const talking = (app) =>
    app.page.waitForFunction(() => /\d+:\d\d/.test(document.body.innerText), null, { timeout: 20000 });
  await Promise.all([talking(anya), talking(borya)]);
  check('соединение встало у обоих', true);
  await anya.page.screenshot({ path: `${OUT}/02-разговор.png` });

  await anya.page.waitForTimeout(3000);
  const [a, b] = await Promise.all([traffic(anya), traffic(borya)]);
  check('звук идёт от Ани к Боре', b.received > 0, `${b.received} байт`);
  check('звук идёт от Бори к Ане', a.received > 0, `${a.received} байт`);

  await anya.page.locator('button[aria-label="Завершить"]').first().click();
  await borya.page.waitForSelector('text=Звонок завершён', { timeout: 10000 });
  check('отбой слышен на той стороне', true);
} finally {
  await browser.close();
}

console.log(failures === 0 ? '\nЗвонок работает.' : `\nНе сошлось: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
