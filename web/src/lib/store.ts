/// Состояние приложения.
///
/// Форма стора и имена полей — из присланного образца, чтобы экраны
/// переносились без правок. Наполнение другое: вместо выдуманного `seed.ts`
/// здесь настоящий сервер — REST для истории и сокет для всего живого.
///
/// Чего в образце не было и что перенесено из Flutter-клиента:
///
///   * очередь отправки — сообщение видно сразу, уходит отдельно и
///     переживает обрыв связи и перезагрузку вкладки;
///   * идемпотентность по `client_msg_id` — повтор не создаёт второе
///     сообщение;
///   * докачка по `seq` после обрыва — команда `sync` с курсорами по чатам.

import { create } from "zustand";
import { persist } from "zustand/middleware";
import { api } from "./api";
import type {
  Attachment,
  AttachmentKind,
  Chat,
  Contact,
  FolderId,
  Me,
  Message,
  SidebarView,
  TargetLang,
  UiLang,
} from "./types";
import { uid } from "./utils";
import { Cmd, Ev, ProtocolError, ws, type Envelope, type WsStatus } from "./ws";

// --- Перевод серверных полей в понятия интерфейса ---

type ServerUser = {
  id: string;
  display_name: string;
  phone?: string;
  avatar_url?: string;
  last_seen_at?: string;
};

type ServerChat = {
  id: string;
  type: "private" | "group";
  title: string;
  avatar_url?: string;
  last_seq: number;
};

type ServerAttachment = {
  id: string;
  kind: AttachmentKind;
  url?: string;
  file_name?: string;
  mime: string;
  size: number;
  width?: number;
  height?: number;
};

type ServerMessage = {
  id: string;
  chat_id: string;
  seq: number;
  sender_id: string;
  text: string;
  client_msg_id: string;
  created_at: string;
  reply_to_id?: string;
  deleted_at?: string;
  attachments?: ServerAttachment[];
};

function toAttachment(raw: ServerAttachment): Attachment {
  return {
    id: raw.id,
    kind: raw.kind,
    url: raw.url,
    fileName: raw.file_name,
    mime: raw.mime,
    size: raw.size,
    width: raw.width,
    height: raw.height,
  };
}

type ServerSummary = {
  chat: ServerChat;
  members: { user_id: string; role: string; last_read_seq: number }[];
  users: ServerUser[];
  last_message?: ServerMessage;
  unread_count: number;
  pinned?: boolean;
  muted?: boolean;
};

/// Две буквы для кружка аватара: пока люди не завели картинки, только по ним
/// строка списка и отличается от соседней.
function initialsOf(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return "?";
  const first = words[0]?.[0] ?? "";
  const second = words.length > 1 ? (words[1]?.[0] ?? "") : "";
  return (first + second).toUpperCase();
}

function toContact(user: ServerUser, online: boolean): Contact {
  return {
    id: user.id,
    name: user.display_name,
    about: user.phone,
    avatar: user.avatar_url,
    initials: initialsOf(user.display_name),
    online,
    lastSeenAt: user.last_seen_at
      ? new Date(user.last_seen_at).getTime()
      : undefined,
  };
}

function toMessage(raw: ServerMessage): Message {
  return {
    id: raw.id,
    chatId: raw.chat_id,
    senderId: raw.sender_id,
    text: raw.deleted_at ? "" : raw.text,
    createdAt: new Date(raw.created_at).getTime(),
    status: "sent",
    replyToId: raw.reply_to_id,
    attachments: raw.attachments?.map(toAttachment),
    seq: raw.seq,
    clientMsgId: raw.client_msg_id,
    deleted: Boolean(raw.deleted_at),
  };
}

// --- Состояние ---

type Outgoing = {
  clientMsgId: string;
  chatId?: string;
  peerId?: string;
  text: string;
  replyToId?: string;
  /// Файлы уходят на сервер до сообщения, здесь остаются только их номера.
  attachmentIds?: string[];
};

type State = {
  me: Me | null;
  contacts: Record<string, Contact>;
  chats: Chat[];
  messages: Message[];
  /// До какого номера мы всё знаем по каждому чату. Отдельно от `last_seq`:
  /// о существовании более свежих сообщений можно знать, ещё не получив их.
  cursors: Record<string, number>;
  outbox: Outgoing[];

  uiLang: UiLang;
  targetLang: TargetLang;
  notifications: boolean;
  status: WsStatus;

  selectedChatId: string | null;
  /// С кем начата переписка, которой ещё нет на сервере.
  ///
  /// Личный чат заводится первым сообщением, а не открытием экрана. До
  /// этого показывать нечего и выбирать нечего — поэтому собеседник
  /// держится отдельно от выбранного чата.
  draftPeerId: string | null;
  folder: FolderId;
  search: string;
  sidebarView: SidebarView;
  replyToId: string | null;
  typingChatId: string | null;
  translatingChatId: string | null;
  draftBusy: boolean;
  revealedOriginal: Record<string, boolean>;
  /// Почему перевод не сработал — показываем словами вместо молчания.
  translateError: string | null;
};

type Actions = {
  bootstrap: () => Promise<void>;
  signOut: () => Promise<void>;

  setUiLang: (lang: UiLang) => void;
  setTargetLang: (lang: TargetLang) => void;
  setNotifications: (v: boolean) => void;
  setMe: (patch: Partial<Me>) => void;
  setSearch: (q: string) => void;
  setFolder: (f: FolderId) => void;
  setSidebarView: (v: SidebarView) => void;
  selectChat: (id: string | null) => void;
  startChatWith: (userId: string) => void;
  createGroup: (title: string, memberIds: string[]) => Promise<void>;
  findPeople: (query: string) => Promise<Contact[]>;
  setReplyTo: (id: string | null) => void;
  toggleOriginal: (id: string) => void;
  togglePin: (chatId: string) => void;
  toggleMute: (chatId: string) => void;
  sendMessage: (
    chatId: string,
    text: string,
    attachments?: Attachment[],
  ) => Promise<void>;
  sendFiles: (chatId: string, files: File[]) => Promise<void>;
  sendTyping: (chatId: string) => void;
  toggleTranslate: (chatId: string) => Promise<void>;
  translateMessage: (messageId: string) => Promise<void>;
  ensureLiveTranslation: (chatId: string) => Promise<void>;
  runDraftTool: (
    mode: "improve" | "translate" | "reply",
    text: string,
  ) => Promise<string | null>;
};

export type MessengerStore = State & Actions;

function upsertChat(chats: Chat[], next: Chat): Chat[] {
  const index = chats.findIndex((c) => c.id === next.id);
  const merged = index === -1 ? chats.concat(next) : chats.with(index, next);
  // Сверху тот, где последнее движение. Не по номеру сообщения: это счётчик
  // внутри чата, между чатами он несравним — переписка на пятьсот сообщений
  // всегда оказывалась бы выше вчерашней на три.
  return merged.sort((a, b) => {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
    return b.lastMessageAt - a.lastMessageAt;
  });
}

function summaryToChat(summary: ServerSummary, myId: string): Chat {
  const peer = summary.users.find((u) => u.id !== myId);
  const isGroup = summary.chat.type === "group";
  const title = isGroup
    ? summary.chat.title || "Группа"
    : (peer?.display_name ?? "Чат");

  return {
    id: summary.chat.id,
    kind: isGroup ? "group" : summary.users.length === 1 ? "saved" : "dm",
    title,
    peerId: peer?.id,
    memberIds: summary.members.map((m) => m.user_id).filter((id) => id !== myId),
    avatar: isGroup ? summary.chat.avatar_url : peer?.avatar_url,
    initials: initialsOf(title),
    pinned: summary.pinned ?? false,
    muted: summary.muted ?? false,
    unread: summary.unread_count,
    translateOn: false,
    lastMessageAt: summary.last_message
      ? new Date(summary.last_message.created_at).getTime()
      : Date.now(),
  };
}

export const useMessenger = create<MessengerStore>()(
  persist(
    (set, get) => ({
      me: null,
      contacts: {},
      chats: [],
      messages: [],
      cursors: {},
      outbox: [],

      uiLang: "ru",
      targetLang: "ru",
      notifications: true,
      status: "offline",

      selectedChatId: null,
      draftPeerId: null,
      folder: "all",
      search: "",
      sidebarView: "chats",
      replyToId: null,
      typingChatId: null,
      translatingChatId: null,
      draftBusy: false,
      revealedOriginal: {},
      translateError: null,

      // --- Подъём ---

      bootstrap: async () => {
        const session = api.session();
        if (!session) return;

        const me = (await api.me()) as unknown as { user: ServerUser };
        const user = me.user ?? (me as unknown as ServerUser);
        set({
          me: {
            id: user.id,
            name: user.display_name,
            about: user.phone ?? "",
            avatar: user.avatar_url ?? "",
            initials: initialsOf(user.display_name),
          },
        });

        ws.onEvent(handleEvent);
        ws.onStatus((status) => set({ status }));
        ws.onReady = async () => {
          await syncAll();
          await drainOutbox();
        };
        ws.connect();

        void refreshContacts();
      },

      signOut: async () => {
        ws.close();
        await api.logout();
        // Стираем и кэш: устройство может быть общим.
        localStorage.removeItem("tito-messenger");
        window.location.reload();
      },

      // --- Настройки интерфейса ---

      setUiLang: (uiLang) => set({ uiLang }),
      setTargetLang: (targetLang) => set({ targetLang }),
      setNotifications: (notifications) => set({ notifications }),
      setMe: (patch) => {
        const me = get().me;
        if (!me) return;
        set({ me: { ...me, ...patch } });
        if (patch.name) void api.updateMe(patch.name).catch(() => {});
      },
      setSearch: (search) => set({ search }),
      setFolder: (folder) => set({ folder }),
      setSidebarView: (sidebarView) => set({ sidebarView }),
      setReplyTo: (replyToId) => set({ replyToId }),
      toggleOriginal: (id) =>
        set((s) => ({
          revealedOriginal: { ...s.revealedOriginal, [id]: !s.revealedOriginal[id] },
        })),

      togglePin: (chatId) => {
        const chat = get().chats.find((c) => c.id === chatId);
        if (!chat) return;
        const pinned = !chat.pinned;
        set((s) => ({
          chats: upsertChat(
            s.chats.filter((c) => c.id !== chatId),
            { ...chat, pinned },
          ),
        }));
        // Закрепление — свойство аккаунта, а не вкладки: человек делает это
        // один раз, а не на каждом устройстве заново.
        ws.notify(Cmd.chatPin, { chat_id: chatId, pinned });
      },

      toggleMute: (chatId) => {
        const chat = get().chats.find((c) => c.id === chatId);
        if (!chat) return;
        const muted = !chat.muted;
        set((s) => ({
          chats: s.chats.map((c) => (c.id === chatId ? { ...c, muted } : c)),
        }));
        ws.notify(Cmd.chatMute, { chat_id: chatId, muted });
      },

      selectChat: (id) => {
        set((s) => ({
          selectedChatId: id,
          draftPeerId: null,
          replyToId: null,
          sidebarView: "chats",
          chats: id
            ? s.chats.map((c) => (c.id === id ? { ...c, unread: 0 } : c))
            : s.chats,
        }));
        if (!id) return;

        void loadHistory(id);
        markRead(id);
        void get().ensureLiveTranslation(id);
      },

      /// Открывает переписку с человеком.
      ///
      /// Если она уже была — открываем её, а не заводим черновик рядом:
      /// иначе у одного человека оказалось бы два места.
      startChatWith: (userId) => {
        const existing = get().chats.find(
          (c) => c.kind === "dm" && c.peerId === userId,
        );
        if (existing) {
          get().selectChat(existing.id);
          return;
        }
        set({
          draftPeerId: userId,
          selectedChatId: null,
          replyToId: null,
          sidebarView: "chats",
        });
      },

      createGroup: async (title, memberIds) => {
        const result = await ws.call(Cmd.chatCreate, {
          title: title.trim(),
          member_ids: memberIds,
        });
        // Сервер отвечает самим чатом, а не сводкой по нему: участников,
        // непрочитанного и последнего сообщения в ответе нет. Собирать
        // сводку руками значит выдумать её половину — проще спросить.
        const chat = result.chat as { id?: string } | undefined;
        if (!chat?.id) return;
        await syncAll();
        get().selectChat(chat.id);
      },

      /// Поиск человека, которого нет в книге контактов, — по номеру или
      /// имени. Книга заполняется тем, что синхронизировал телефон; в
      /// браузере её может не быть вовсе.
      findPeople: async (query) => {
        const q = query.trim();
        if (q.length < 2) return [];
        try {
          const found = (await api.searchUsers(q)) as ServerUser[];
          const mine = get().me?.id;
          return found
            .filter((u) => u.id !== mine)
            .map((u) => toContact(u, false));
        } catch {
          return [];
        }
      },

      // --- Отправка ---

      sendMessage: async (chatId, text, attachments) => {
        const trimmed = text.trim();
        // Пустое сообщение отправлять некуда, но картинка без подписи —
        // обычное дело, и её текст пустой.
        if (!trimmed && !attachments?.length) return;

        const me = get().me;
        if (!me) return;

        const chat = get().chats.find((c) => c.id === chatId);
        // Пустой chatId — переписка, которой ещё нет: сервер заведёт её сам
        // по собеседнику в первом же сообщении.
        const peerId = chat?.peerId ?? (chatId ? undefined : get().draftPeerId ?? undefined);
        if (!chatId && !peerId) return;

        const clientMsgId = crypto.randomUUID();
        const replyToId = get().replyToId ?? undefined;

        // Черновик кладём в ленту сразу: сообщение должно появиться на
        // экране раньше, чем уйдёт в сеть, иначе при плохой связи кажется,
        // что нажатие не сработало.
        const draft: Message = {
          id: clientMsgId,
          chatId,
          senderId: me.id,
          text: trimmed,
          createdAt: Date.now(),
          status: "sending",
          replyToId,
          attachments,
          seq: 0,
          clientMsgId,
        };

        set((s) => ({
          messages: [...s.messages, draft],
          replyToId: null,
          outbox: [
            ...s.outbox,
            {
              clientMsgId,
              chatId,
              peerId,
              text: trimmed,
              replyToId,
              attachmentIds: attachments?.map((a) => a.id),
            },
          ],
          chats: s.chats.map((c) =>
            c.id === chatId ? { ...c, lastMessageAt: draft.createdAt, unread: 0 } : c,
          ),
        }));

        await drainOutbox();
      },

      /// Отправляет файлы.
      ///
      /// Файл уходит ДО сообщения: так виден прогресс, а само сообщение
      /// отправляется одним кадром со списком номеров. Порядок обратный —
      /// сначала кадр, потом файлы — оставил бы сообщение без вложения,
      /// если загрузка не удалась.
      sendFiles: async (chatId, files) => {
        if (!files.length) return;
        set({ draftBusy: true });
        try {
          const uploaded: Attachment[] = [];
          for (const file of files) {
            const raw = (await api.upload(file)) as unknown as ServerAttachment;
            uploaded.push(toAttachment(raw));
          }
          await get().sendMessage(chatId, "", uploaded);
        } finally {
          set({ draftBusy: false });
        }
      },

      sendTyping: (chatId) => {
        // Чата может ещё не быть — переписка только начата. Сообщать «печатает»
        // некуда, да и сервер такой кадр отвергнет.
        if (!chatId) return;
        ws.notify(Cmd.typing, { chat_id: chatId });
      },

      // --- Перевод ---

      toggleTranslate: async (chatId) => {
        const chat = get().chats.find((c) => c.id === chatId);
        if (!chat) return;
        const turningOn = !chat.translateOn;
        set((s) => ({
          chats: s.chats.map((c) =>
            c.id === chatId ? { ...c, translateOn: turningOn } : c,
          ),
          translateError: null,
        }));
        if (turningOn) await get().ensureLiveTranslation(chatId);
      },

      ensureLiveTranslation: async (chatId) => {
        const chat = get().chats.find((c) => c.id === chatId);
        if (!chat?.translateOn) return;

        const me = get().me;
        const lang = get().targetLang;
        const pending = get()
          .messages.filter(
            (m) =>
              m.chatId === chatId &&
              m.senderId !== me?.id &&
              m.text &&
              !m.translations?.[lang],
          )
          .map((m) => ({ id: m.id, text: m.text }));
        if (pending.length === 0) return;

        set({ translatingChatId: chatId });
        try {
          const items = await api.translate(pending, lang);
          const map = new Map(items.map((it) => [it.id, it]));
          set((s) => ({
            messages: s.messages.map((m) => {
              const hit = map.get(m.id);
              if (!hit) return m;
              return {
                ...m,
                translations: {
                  ...m.translations,
                  [lang]: { text: hit.text, from: hit.from },
                },
              };
            }),
            translateError: null,
          }));
        } catch (error) {
          // Молча не переводить хуже, чем сказать почему: человек ждёт
          // перевода и не понимает, почему его нет.
          set({
            translateError:
              error instanceof Error ? error.message : "Перевод недоступен",
          });
        } finally {
          set({ translatingChatId: null });
        }
      },

      translateMessage: async (messageId) => {
        const message = get().messages.find((m) => m.id === messageId);
        if (!message) return;
        const lang = get().targetLang;

        if (message.translations?.[lang]) {
          set((s) => ({
            revealedOriginal: {
              ...s.revealedOriginal,
              [messageId]: !s.revealedOriginal[messageId],
            },
          }));
          return;
        }

        try {
          const [item] = await api.translate(
            [{ id: message.id, text: message.text }],
            lang,
          );
          if (!item) return;
          set((s) => ({
            messages: s.messages.map((m) =>
              m.id === messageId
                ? {
                    ...m,
                    translations: {
                      ...m.translations,
                      [lang]: { text: item.text, from: item.from },
                    },
                  }
                : m,
            ),
            translateError: null,
          }));
        } catch (error) {
          set({
            translateError:
              error instanceof Error ? error.message : "Перевод недоступен",
          });
        }
      },

      /// Правка черновика — та же машинка, что и перевод. Пока поставщик не
      /// подключён, возвращаем null: поле ввода оставит текст как есть.
      runDraftTool: async (mode, text) => {
        if (get().draftBusy || !text.trim()) return null;
        set({ draftBusy: true });
        try {
          if (mode !== "translate") return null;
          const [item] = await api.translate(
            [{ id: "draft", text }],
            get().targetLang,
          );
          return item?.text ?? null;
        } catch (error) {
          set({
            translateError:
              error instanceof Error ? error.message : "Перевод недоступен",
          });
          return null;
        } finally {
          set({ draftBusy: false });
        }
      },
    }),
    {
      name: "tito-messenger",
      // Кэш, а не источник правды: при расхождении побеждает сервер.
      partialize: (s) => ({
        me: s.me,
        contacts: s.contacts,
        chats: s.chats,
        messages: s.messages,
        cursors: s.cursors,
        outbox: s.outbox,
        uiLang: s.uiLang,
        targetLang: s.targetLang,
        notifications: s.notifications,
        selectedChatId: s.selectedChatId,
      }),
    },
  ),
);

// --- Работа с сервером ---

const set = useMessenger.setState;
const get = useMessenger.getState;

async function refreshContacts() {
  try {
    const list = (await api.contacts()) as ServerUser[];
    set((s) => ({
      contacts: {
        ...s.contacts,
        ...Object.fromEntries(list.map((u) => [u.id, toContact(u, false)])),
      },
    }));
  } catch {
    // Адресная книга не обязательна для переписки: без неё имена возьмутся
    // из самих чатов.
  }
}

/// Догоняет всё, что произошло, пока нас не было.
///
/// Курсоры уходят по каждому чату сразу: одним кадром вместо запроса на
/// каждый чат, иначе после недели офлайна это сотня запросов подряд.
async function syncAll() {
  const me = get().me;
  if (!me) return;

  try {
    const summaries = (await api.chats()) as unknown as ServerSummary[];
    const contacts: Record<string, Contact> = { ...get().contacts };
    let chats = get().chats;

    for (const summary of summaries) {
      for (const user of summary.users) {
        contacts[user.id] ??= toContact(user, false);
      }
      chats = upsertChat(
        chats.filter((c) => c.id !== summary.chat.id),
        {
          ...summaryToChat(summary, me.id),
          // Живой перевод — выбор человека, он переживает обновление списка.
          translateOn:
            chats.find((c) => c.id === summary.chat.id)?.translateOn ?? false,
        },
      );
    }
    set({ chats, contacts });

    const cursors = get().cursors;
    const result = await ws.call(Cmd.sync, {
      cursors: Object.fromEntries(
        chats.map((c) => [c.id, cursors[c.id] ?? 0]),
      ),
    });
    applySync(result);
  } catch {
    // Связь пропала посреди синхронизации — следующее подключение начнёт
    // с тех же курсоров, ничего не потеряется.
  }
}

function applySync(data: Record<string, unknown>) {
  const deltas = (data.chats as { chat_id: string; messages: ServerMessage[]; last_seq: number; truncated?: boolean }[]) ?? [];
  for (const delta of deltas) {
    for (const raw of delta.messages ?? []) mergeMessage(raw);
    // Курсор двигаем, только если чат приехал целиком: при truncated в
    // ленте дыра, и её надо дочитать историей.
    if (!delta.truncated) {
      set((s) => ({
        cursors: { ...s.cursors, [delta.chat_id]: delta.last_seq },
      }));
    }
  }
}

async function loadHistory(chatId: string) {
  const known = get().messages.filter((m) => m.chatId === chatId);
  if (known.length > 0) return;
  try {
    const list = (await api.history(chatId)) as unknown as ServerMessage[];
    for (const raw of list) mergeMessage(raw);
  } catch {
    // История подтянется при следующем открытии чата.
  }
}

/// Кладёт сообщение в ленту, заменяя свой черновик, а не дублируя его.
function mergeMessage(raw: ServerMessage) {
  const message = toMessage(raw);
  set((s) => {
    const index = s.messages.findIndex(
      (m) => m.id === message.id || m.clientMsgId === message.clientMsgId,
    );
    const messages =
      index === -1
        ? [...s.messages, message]
        : s.messages.with(index, { ...s.messages[index], ...message });
    messages.sort((a, b) => a.createdAt - b.createdAt);

    const cursor = Math.max(s.cursors[message.chatId] ?? 0, message.seq);
    return {
      messages,
      cursors: { ...s.cursors, [message.chatId]: cursor },
      chats: s.chats.map((c) =>
        c.id === message.chatId
          ? { ...c, lastMessageAt: Math.max(c.lastMessageAt, message.createdAt) }
          : c,
      ),
    };
  });
}

function markRead(chatId: string) {
  const last = get()
    .messages.filter((m) => m.chatId === chatId && m.seq > 0)
    .at(-1);
  if (!last) return;
  ws.notify(Cmd.read, { chat_id: chatId, up_to_seq: last.seq });
}

// --- Очередь отправки ---

let draining = false;
let drainAgain = false;

/// Разгребает очередь по одному, сохраняя порядок.
///
/// Вызов во время работы не теряется: он поднимает флаг, и цикл повторится
/// сразу после текущего прохода — иначе сообщение, написанное в момент
/// отправки предыдущего, залипало бы до следующего запуска приложения.
async function drainOutbox(): Promise<void> {
  if (draining) {
    drainAgain = true;
    return;
  }
  draining = true;
  try {
    do {
      drainAgain = false;
      while (get().outbox.length > 0 && ws.status === "online") {
        const item = get().outbox[0];
        if (!item) break;
        const sent = await trySend(item);
        if (!sent) break;
      }
    } while (drainAgain);
  } finally {
    draining = false;
  }
}

/// Возвращает true, если сообщение покинуло очередь.
///
/// Временная ошибка возвращает false и останавливает цикл: следующие
/// сообщения должны уйти после этого, а не раньше него.
async function trySend(item: Outgoing): Promise<boolean> {
  try {
    const result = await ws.call(Cmd.messageSend, {
      // Именно `|| undefined`: у переписки, которой ещё нет, chatId пустая
      // строка, а сервер читает это поле как UUID и на пустой строке
      // отказывает целому кадру. Сообщение при этом помечается «не ушло» —
      // выглядит как отказ по существу, хотя дело в одном лишнем поле.
      chat_id: item.chatId || undefined,
      peer_id: item.chatId ? undefined : item.peerId,
      text: item.text,
      client_msg_id: item.clientMsgId,
      reply_to_id: item.replyToId,
      attachment_ids: item.attachmentIds,
    });
    const raw = result.message as ServerMessage | undefined;
    if (raw) mergeMessage(raw);
    set((s) => ({
      outbox: s.outbox.filter((o) => o.clientMsgId !== item.clientMsgId),
    }));

    // Переписки не было — сервер завёл её первым сообщением и вернул номер.
    // Черновик в ленте лежит без чата; без этого он остался бы сиротой, а
    // экран — пустым при живом ответе собеседника.
    if (raw && !item.chatId) {
      set((s) => ({
        messages: s.messages.map((m) =>
          m.clientMsgId === item.clientMsgId ? { ...m, chatId: raw.chat_id } : m,
        ),
        selectedChatId: s.draftPeerId ? raw.chat_id : s.selectedChatId,
        draftPeerId: null,
      }));
      await syncAll();
    }
    return true;
  } catch (error) {
    if (error instanceof ProtocolError && error.retriable) return false;

    // Отказ по существу — выкинули из чата, чат удалён. Повторять
    // бессмысленно: пометим сообщение и оставим решение человеку.
    set((s) => ({
      outbox: s.outbox.filter((o) => o.clientMsgId !== item.clientMsgId),
      messages: s.messages.map((m) =>
        m.clientMsgId === item.clientMsgId ? { ...m, status: "failed" } : m,
      ),
    }));
    return true;
  }
}

// --- События сокета ---

function handleEvent(envelope: Envelope) {
  const data = envelope.d ?? {};

  switch (envelope.t) {
    case Ev.messageNew:
    case Ev.messageEdited:
    case Ev.messageDeleted: {
      const raw = data.message as ServerMessage | undefined;
      if (!raw) return;
      mergeMessage(raw);
      const state = get();
      if (raw.chat_id === state.selectedChatId) {
        markRead(raw.chat_id);
        void state.ensureLiveTranslation(raw.chat_id);
      } else if (raw.sender_id !== state.me?.id) {
        set((s) => ({
          chats: s.chats.map((c) =>
            c.id === raw.chat_id ? { ...c, unread: c.unread + 1 } : c,
          ),
        }));
      }
      return;
    }

    case Ev.chatUpdate: {
      const summary = data.chat as ServerSummary | undefined;
      const me = get().me;
      if (!summary || !me) return;
      if (data.gone === true) {
        set((s) => ({
          chats: s.chats.filter((c) => c.id !== summary.chat.id),
          messages: s.messages.filter((m) => m.chatId !== summary.chat.id),
        }));
        return;
      }
      set((s) => ({
        chats: upsertChat(
          s.chats.filter((c) => c.id !== summary.chat.id),
          summaryToChat(summary, me.id),
        ),
        contacts: {
          ...s.contacts,
          ...Object.fromEntries(
            summary.users.map((u) => [u.id, toContact(u, s.contacts[u.id]?.online ?? false)]),
          ),
        },
      }));
      if (summary.last_message) mergeMessage(summary.last_message);
      return;
    }

    case Ev.readUpdate: {
      const chatId = data.chat_id as string;
      const upTo = data.last_read_seq as number;
      const me = get().me;
      if (data.user_id === me?.id) return;
      set((s) => ({
        messages: s.messages.map((m) =>
          m.chatId === chatId && m.senderId === me?.id && m.seq > 0 && m.seq <= upTo
            ? { ...m, status: "read" }
            : m,
        ),
      }));
      return;
    }

    case Ev.typing: {
      const chatId = data.chat_id as string;
      set({ typingChatId: chatId });
      // Событие протухает за секунды: сервер не присылает «перестал
      // печатать», и без таймера индикатор висел бы вечно.
      window.setTimeout(() => {
        if (get().typingChatId === chatId) set({ typingChatId: null });
      }, 4000);
      return;
    }

    case Ev.presence: {
      const userId = data.user_id as string;
      const online = data.online === true;
      set((s) => {
        const contact = s.contacts[userId];
        if (!contact) return s;
        return {
          contacts: {
            ...s.contacts,
            [userId]: { ...contact, online, lastSeenAt: online ? undefined : Date.now() },
          },
        };
      });
      return;
    }
  }
}

// --- Вспомогательное для экранов ---

/// Пустой профиль на время загрузки.
///
/// Экраны под ним рендерятся только после `bootstrap`, поэтому настоящий
/// профиль там уже есть. Заглушка нужна ровно затем, чтобы в каждом из них
/// не стояла проверка на null, которая никогда не срабатывает и только
/// мешает читать разметку.
const LOADING_ME: Me = {
  id: "",
  name: "",
  about: "",
  avatar: "",
  initials: "",
};

export function useMe(): Me {
  return useMessenger((s) => s.me) ?? LOADING_ME;
}

// --- Подписи ---

export function chatTitle(chat: Chat, uiLang: UiLang) {
  if (chat.kind === "saved") return uiLang === "en" ? "Saved Messages" : "Избранное";
  return chat.title;
}

/// Чем подписано вложение в списке диалогов.
///
/// У картинки подписи нет вовсе, и строка «Вы:» оставалась пустой — будто
/// сообщение потерялось. Поэтому у сообщения без текста в списке стоит род
/// вложения.
const attachmentLabels: Record<UiLang, Record<AttachmentKind, string>> = {
  ru: { image: "Фото", video: "Видео", audio: "Аудио", file: "Файл" },
  en: { image: "Photo", video: "Video", audio: "Audio", file: "File" },
};

export function lastPreview(
  messages: Message[],
  chatId: string,
  meLabel: string,
): string {
  const me = get().me;
  const uiLang = get().uiLang;
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i];
    if (message?.chatId !== chatId) continue;
    if (message.deleted) return "Сообщение удалено";
    const prefix = message.senderId === me?.id ? `${meLabel}: ` : "";
    const attachment = message.attachments?.[0];
    const body = message.text.trim()
      ? message.text.replace(/\s+/g, " ")
      : attachment
        ? attachmentLabels[uiLang][attachment.kind]
        : "";
    return `${prefix}${body}`;
  }
  return "";
}

export { uid };
