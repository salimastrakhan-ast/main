// Состав группы и удаление чатов — про права.
//
// Ошибка здесь не «неудобно», а «посторонний стёр переписку» или «владельца
// выставили из его же группы». Сервер это проверяет тестами; здесь проверяется
// вторая половина: интерфейс не показывает того, чего человеку нельзя, и
// показывает то, что можно.
//
//   make e2e-groups
import { chromium } from 'playwright';
const WEB = 'http://127.0.0.1:4173', API = 'http://localhost:8080';
const OUT = process.env.SCRATCH
  ? `${process.env.SCRATCH}/groupshots`
  : new URL('shots/groupshots', import.meta.url).pathname;

const base = 9011000000 + Math.floor(Math.random() * 800000);
const phone = (n) => `+7${base + n}`;
let bad = 0;
const check = (w, ok, d = '') => { console.log(`${ok ? '  ✓' : '  ✗'} ${w}${d ? ` — ${d}` : ''}`); if (!ok) bad++; };
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
async function login(p) {
  const c = await (await fetch(`${API}/v1/auth/request-code`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: p }) })).json();
  const s = await (await fetch(`${API}/v1/auth/verify`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: p, code: c.dev_code, platform: 'web', device: 'e2e' }) })).json();
  return { s, session: { accessToken: s.access_token, refreshToken: s.refresh_token, userId: s.user.id, expiresAt: Date.now() + 900000 } };
}
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
try {
  const [a, b] = await Promise.all([login(phone(1)), login(phone(2))]);

  const open = async (session) => {
    const ctx = await browser.newContext({ viewport: { width: 1200, height: 820 } });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => console.log('  ошибка:', String(e).slice(0, 180)));
    await page.goto(WEB);
    await page.evaluate((s) => localStorage.setItem('tito.session', JSON.stringify(s)), session);
    await page.goto(WEB, { waitUntil: 'networkidle' });
    await pause(2500);
    return page;
  };
  const owner = await open(a.session);
  const member = await open(b.session);

  // Знакомимся, чтобы Боря попал в контакты.
  await owner.locator('button[aria-label="Новое сообщение"]:visible').first().click();
  await pause(800);
  await owner.locator('input[placeholder*="Найти"]').first().fill(phone(2));
  await pause(2200);
  await owner.locator('ul li button').first().click();
  await pause(900);
  await owner.locator('textarea').first().fill('привет');
  await owner.keyboard.press('Enter');
  await pause(1800);

  // --- Группа ---
  await owner.locator('button[aria-label="Новое сообщение"]:visible').first().click();
  await pause(800);
  await owner.getByText('Создать группу').first().click();
  await pause(900);
  // Боря уже в контактах: выбираем его из книги, а не ищем заново.
  // Боря уже в контактах после переписки; если книга пуста — ищем по номеру.
  const rows = await owner.locator('ul li button').count();
  if (rows === 0) {
    await owner.locator('input[placeholder*="Найти"]').first().fill(phone(2));
    await pause(2200);
  }
  await owner.locator('ul li button').first().click();
  await pause(600);
  await owner.locator('input[aria-label="Название группы"]').fill('Планёрка');
  await owner.getByRole('button', { name: 'Создать', exact: true }).first().click();
  await pause(2500);
  check('группа создана', (await owner.getByText('Планёрка').count()) > 0);

  await owner.getByText('Планёрка').first().click();
  await pause(1200);
  await owner.locator('button[aria-label="Настройки"]:visible').first().click();
  await pause(500);
  await owner.getByText('Сведения', { exact: true }).first().click();
  await pause(1000);
  check('владелец видит «Удалить группу у всех»',
    (await owner.getByText('Удалить группу у всех').count()) > 0);
  const tiles = await owner
    .locator('aside button[title]')
    .evaluateAll((els) => els.map((e) => e.getAttribute('title')));
  check('владелец видит кнопку исключения',
    (await owner.locator('button[aria-label^="Исключить"]').count()) > 0);
  check('в группе нет кнопки звонка', !tiles.includes('Позвонить'),
    JSON.stringify(tiles));
  await owner.screenshot({ path: `${OUT}/06-группа-владелец.png` });

  // --- Участник тех же кнопок не видит ---
  await member.getByText('Планёрка').first().click();
  await pause(1200);
  await member.locator('button[aria-label="Настройки"]:visible').first().click();
  await pause(500);
  await member.getByText('Сведения', { exact: true }).first().click();
  await pause(900);
  check('участник не видит удаления у всех',
    (await member.getByText('Удалить группу у всех').count()) === 0);
  check('участник не видит исключения',
    (await member.locator('button[aria-label^="Исключить"]').count()) === 0);

  // --- Исключение ---
  owner.on('dialog', (d) => d.accept());
  await owner.locator('button[aria-label^="Исключить"]').first().click();
  await pause(2500);
  check('исключённый потерял группу', (await member.getByText('Планёрка').count()) === 0);

  // --- Удаление группы у всех ---
  await owner.getByText('Удалить группу у всех').first().click();
  await pause(2500);
  check('группа исчезла у владельца', (await owner.getByText('Планёрка').count()) === 0);
} finally { await browser.close(); }
console.log(bad === 0 ? '\nСостав группы и удаление работают.' : `\nНе сошлось: ${bad}`);
process.exit(bad === 0 ? 0 : 1);
