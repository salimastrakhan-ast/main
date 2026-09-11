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
  // Отказ сервера иначе выглядит как «приложение не отвечает»: экран не
  // меняется, и полдня уходит на поиск несуществующей ошибки в вёрстке.
  page.on('response', (r) => {
    if (r.url().includes('/v1/') && r.status() >= 400) {
      console.log(`[${label}] сервер ответил ${r.status()} на ${new URL(r.url()).pathname}`);
    }
  });
  page.on('requestfailed', (r) => {
    if (r.url().includes('/v1/')) {
      console.log(`[${label}] запрос не прошёл: ${new URL(r.url()).pathname} — ${r.failure()?.errorText}`);
    }
  });
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

/// Нажимает кнопку настоящим указателем по её месту в дереве доступности.
///
/// Берётся самый маленький узел с нужным текстом. Просто «последний
/// подходящий» не годится: дерево вложенное, и текст кнопки есть и у
/// контейнера всего экрана — клик по его середине попадал в соседний
/// элемент, а однажды увёл назад с экрана кода на экран номера.
async function pressButton(app, label) {
  const nodes = app.page.locator('flt-semantics', { hasText: label });
  const count = await nodes.count();

  let target = null;
  for (let i = 0; i < count; i++) {
    const box = await nodes.nth(i).boundingBox();
    if (!box || box.width === 0 || box.height === 0) continue;
    if (!target || box.width * box.height < target.width * target.height) {
      target = box;
    }
  }
  if (!target) throw new Error(`не нашёл кнопку «${label}»`);

  await app.page.mouse.click(target.x + target.width / 2, target.y + target.height / 2);
  await app.page.waitForTimeout(600);
}

async function login(app, phone) {
  // Приветствие показывается один раз при первом запуске, а контекст
  // браузера здесь каждый раз новый — значит, оно будет всегда.
  await tap(app, 'Начать');
  await app.page.waitForTimeout(1500);
  check('экран входа отрисован', (await screenText(app)).includes('Введите номер телефона'));

  // Клик по полю: на автофокус сразу после перехода полагаться нельзя, он
  // приходит кадром позже, и набор уходит в пустоту.
  await tapAt(app, 215, 507);
  await typeInto(app, phone);
  await pressButton(app, 'Получить код');
  await app.page.waitForTimeout(4000);
  // В разработке код уже подставлен в поле — остаётся подтвердить.
  await pressButton(app, 'Войти');
  await app.page.waitForTimeout(4500);
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

// Номера на каждый прогон свои: у сервера между кодами на один номер стоит
// пауза в несколько минут, и на постоянных номерах второй прогон подряд
// упирался бы в неё, а выглядело бы это как поломка приложения.
const base = 9005000000 + Math.floor(Math.random() * 900000);
const ANYA = `+7${base}`;
const BORYA = `+7${base + 1}`;

const browser = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  args: ['--no-sandbox'],
});

// --- Аня входит через приложение ---
const anya = await open(browser, 'Аня');
check('приветствие отрисовано', (await screenText(anya)).includes('без границ'));
await anya.page.screenshot({ path: `${OUT}/01-вход.png` });

await login(anya, ANYA);
await anya.page.screenshot({ path: `${OUT}/02-список-чатов.png` });

const afterLogin = await screenText(anya);
check('после входа открылся список диалогов',
  afterLogin.includes('Профиль'), afterLogin.slice(0, 120));

// --- Боря пишет Ане ---
const borya = await apiLogin(BORYA);
const sock = await connect(borya);

const found = await (await fetch(`${API}/v1/contacts/sync`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${borya.access_token}`,
  },
  body: JSON.stringify({ contacts: [{ phone: ANYA, name: 'Аня' }] }),
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
