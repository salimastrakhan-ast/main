import { chromium } from 'playwright';

const WEB = 'http://127.0.0.1:4173';
const API = 'http://localhost:8080';
// Папка для кадров: рядом со скриптом, если снаружи ничего не задано.
// Без этого при пустом SCRATCH путь склеивался в «undefined/…», и кадры
// оседали мусорной папкой в репозитории.
const OUT = process.env.SCRATCH
  ? process.env.SCRATCH + '/webshots'
  : new URL('shots/webshots', import.meta.url).pathname;

const base = 9005000000 + Math.floor(Math.random() * 900000);
const phone = (n) => `+7${base + n}`;

async function open(browser) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 820 } });
  const page = await context.newPage();
  page.on('console', (m) => m.type() === 'error' && console.log('  консоль:', m.text().slice(0, 160)));
  page.on('pageerror', (e) => console.log('  ошибка страницы:', String(e).slice(0, 160)));
  await page.goto(WEB, { waitUntil: 'networkidle' });
  return { page, context };
}

async function signIn(app, number) {
  await app.page.fill('input[aria-label="Номер телефона"]', number);
  await app.page.getByRole('button', { name: 'Получить код' }).click();
  await app.page.waitForSelector('input[aria-label="Код из SMS"]', { timeout: 10000 });
  await app.page.getByRole('button', { name: 'Войти' }).click();
  await app.page.waitForTimeout(3000);
}

async function apiLogin(p) {
  const code = await (await fetch(`${API}/v1/auth/request-code`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p }),
  })).json();
  const s = await (await fetch(`${API}/v1/auth/verify`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p, code: code.dev_code, platform: 'e2e' }),
  })).json();
  if (!s.access_token) throw new Error(`вход не удался: ${JSON.stringify(s)}`);
  return s;
}

async function syncBook(token, contacts) {
  return (await fetch(`${API}/v1/contacts/sync`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ contacts }),
  })).json();
}

async function connect(session) {
  const sock = new WebSocket('ws://localhost:8080/v1/ws');
  await new Promise((ok, fail) => {
    sock.addEventListener('open', ok);
    sock.addEventListener('error', () => fail(new Error('сокет не открылся')));
    setTimeout(() => fail(new Error('сокет не открылся за 10 с')), 10000);
  });
  sock.send(JSON.stringify({ v: 1, t: 'auth', d: { token: session.access_token } }));
  await new Promise((r) => sock.addEventListener('message', r, { once: true }));
  return sock;
}

let passed = 0, failed = 0;
function check(name, ok, detail = '') {
  if (ok) { passed++; console.log(`  OK   ${name}`); }
  else { failed++; console.log(`  ПЛОХО ${name} ${detail}`); }
}

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });

const myPhone = phone(0);
const peerPhone = phone(1);
const thirdPhone = phone(2);

const app = await open(browser);
await app.page.screenshot({ path: `${OUT}/01-вход.png` });

await signIn(app, myPhone);
await app.page.screenshot({ path: `${OUT}/02-пусто.png` });
check('вошли по номеру', !(await app.page.$('input[aria-label="Номер телефона"]')));

// Собеседник заводит чат и пишет первым.
const peer = await apiLogin(peerPhone);
const sock = await connect(peer);
const found = await syncBook(peer.access_token, [{ phone: myPhone, name: 'Я' }]);
const myId = found.users?.[0]?.id;
check('собеседник нашёл нас по номеру', Boolean(myId));

sock.send(JSON.stringify({
  v: 1, t: 'message.send', id: 'w-1',
  d: { peer_id: myId, text: 'Привет! Это из другого браузера.', client_msg_id: crypto.randomUUID() },
}));
await app.page.waitForTimeout(2500);
await app.page.screenshot({ path: `${OUT}/03-пришло.png` });

let text = await app.page.locator('body').innerText();
check('чат появился сам, без перезагрузки', text.includes('Привет! Это из другого браузера'), text.slice(0, 200));

// Открываем чат и отвечаем.
await app.page.getByText('Привет! Это из другого браузера').first().click();
await app.page.waitForTimeout(1500);
await app.page.screenshot({ path: `${OUT}/04-переписка.png` });

const reply = new Promise((res) => {
  sock.addEventListener('message', (e) => {
    const env = JSON.parse(e.data);
    if (env.t === 'message.new') res(env.d.message.text);
  });
});

await app.page.locator('textarea').first().fill('И тебе привет — это уже наш сервер');
await app.page.keyboard.press('Enter');
await app.page.waitForTimeout(2000);
await app.page.screenshot({ path: `${OUT}/05-ответ.png` });

const delivered = await Promise.race([reply, new Promise((r) => setTimeout(() => r(null), 8000))]);
check('ответ дошёл до собеседника', delivered === 'И тебе привет — это уже наш сервер', String(delivered));

text = await app.page.locator('body').innerText();
check('свой ответ виден в ленте', text.includes('И тебе привет'), text.slice(0, 200));

// --- Новый чат из интерфейса ---
//
// До этого переписка всегда появлялась снаружи: собеседник писал первым.
// Здесь проверяется обратный путь — человек сам выбирает, кому написать, а
// чат на сервере заводится первым же сообщением.
const third = await apiLogin(thirdPhone);
await fetch(`${API}/v1/users/me`, {
  method: 'PATCH',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${third.access_token}` },
  body: JSON.stringify({ display_name: 'Вера Новикова' }),
});
// Книгу контактов на телефоне заполняет система; в браузере — некому.
// Токен для этого берём отдельным входом по тому же номеру: браузер держит
// свой в localStorage, и доставать его оттуда значило бы лезть во внутренности.
const mine = await apiLogin(myPhone);
await fetch(`${API}/v1/contacts/sync`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${mine.access_token}` },
  body: JSON.stringify({ contacts: [{ phone: thirdPhone, name: 'Вера Новикова' }] }),
});
// Список подтянется на следующей синхронизации — перезагружаем страницу.
await app.page.reload({ waitUntil: 'networkidle' });
await app.page.waitForTimeout(3000);

await app.page.locator('button[aria-label="Новое сообщение"]:visible').first().click();
await app.page.waitForTimeout(900);
check('экран «новый чат» открылся', await app.page.getByText('Создать группу').first().isVisible());

await app.page.getByText('Вера Новикова').first().click();
await app.page.waitForTimeout(900);
await app.page.locator('textarea').first().fill('Пишу первым');
await app.page.keyboard.press('Enter');
await app.page.waitForTimeout(3000);
await app.page.screenshot({ path: `${OUT}/06-новый-чат.png` });

const started = await app.page.evaluate(() => {
  const raw = localStorage.getItem('tito-messenger');
  const state = raw ? JSON.parse(raw).state : {};
  const message = (state.messages ?? []).find((m) => m.text === 'Пишу первым');
  return { status: message?.status, chats: (state.chats ?? []).length };
});
check('первое сообщение ушло, а не упало', started.status === 'sent', String(started.status));
check('новая переписка встала в список', started.chats >= 2, `чатов ${started.chats}`);

// --- Группа ---
await app.page.locator('button[aria-label="Новое сообщение"]:visible').first().click();
await app.page.waitForTimeout(800);
await app.page.getByText('Создать группу').first().click();
await app.page.waitForTimeout(600);
await app.page.getByText('Вера Новикова').first().click();
await app.page.waitForTimeout(300);
await app.page.locator('input[aria-label="Название группы"]').fill('Команда Tito');
await app.page.getByRole('button', { name: 'Создать' }).click();
await app.page.waitForTimeout(3000);
await app.page.screenshot({ path: `${OUT}/07-группа.png` });
check('группа создана и открыта',
  (await app.page.locator('body').innerText()).includes('Команда Tito'));

// --- Настройки ---
await app.page.locator('button[aria-label="Меню"]:visible').first().click();
await app.page.waitForTimeout(1200);
await app.page.screenshot({ path: `${OUT}/08-настройки.png` });
check('выход из аккаунта выведен в настройки',
  await app.page.getByText('Выйти').first().isVisible());

sock.close();
await app.context.close();
await browser.close();

console.log(`\nИтог: ${passed}/${passed + failed}`);
process.exit(failed === 0 ? 0 : 1);
