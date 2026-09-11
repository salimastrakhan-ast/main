/// Снимок всех экранов обоих клиентов.
///
/// Нужен, потому что глазами два клиента сравнивают по картинкам, а не по
/// коду: расхождение в цвете, отступе или порядке кнопок видно только рядом.
/// Раньше такие снимки делались одноразовыми скриптами, до разговора
/// доезжало одно окно переписки, и «собери все экраны» было справедливым.
///
/// Запуск:  make shots
///
/// Что нужно поднятым: `make up`, сервер на 8080, веб-клиент на 4173,
/// сборка Flutter web на 8090. Подробности — в e2e/README.md.

import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const API = process.env.API ?? 'http://localhost:8080';
const WEB = process.env.WEB ?? 'http://127.0.0.1:4173';
const FLUTTER = process.env.FLUTTER ?? 'http://localhost:8090';
// Считаем от корня репозитория, а не от текущей папки: make запускает
// скрипт из e2e/, и кадры легли бы в e2e/docs/shots.
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = process.env.SHOTS ?? resolve(ROOT, 'docs/shots');

const WIDE = { width: 1280, height: 860 };
const NARROW = { width: 430, height: 900 };

const only = process.argv.find((a) => a.startsWith('--only='))?.slice(7);

// Прогон не должен висеть вечно, если один тап не нашёл цели.
const watchdog = setTimeout(() => {
  console.log('Съёмка не уложилась в десять минут');
  process.exit(2);
}, 600000);
watchdog.unref?.();

// --- Съёмка ---

let shots = 0;
const missed = [];

async function shot(page, client, name) {
  const dir = `${OUT}/${client}`;
  await mkdir(dir, { recursive: true });
  await page.screenshot({ path: `${dir}/${name}.png` });
  shots++;
  console.log(`  снято  ${client}/${name}`);
}

function miss(what) {
  missed.push(what);
  console.log(`  мимо   ${what}`);
}

// --- Сервер ---

async function post(path, body, token) {
  const res = await fetch(API + path, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return res.json();
}

async function apiLogin(phone) {
  const code = await post('/v1/auth/request-code', { phone });
  if (!code.dev_code) throw new Error(`код не пришёл: ${JSON.stringify(code)}`);
  const session = await post('/v1/auth/verify', {
    phone,
    code: code.dev_code,
    platform: 'shots',
    device: 'node',
  });
  if (!session.access_token) {
    throw new Error(`вход не удался: ${JSON.stringify(session)}`);
  }
  return session;
}

async function rename(session, name) {
  await fetch(API + '/v1/users/me', {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session.access_token}`,
    },
    body: JSON.stringify({ display_name: name }),
  });
}

async function connect(session) {
  const sock = new WebSocket(API.replace(/^http/, 'ws') + '/v1/ws');
  await new Promise((ok, fail) => {
    sock.addEventListener('open', ok);
    sock.addEventListener('error', () => fail(new Error('сокет не открылся')));
    setTimeout(() => fail(new Error('сокет молчит десять секунд')), 10000);
  });
  sock.send(JSON.stringify({ v: 1, t: 'auth', d: { token: session.access_token } }));
  await new Promise((r) => sock.addEventListener('message', r, { once: true }));
  return sock;
}

/// Команда с ответом: без неё не узнать id созданной группы.
function call(sock, type, data) {
  const id = `s${Math.random().toString(36).slice(2, 8)}`;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${type}: нет ответа`)), 10000);
    const onMessage = (e) => {
      const env = JSON.parse(e.data);
      if (env.id !== id) return;
      clearTimeout(timer);
      sock.removeEventListener('message', onMessage);
      env.t === 'error' ? reject(new Error(env.d.message)) : resolve(env.d);
    };
    sock.addEventListener('message', onMessage);
    sock.send(JSON.stringify({ v: 1, t: type, id, d: data }));
  });
}

function send(sock, data) {
  sock.send(JSON.stringify({
    v: 1,
    t: 'message.send',
    d: { ...data, client_msg_id: crypto.randomUUID() },
  }));
}

const pause = (ms) => new Promise((r) => setTimeout(r, ms));

// --- Наполнение ---
//
// Пустые экраны ничего не показывают: список без чатов и переписка без
// сообщений выглядят одинаково в любом оформлении. Поэтому перед съёмкой
// заводим настоящую переписку через тот же протокол, которым живёт клиент.

const base = 9005000000 + Math.floor(Math.random() * 900000);
const MY = `+7${base}`;
const ANYA = `+7${base + 1}`;
const BORYA = `+7${base + 2}`;

async function seed() {
  console.log('Наполняю сервер…');

  const me = await apiLogin(MY);
  await rename(me, 'Маша');
  const anya = await apiLogin(ANYA);
  await rename(anya, 'Аня Соколова');
  const borya = await apiLogin(BORYA);
  await rename(borya, 'Боря Ким');

  // Адресная книга: без неё собеседники друг друга не найдут.
  const book = async (session, contacts) =>
    (await post('/v1/contacts/sync', { contacts }, session.access_token)).users ?? [];

  // Сервер отдаёт номер уже нормализованным — без плюса. Сравнивать надо по
  // цифрам, иначе совпадений не будет ни одного, а сломается это не здесь, а
  // на chat.create с непонятным «Не найдено».
  const digits = (p) => String(p).replace(/\D/g, '');
  const idOf = (users, phone) =>
    users.find((u) => digits(u.phone) === digits(phone))?.id;

  const seenByAnya = await book(anya, [
    { phone: MY, name: 'Маша' },
    { phone: BORYA, name: 'Боря Ким' },
  ]);
  const myId = idOf(seenByAnya, MY);
  await book(borya, [{ phone: MY, name: 'Маша' }, { phone: ANYA, name: 'Аня Соколова' }]);
  const mine = await book(me, [
    { phone: ANYA, name: 'Аня Соколова' },
    { phone: BORYA, name: 'Боря Ким' },
  ]);
  const anyaId = idOf(mine, ANYA);
  const boryaId = idOf(mine, BORYA);
  if (!myId || !anyaId || !boryaId) {
    throw new Error(`не нашлись собеседники: ${JSON.stringify({ myId, anyaId, boryaId })}`);
  }

  const mySock = await connect(me);
  const anyaSock = await connect(anya);
  const borySock = await connect(borya);

  // Личная переписка с Аней — в обе стороны, чтобы в ленте были оба пузыря.
  send(anyaSock, { peer_id: myId, text: 'Привет! Дошли макеты?' });
  await pause(400);
  send(mySock, { peer_id: anyaId, text: 'Да, смотрю. Цвета наконец сходятся 🙂' });
  await pause(400);
  send(anyaSock, { peer_id: myId, text: 'Отлично. Тогда завтра показываем.' });
  await pause(400);
  send(mySock, { peer_id: anyaId, text: 'Договорились. Скинь ещё список экранов.' });
  await pause(600);

  // Второй личный чат — чтобы список не состоял из одной строки.
  send(borySock, { peer_id: myId, text: 'Сервер поднял, можно проверять.' });
  await pause(600);

  // Группа: в ней над пузырями видны имена отправителей.
  const group = await call(mySock, 'chat.create', {
    title: 'Команда Tito',
    member_ids: [anyaId, boryaId],
  });
  const groupId = group.chat?.id ?? group.id;
  await pause(400);
  send(anyaSock, { chat_id: groupId, text: 'Собираемся в четверг?' });
  await pause(400);
  send(borySock, { chat_id: groupId, text: 'Я за. Утром удобнее.' });
  await pause(400);
  send(mySock, { chat_id: groupId, text: 'Тогда в десять.' });
  await pause(600);

  // «Избранное» — личный чат с самим собой.
  send(mySock, { peer_id: myId, text: 'Не забыть: пересобрать иконки' });
  await pause(800);

  console.log(`  завели: два личных чата, группу и избранное`);
  return { me, myId, anyaId, anyaSock, groupId };
}

// --- Веб-клиент ---

async function walkWeb(browser, world) {
  const context = await browser.newContext({ viewport: WIDE });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.log('  ошибка страницы:', String(e).slice(0, 140)));
  await page.goto(WEB, { waitUntil: 'networkidle' });

  // Вход — на телефонной ширине: этот экран так и выглядит в жизни.
  await page.setViewportSize(NARROW);
  await pause(600);
  await shot(page, 'веб', '01-номер');
  await page.fill('input[aria-label="Номер телефона"]', MY);
  await page.getByRole('button', { name: 'Получить код' }).click();
  await page.waitForSelector('input[aria-label="Код из SMS"]', { timeout: 15000 });
  await pause(400);
  await shot(page, 'веб', '02-код');
  await page.getByRole('button', { name: 'Войти' }).click();
  await pause(4000);

  // Кнопок с одной подписью на странице бывает две: например «Назад» в
  // шапке переписки и в настройках, причём одна спрятана вёрсткой под
  // ширину. Берём видимую, иначе клик ждёт спрятанную до таймаута.
  const tap = async (what, locator) => {
    try {
      await locator.click({ timeout: 5000 });
      await pause(900);
      return true;
    } catch {
      miss(`веб: ${what}`);
      return false;
    }
  };
  const visible = (selector) => page.locator(`${selector}:visible`).first();
  const button = (name) => visible(`button[aria-label="${name}"]`);

  // --- Широкий экран: панель и переписка рядом ---
  await page.setViewportSize(WIDE);
  await pause(1200);
  await shot(page, 'веб', '03-широкий-ничего-не-выбрано');

  if (await tap('строка Ани', page.getByText('Аня Соколова').first())) {
    await shot(page, 'веб', '04-широкий-переписка');
  }

  // «Печатает…» живёт три секунды — снимок делаем сразу.
  world.anyaSock.send(JSON.stringify({
    v: 1, t: 'typing', d: { chat_id: null, peer_id: world.myId, typing: true },
  }));
  await pause(700);
  await shot(page, 'веб', '05-широкий-печатает');

  if (await tap('меню чата', button('Настройки'))) {
    await shot(page, 'веб', '06-широкий-меню-чата');
    await page.keyboard.press('Escape');
    await pause(400);
  }

  if (await tap('группа', page.getByText('Команда Tito').first())) {
    await shot(page, 'веб', '07-широкий-группа');
  }

  if (await tap('избранное', page.getByText('Избранное').first())) {
    await shot(page, 'веб', '08-широкий-избранное');
  }

  // В шапке панели кнопка подписана «Меню», а «Настройки» — это меню
  // самой переписки. Подписи снял с живой страницы, не с памяти.
  if (await tap('настройки', button('Меню'))) {
    await shot(page, 'веб', '09-широкий-настройки');
    await tap('назад из настроек', button('Назад'));
  }

  if (await tap('новый чат', button('Новое сообщение'))) {
    await shot(page, 'веб', '10-широкий-новый-чат');
    if (await tap('создание группы', page.getByText('Создать группу').first())) {
      await shot(page, 'веб', '11-широкий-новая-группа');
    }
    await tap('назад из нового чата', button('Назад'));
    await tap('назад из нового чата', button('Назад'));
  }

  // --- Узкий экран: панель и переписка по очереди ---
  await page.setViewportSize(NARROW);
  await pause(1000);
  await shot(page, 'веб', '12-узкий-переписка');

  if (await tap('к списку', button('Назад'))) {
    await shot(page, 'веб', '13-узкий-список');
  }

  const search = visible('input[placeholder="Поиск"]');
  try {
    await search.fill('аня', { timeout: 4000 });
    await pause(700);
    await shot(page, 'веб', '14-узкий-поиск');
    await search.fill('');
    await pause(500);
  } catch {
    miss('веб: поиск в списке');
  }

  if (await tap('папка «Группы»', visible('button:text-is("Группы")'))) {
    await shot(page, 'веб', '15-узкий-папка-группы');
  }

  await context.close();
}

// --- Flutter ---
//
// Flutter рисует в канвас: обычных кнопок в DOM нет, работаем через дерево
// доступности — узлы flt-semantics с текстом.

async function walkFlutter(browser) {
  const context = await browser.newContext({
    viewport: NARROW,
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.log('  ошибка страницы:', String(e).slice(0, 140)));
  page.on('response', (r) => {
    if (r.url().includes('/v1/') && r.status() >= 400) {
      console.log(`  сервер ответил ${r.status()} на ${new URL(r.url()).pathname}`);
    }
  });

  await page.goto(FLUTTER, { waitUntil: 'load' });
  await page.waitForSelector('flutter-view', { timeout: 60000 });
  await pause(2000);
  // Кнопка включения доступности 1×1 за краем экрана: обычный клик мимо.
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await pause(1500);

  const readNodes = () =>
    page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')].map((e) => {
        const r = e.getBoundingClientRect();
        return {
          text: (e.textContent ?? '').trim(),
          role: e.getAttribute('role'),
          x: r.x, y: r.y, w: r.width, h: r.height,
        };
      }).filter((n) => n.text && n.w > 0 && n.h > 0));

  /// Узлы дерева доступности с их местом на экране.
  ///
  /// Пустое дерево не значит пустой экран: движок иногда сбрасывает
  /// доступность — например, после закрытия всплывающего меню, — и тогда
  /// его надо включить заново. Без этого дальше промахивается всё подряд, а
  /// в логе стоит «на экране: » с пустотой.
  const nodes = async () => {
    let found = await readNodes();
    if (found.length === 0) {
      await page.evaluate(() =>
        document.querySelector('flt-semantics-placeholder')?.click());
      await pause(800);
      found = await readNodes();
    }
    return found;
  };

  /// Что сейчас на экране — словами. Нужно, чтобы промах читался в логе, а
  /// не выяснялся гаданием.
  const screenText = async () =>
    (await nodes()).map((n) => n.text).filter((t) => t.length < 60).join(' | ');

  /// Уводит указатель с кнопки.
  ///
  /// Flutter после клика показывает всплывающую подпись и держит её, пока
  /// мышь на кнопке. Подпись — отдельный узел дерева с тем же текстом:
  /// следующий клик уходил в неё, и кнопка не срабатывала. А на снимке она
  /// просто висела поверх шапки.
  ///
  /// Уводить в левый верхний угол нельзя — там стрелка «Назад». Правый край
  /// по середине высоты пуст в обеих раскладках.
  const unhover = async () => {
    const size = page.viewportSize();
    await page.mouse.move(size.width - 2, Math.round(size.height / 2));
    await pause(350);
  };

  /// Снимок экрана: сначала убираем подсказку, иначе она попадёт в кадр.
  const frame = async (name) => {
    await unhover();
    await shot(page, 'flutter', name);
  };

  /// Нажатие кнопки. Ищем именно кнопку (role=button), а не любой узел с
  /// таким текстом: у подписи-подсказки текст тот же.
  const press = async (label) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      const hit = (await nodes())
        .filter((n) => n.role === 'button' && n.text === label && n.h >= 16)
        .pop();
      if (hit) {
        await page.mouse.click(hit.x + hit.w / 2, hit.y + hit.h / 2);
        await pause(1000);
        await unhover();
        return true;
      }
      await pause(900);
    }
    miss(`Flutter: кнопка «${label}» — на экране: ${(await screenText()).slice(0, 200)}`);
    return false;
  };

  /// Ставит курсор в поле ввода.
  ///
  /// Поле Flutter отдаёт настоящим <input> в DOM, но без текста и без
  /// подсказки: в дереве доступности его не найти ни по одному слову.
  /// Поэтому ищем сам элемент, а не подпись, и не целимся по координатам —
  /// промах «примерно туда» один раз уже дал снимок нетронутого списка.
  const focusField = async (index = 0) => {
    const box = await page.evaluate((i) => {
      const field = [...document.querySelectorAll('input, textarea')][i];
      if (!field) return null;
      const r = field.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height };
    }, index);
    if (!box) {
      miss('Flutter: поле ввода');
      return false;
    }
    await page.mouse.click(box.x + box.w / 2, box.y + box.h / 2);
    await pause(600);
    return true;
  };

  /// Тап по строке или пункту списка. Берём самый маленький узел с этим
  /// текстом: он и есть сам элемент, а не контейнер всего экрана.
  const tap = async (text) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      const candidates = (await nodes())
        .filter((n) => n.text.includes(text) && n.h >= 16 && n.h < 200)
        .sort((a, b) => a.w * a.h - b.w * b.h);
      const hit = candidates[0];
      if (hit) {
        await page.mouse.click(hit.x + hit.w / 2, hit.y + hit.h / 2);
        await pause(1100);
        await unhover();
        return true;
      }
      await pause(900);
    }
    miss(`Flutter: «${text}» — на экране: ${(await screenText()).slice(0, 200)}`);
    return false;
  };

  // --- Вход ---
  await frame('01-приветствие');
  await tap('Начать');
  await pause(1500);
  await frame('02-номер');

  await focusField();
  await page.keyboard.type(MY, { delay: 25 });
  await pause(700);
  await press('Получить код');
  await pause(4000);
  await frame('03-код');
  await press('Войти');
  await pause(6000);

  // --- Узкий экран ---
  await frame('04-узкий-список');

  if (await tap('Аня Соколова')) {
    await frame('05-узкий-переписка');
    // Меню переписки: закрепить, без звука, сведения. Снимаем его открытым
    // — закрепление иначе не показать ничем.
    // Меню переписки снимаем открытым — закрепление иначе не показать
    // ничем, — но нажимать по его пунктам нельзя: пока всплывающее открыто,
    // в дереве доступности остаются только подложка и каркас, без текста.
    // Поэтому закрываем его подложкой, а сведения открываем из шапки.
    if (await press('Ещё')) {
      await shot(page, 'flutter', '05a-меню-чата');
      await page.mouse.click(12, 400);
      await pause(900);
    }
    if (await tap('Аня Соколова')) {
      await frame('06-сведения-о-чате');
      if (await tap('Медиа, файлы, ссылки')) {
        await frame('07-медиа-чата');
        await press('Назад');
      }
      await press('Назад');
    }
    await press('К списку');
  }

  if (await tap('Команда Tito')) {
    await frame('08-узкий-группа');
    await press('К списку');
  }

  if (await tap('Избранное')) {
    await frame('09-узкий-избранное');
    await press('К списку');
  }

  if (await press('Новый чат')) {
    await frame('10-новый-чат');
    await press('Назад');
  }

  if (await press('Настройки')) {
    await frame('11-настройки');
    if (await tap('Аккаунт')) {
      await frame('12-аккаунт');
      await press('Назад');
    }
    // Настройки занимают место панели, а не отдельный маршрут: стрелка
    // возвращает список, и подписана она соответственно.
    await press('К диалогам');
  }

  // Поиск: фильтр по списку, а под ним — переход в поиск по сообщениям.
  // Поле ищем по подсказке, а не по координатам: попадание «примерно туда»
  // один раз уже дало снимок нетронутого списка вместо отфильтрованного.
  await focusField();
  await page.keyboard.type('аня', { delay: 30 });
  await pause(1000);
  await frame('13-поиск-в-списке');
  if (await tap('Искать в сообщениях')) {
    await frame('14-поиск-по-сообщениям');
    await press('Назад');
  }

  // Запрос в поле остаётся, и список дальше был бы отфильтрован: широкий
  // экран снялся бы с одной строкой вместо всех чатов.
  await focusField();
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await pause(800);

  // --- Широкий экран: панель и переписка рядом ---
  await page.setViewportSize(WIDE);
  await pause(2000);
  await frame('15-широкий-ничего-не-выбрано');
  if (await tap('Аня Соколова')) {
    await frame('16-широкий-переписка');
  }
  if (await tap('Команда Tito')) {
    await frame('17-широкий-группа');
  }

  await context.close();
}

// --- Прогон ---

// Ограничение на коды — двадцать на адрес в час. Оно живёт в Redis, и без
// сброса второй прогон подряд упирается в 429; выглядит это как «клиент не
// отвечает на нажатия», а не как отказ сервера. Один раз я на это уже попался.
try {
  execFileSync('redis-cli', ['-p', '6380', 'FLUSHDB'], { stdio: 'ignore' });
  console.log('Счётчик кодов сброшен');
} catch {
  console.log('redis-cli недоступен — если упрёмся в 429, причина здесь');
}

const world = await seed();

const browser = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium',
  args: ['--no-sandbox'],
});

if (only !== 'flutter') {
  console.log('\nВеб-клиент…');
  await walkWeb(browser, world);
}
if (only !== 'web') {
  console.log('\nFlutter…');
  await walkFlutter(browser);
}

await browser.close();
world.anyaSock.close();

console.log(`\nСнято кадров: ${shots}`);
if (missed.length) {
  console.log(`Не нашлось: ${missed.length}`);
  for (const m of missed) console.log(`  · ${m}`);
}
process.exit(0);
