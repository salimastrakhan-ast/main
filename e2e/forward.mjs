// Пересылка сообщений.
//
// Проверяется не «кнопка нажалась», а то, ради чего пересылка нужна: чужой
// текст оказывается в другой переписке и подписан первым автором — иначе он
// выглядит написанным вами.
//
//   make e2e-forward
import { chromium } from 'playwright';

const WEB = process.env.WEB ?? 'http://127.0.0.1:4173';
const API = process.env.API ?? 'http://localhost:8080';
const OUT = process.env.SCRATCH
  ? `${process.env.SCRATCH}/forwardshots`
  : new URL('shots/forwardshots', import.meta.url).pathname;

const base = 9012000000 + Math.floor(Math.random() * 800000);
const phone = (n) => `+7${base + n}`;

let bad = 0;
const check = (w, ok, d = '') => {
  console.log(`${ok ? '  ✓' : '  ✗'} ${w}${d ? ` — ${d}` : ''}`);
  if (!ok) bad++;
};
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

async function login(p) {
  const c = await (await fetch(`${API}/v1/auth/request-code`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p }),
  })).json();
  const s = await (await fetch(`${API}/v1/auth/verify`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: p, code: c.dev_code, platform: 'web', device: 'e2e' }),
  })).json();
  return {
    accessToken: s.access_token, refreshToken: s.refresh_token,
    userId: s.user.id, expiresAt: Date.now() + (s.expires_in ?? 900) * 1000,
  };
}

const browser = await chromium.launch({
  executablePath: process.env.CHROME ?? '/opt/pw-browsers/chromium',
  args: ['--no-sandbox'],
});

try {
  const [anya, borya, vita] = await Promise.all([
    login(phone(1)), login(phone(2)), login(phone(3)),
  ]);

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

  const write = async (page, to, text) => {
    await page.locator('button[aria-label="Новое сообщение"]:visible').first().click();
    await pause(800);
    await page.locator('input[placeholder*="Найти"]').first().fill(to);
    await pause(2200);
    await page.locator('ul li button').first().click();
    await pause(900);
    await page.locator('textarea').first().fill(text);
    await page.keyboard.press('Enter');
    await pause(1800);
  };

  const anyaPage = await open(anya);
  const boryaPage = await open(borya);
  const vitaPage = await open(vita);

  // Аня пишет Боре, Боря заводит переписку с Витей, потом пересылает ей
  // сообщение Ани.
  await write(anyaPage, phone(2), 'важное объявление');
  await write(boryaPage, phone(3), 'привет');

  // Открываем переписку с Аней — там лежит её сообщение. В списке слева
  // она подписана её же текстом.
  await boryaPage.locator('aside button').filter({ hasText: 'важное объявление' })
    .first().click();
  await pause(1400);
  check('сообщение Ани видно у Бори',
    (await boryaPage.locator('main').getByText('важное объявление').count()) > 0);

  // Кнопки сообщения появляются по наведению или по клику на пузырь.
  // Клик надёжнее: между наведением и нажатием мышь успевает уехать.
  await boryaPage.locator('main').getByText('важное объявление').first().click();
  await pause(600);
  await boryaPage.locator('button[aria-label="Переслать"]').first().click();
  await pause(800);
  check('окно выбора чата открылось',
    await boryaPage.getByRole('dialog', { name: 'Кому переслать' }).isVisible());
  await boryaPage.screenshot({ path: `${OUT}/01-выбор-чата.png` });

  // Выбираем переписку с Витей.
  const rows = boryaPage.locator('div[role="dialog"] ul li button');
  const titles = await rows.allInnerTexts();
  const index = titles.findIndex((x) => !x.includes('важное'));
  await rows.nth(index >= 0 ? index : 0).click();
  await pause(2500);

  check('пересланное подписано первым автором',
    (await boryaPage.getByText('Переслано от').count()) > 0);
  await boryaPage.screenshot({ path: `${OUT}/02-переслано.png` });

  await pause(1500);
  check('текст доехал до третьего человека',
    (await vitaPage.getByText('важное объявление').count()) > 0);

  // Отметка живёт в ленте, а не в списке слева: чтобы её увидеть, надо
  // открыть переписку.
  await vitaPage.locator('aside button').filter({ hasText: 'важное объявление' })
    .first().click();
  await pause(1400);
  check('у третьего он тоже подписан автором',
    (await vitaPage.locator('main').getByText('Переслано от').count()) > 0);
  await vitaPage.screenshot({ path: `${OUT}/03-у-получателя.png` });
} finally {
  await browser.close();
}

console.log(bad === 0 ? '\nПересылка работает.' : `\nНе сошлось: ${bad}`);
process.exit(bad === 0 ? 0 : 1);
