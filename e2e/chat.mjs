import { chromium } from 'playwright';

const WEB = 'http://localhost:8090';
const API = 'http://localhost:8080';
const OUT = process.env.SCRATCH + '/e2e';

// Жёсткий предохранитель: зависший шаг не должен держать прогон вечно.
const watchdog = setTimeout(() => {
  console.log('Прогон не уложился в 4 минуты');
  process.exit(2);
}, 240000);
watchdog.unref?.();

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok });
  console.log(`${ok ? '  OK  ' : ' FAIL '} ${name}${detail ? ' — ' + detail : ''}`);
}

// --- Работа с приложением ---
//
// Flutter рисует в канвас, поэтому обычных кнопок в DOM нет. Включённое
// дерево доступности даёт узлы flt-semantics с текстом — по нему и работаем.

async function open(browser, label) {
  const context = await browser.newContext({
    viewport: { width: 430, height: 900 },
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.log(`[${label}]`, String(e).slice(0, 200)));
  await page.goto(WEB, { waitUntil: 'load' });
  await page.waitForSelector('flutter-view', { timeout: 40000 });
  await page.waitForTimeout(1500);
  // Кнопка включения 1x1 за краем экрана — обычный клик по ней не проходит.
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1200);
  return { page, context, label };
}

/// Весь текст, который сейчас на экране, — из дерева доступности.
const screenText = async (app) =>
  (await app.page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.textContent?.trim())
      .filter(Boolean))).join(' | ');

async function tap(app, text) {
  const ok = await app.page.evaluate((needle) => {
    const nodes = [...document.querySelectorAll('flt-semantics')]
      .filter((e) => e.textContent?.trim().includes(needle));
    // Самый глубокий узел с этим текстом и есть сам элемент, а не контейнер.
    const target = nodes[nodes.length - 1];
    if (!target) return false;
    target.click();
    return true;
  }, text);
  await app.page.waitForTimeout(600);
  return ok;
}

/// Печатает в поле, которое сейчас в фокусе.
///
/// Именно клавиатурой: Flutter слушает события ввода, а подменённое напрямую
/// значение input он не заметит.
async function typeInto(app, value) {
  await app.page.keyboard.type(value, { delay: 25 });
  await app.page.waitForTimeout(700);
}

/// Тап по координатам. Нужен там, где узел доступности не ловит клик, —
/// например по полю ввода сообщения.
async function tapAt(app, x, y) {
  await app.page.mouse.click(x, y);
  await app.page.waitForTimeout(600);
}

async function login(app, phone) {
  await typeInto(app, phone);
  await tap(app, 'Получить код');
  await app.page.waitForTimeout(3000);
  // В разработке код уже подставлен в поле — остаётся подтвердить.
  await tap(app, 'Войти');
  await app.page.waitForTimeout(4000);
}

// --- Второй участник: клиент протокола на голом WebSocket ---

async function apiLogin(phone) {
  const code = await (await fetch(`${API}/v1/auth/request-code`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone }),
  })).json();
  return (await fetch(`${API}/v1/auth/verify`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone, code: code.dev_code, platform: 'e2e', device: 'node' }),
  })).json();
}

async function connect(session) {
  const sock = new WebSocket('ws://localhost:8080/v1/ws');
  await new Promise((res) => sock.addEventListener('open', res));
  sock.send(JSON.stringify({ v: 1, t: 'auth', d: { token: session.access_token } }));
  await new Promise((res) => sock.addEventListener('message', res, { once: true }));
  return sock;
}

const browser = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  args: ['--no-sandbox'],
});

// --- Аня входит через приложение ---
const anya = await open(browser, 'Аня');
check('экран входа отрисован', (await screenText(anya)).includes('Введите номер телефона'));
await anya.page.screenshot({ path: `${OUT}/01-вход.png` });

await login(anya, '+79005550001');
await anya.page.screenshot({ path: `${OUT}/02-список-чатов.png` });

const afterLogin = await screenText(anya);
check('после входа открылся список диалогов',
  afterLogin.includes('Профиль'), afterLogin.slice(0, 120));

// --- Боря пишет Ане ---
const borya = await apiLogin('+79005550002');
const sock = await connect(borya);

const found = await (await fetch(`${API}/v1/contacts/sync`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${borya.access_token}`,
  },
  body: JSON.stringify({ contacts: [{ phone: '+79005550001', name: 'Аня' }] }),
})).json();

const anyaId = found.users?.[0]?.id;
check('Боря нашёл Аню по номеру телефона', Boolean(anyaId));

sock.send(JSON.stringify({
  v: 1, t: 'message.send', id: 'e2e-1',
  d: { peer_id: anyaId, text: 'Привет!', client_msg_id: crypto.randomUUID() },
}));
await new Promise((r) => setTimeout(r, 3000));

await anya.page.screenshot({ path: `${OUT}/03-пришло-сообщение.png` });
const withChat = await screenText(anya);
// В строке списка видно начало последнего сообщения — по нему и проверяем,
// и по нему же открываем чат.
check('чат появился у Ани сам, без перезагрузки',
  withChat.includes('Привет!'), withChat.slice(0, 140));

// --- Аня открывает чат и отвечает ---
await tap(anya, 'Привет!');
await anya.page.waitForTimeout(2500);
await anya.page.screenshot({ path: `${OUT}/04-переписка.png` });

const inChat = await screenText(anya);
check('входящее сообщение видно в переписке',
  inChat.includes('Привет!'), inChat.slice(0, 140));

const reply = new Promise((res) => {
  sock.addEventListener('message', (e) => {
    const env = JSON.parse(e.data);
    if (env.t === 'message.new') res(env.d.message.text);
  });
});

// Поле ввода и кнопка отправки — внизу экрана.
await tapAt(anya, 187, 865);
await typeInto(anya, 'И тебе привет');
await tapAt(anya, 394, 866);
await anya.page.waitForTimeout(2500);
await anya.page.screenshot({ path: `${OUT}/05-ответ.png` });

const answer = await Promise.race([
  reply,
  new Promise((r) => setTimeout(() => r(null), 8000)),
]);
check('ответ из приложения дошёл до собеседника',
  answer === 'И тебе привет', answer ?? 'не пришло');

const sent = await screenText(anya);
check('свой ответ виден в ленте', sent.includes('И тебе привет'), sent.slice(0, 140));

clearTimeout(watchdog);
sock.close();
await browser.close();

const failed = results.filter((r) => !r.ok);
console.log(`\nИтог: ${results.length - failed.length}/${results.length}`);
process.exit(failed.length ? 1 : 0);
