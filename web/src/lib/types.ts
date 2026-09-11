export type UiLang = "ru" | "en";

export type TargetLang = "ru" | "en" | "es" | "de" | "zh" | "tr" | "ar";

export type ChatKind = "ai" | "dm" | "group" | "saved";

export type FolderId = "all" | "personal" | "groups" | "ai";

export type SidebarView = "chats" | "settings" | "new";

export type Gender = "f" | "m";

/// «failed» — сервер отказал навсегда: повторять бессмысленно,
/// нужно решение человека.
export type MessageStatus = "sending" | "sent" | "read" | "failed";

export type Contact = {
  id: string;
  name: string;
  about?: string;
  avatar?: string;
  initials: string;
  online?: boolean;
  lastSeenAt?: number;
  gender?: Gender;
};

export type Chat = {
  id: string;
  kind: ChatKind;
  title: string;
  titleKey?: "saved" | "ai";
  peerId?: string;
  memberIds?: string[];
  avatar?: string;
  initials: string;
  pinned: boolean;
  muted: boolean;
  unread: number;
  translateOn: boolean;
  lastMessageAt: number;
};

export type Message = {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  createdAt: number;
  status: MessageStatus;
  replyToId?: string;
  translations?: Partial<Record<TargetLang, { text: string; from: string }>>;

  /// Номер в чате. Ноль у неотправленных: настоящий выдаёт сервер.
  seq: number;

  /// Ключ идемпотентности. По нему ответ сервера заменяет наш черновик, а
  /// не ложится рядом с ним второй строкой.
  clientMsgId: string;

  deleted?: boolean;
};

export type Me = {
  id: string;
  name: string;
  about: string;
  avatar: string;
  initials: string;
};
