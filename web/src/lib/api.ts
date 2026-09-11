/// REST-клиент.
///
/// Через сокет идёт всё живое общение; сюда вынесено то, что либо
/// предшествует соединению (вход), либо плохо ложится на кадры —
/// постраничная история, адресная книга и загрузка файлов.
///
/// Повторяет `app/lib/data/api/api_client.dart`: два клиента должны
/// разговаривать с сервером одинаково, иначе расхождения всплывут не в
/// коде, а в переписке живых людей.

const BASE: string =
  import.meta.env.VITE_API_BASE ?? "http://localhost:8080";

export type Session = {
  accessToken: string;
  refreshToken: string;
  userId: string;
  /// Момент, после которого access-токен недействителен.
  expiresAt: number;
};

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const STORAGE_KEY = "tito.session";

function readSession(): Session | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    // Формат поменялся или запись побилась — проще переспросить вход, чем
    // разбираться в мусоре.
    return null;
  }
}

function writeSession(session: Session | null) {
  if (session) localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  else localStorage.removeItem(STORAGE_KEY);
}

function sessionFromAuth(json: Record<string, unknown>): Session {
  const user = json.user as { id: string };
  return {
    accessToken: json.access_token as string,
    refreshToken: json.refresh_token as string,
    userId: user.id,
    expiresAt: Date.now() + ((json.expires_in as number) ?? 900) * 1000,
  };
}

/// Токен считается протухшим за минуту до срока: запрос может уйти в дорогу
/// с ещё годным токеном и приехать с просроченным.
function isExpiring(session: Session): boolean {
  return Date.now() > session.expiresAt - 60_000;
}

let refreshing: Promise<Session | null> | null = null;

/// Единственная точка обновления пары токенов.
///
/// Если пустить сюда параллельные запросы, они устроят гонку ротаций:
/// сервер отзовёт refresh при первом же использовании, второй запрос
/// получит отказ, и человека выкинет из аккаунта на ровном месте.
export async function freshAccessToken(): Promise<string | null> {
  const session = readSession();
  if (!session) return null;
  if (!isExpiring(session)) return session.accessToken;

  refreshing ??= refresh(session.refreshToken);
  try {
    return (await refreshing)?.accessToken ?? null;
  } finally {
    refreshing = null;
  }
}

async function refresh(refreshToken: string): Promise<Session | null> {
  try {
    const json = await post(
      "/v1/auth/refresh",
      { refresh_token: refreshToken },
      false,
    );
    const session = sessionFromAuth(json);
    writeSession(session);
    return session;
  } catch (error) {
    // Refresh мёртв — сессию восстановить нельзя, нужен новый вход.
    if (error instanceof ApiError && error.status === 401) writeSession(null);
    return null;
  }
}

async function headers(auth: boolean): Promise<HeadersInit> {
  const result: Record<string, string> = {
    "Content-Type": "application/json; charset=utf-8",
  };
  if (auth) {
    const token = await freshAccessToken();
    if (token) result.Authorization = `Bearer ${token}`;
  }
  return result;
}

async function parse(response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  const json = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  if (response.ok) return json;

  const error = json.error as { code?: string; message?: string } | undefined;
  throw new ApiError(
    response.status,
    error?.code ?? "unknown",
    error?.message ?? `Ошибка ${response.status}`,
  );
}

async function get(
  path: string,
  query?: Record<string, string | number | undefined>,
): Promise<Record<string, unknown>> {
  const url = new URL(BASE + path);
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }
  return parse(await fetch(url, { headers: await headers(true) }));
}

async function post(
  path: string,
  body: unknown,
  auth = true,
): Promise<Record<string, unknown>> {
  return parse(
    await fetch(BASE + path, {
      method: "POST",
      headers: await headers(auth),
      body: JSON.stringify(body),
    }),
  );
}

export const api = {
  base: BASE,
  session: readSession,
  clearSession: () => writeSession(null),

  requestCode(phone: string) {
    return post("/v1/auth/request-code", { phone }, false);
  },

  async verify(phone: string, code: string): Promise<Session> {
    const json = await post(
      "/v1/auth/verify",
      { phone, code, platform: "web", device: navigator.userAgent.slice(0, 64) },
      false,
    );
    const session = sessionFromAuth(json);
    writeSession(session);
    return session;
  },

  async logout() {
    const session = readSession();
    if (session) {
      try {
        await post(
          "/v1/auth/logout",
          { refresh_token: session.refreshToken },
          false,
        );
      } catch {
        // Сервер недоступен — локальную сессию всё равно стираем: человек
        // нажал «выйти», и его ожидание важнее аккуратного отзыва токена.
      }
    }
    writeSession(null);
  },

  me: () => get("/v1/users/me"),

  updateMe: async (displayName: string) =>
    parse(
      await fetch(BASE + "/v1/users/me", {
        method: "PATCH",
        headers: await headers(true),
        body: JSON.stringify({ display_name: displayName }),
      }),
    ),

  async chats(): Promise<unknown[]> {
    const json = await get("/v1/chats");
    return (json.chats as unknown[]) ?? [];
  },

  async history(
    chatId: string,
    options: { beforeSeq?: number; limit?: number } = {},
  ): Promise<unknown[]> {
    const json = await get(`/v1/chats/${chatId}/messages`, {
      before_seq: options.beforeSeq,
      limit: options.limit ?? 50,
    });
    return (json.messages as unknown[]) ?? [];
  },

  async contacts(): Promise<unknown[]> {
    const json = await get("/v1/contacts");
    return (json.contacts as unknown[]) ?? [];
  },

  async searchUsers(query: string): Promise<unknown[]> {
    const json = await get("/v1/users/search", { q: query });
    return (json.users as unknown[]) ?? [];
  },

  /// Загружает файл и возвращает описание вложения.
  ///
  /// Файл уходит ДО отправки сообщения: так виден прогресс, а сообщение
  /// отправляется одним кадром со списком идентификаторов.
  async upload(file: File): Promise<Record<string, unknown>> {
    const form = new FormData();
    form.append("file", file, file.name);
    const token = await freshAccessToken();
    const response = await fetch(BASE + "/v1/media/upload", {
      method: "POST",
      headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      body: form,
    });
    const json = await parse(response);
    return json.attachment as Record<string, unknown>;
  },

  /// Перевод сообщений. Поставщик подключается на сервере; пока его нет,
  /// приходит 503 — и клиент говорит об этом словами.
  async translate(
    items: { id: string; text: string }[],
    targetLang: string,
  ): Promise<{ id: string; text: string; from: string }[]> {
    const json = await post("/v1/ai/translate", {
      items,
      target_lang: targetLang,
    });
    return (json.items as { id: string; text: string; from: string }[]) ?? [];
  },
};
