-- Маяк: начальная схема.
--
-- Ключевые инварианты, на которых держится доставка:
--   1. chats.last_seq — монотонный счётчик изменений в чате. Номер выдаётся не
--      только новому сообщению, но и правке с удалением: иначе клиент,
--      который был офлайн, никогда бы не узнал об отредактированном тексте.
--      Сообщение хранит два номера: seq — позиция в ленте, updated_seq —
--      номер последнего изменения. Порядок в UI строится по seq,
--      синхронизация — по updated_seq.
--   2. UNIQUE (chat_id, sender_id, client_msg_id) — повторная отправка после
--      обрыва не создаёт дубль.

CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone         text        NOT NULL UNIQUE,
    username      text        UNIQUE,
    display_name  text        NOT NULL DEFAULT '',
    avatar_url    text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now()
);

-- Одна строка на установку приложения. Refresh-токен хранится хэшем и
-- ротируется при каждом обновлении, поэтому украденный токен живёт недолго.
CREATE TABLE devices (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform           text        NOT NULL DEFAULT 'unknown',
    name               text        NOT NULL DEFAULT '',
    push_token         text,
    refresh_token_hash bytea       NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    last_seen_at       timestamptz NOT NULL DEFAULT now(),
    revoked_at         timestamptz
);

CREATE INDEX devices_user_active_idx ON devices (user_id) WHERE revoked_at IS NULL;
CREATE INDEX devices_refresh_idx     ON devices (refresh_token_hash) WHERE revoked_at IS NULL;

-- Код подтверждения живёт до первой успешной проверки или до истечения срока.
CREATE TABLE auth_codes (
    phone      text PRIMARY KEY,
    code_hash  bytea       NOT NULL,
    attempts   int         NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL
);

CREATE TABLE chats (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    type        text        NOT NULL CHECK (type IN ('private', 'group')),
    title       text        NOT NULL DEFAULT '',
    avatar_url  text,
    -- Для личных чатов — отсортированная пара user_id через двоеточие.
    -- Не даёт создать два чата между одними и теми же людьми. У групп NULL,
    -- а Postgres не считает NULL нарушением уникальности.
    private_key text        UNIQUE,
    created_by  uuid        REFERENCES users(id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    last_seq    bigint      NOT NULL DEFAULT 0
);

CREATE TABLE chat_members (
    chat_id       uuid        NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id       uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role          text        NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at     timestamptz NOT NULL DEFAULT now(),
    last_read_seq bigint      NOT NULL DEFAULT 0,
    muted_until   timestamptz,
    PRIMARY KEY (chat_id, user_id)
);

CREATE INDEX chat_members_user_idx ON chat_members (user_id);

CREATE TABLE messages (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id       uuid        NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    seq           bigint      NOT NULL,
    updated_seq   bigint      NOT NULL,
    sender_id     uuid        REFERENCES users(id) ON DELETE SET NULL,
    text          text        NOT NULL DEFAULT '',
    reply_to_id   uuid        REFERENCES messages(id) ON DELETE SET NULL,
    client_msg_id uuid        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    edited_at     timestamptz,
    deleted_at    timestamptz,
    UNIQUE (chat_id, seq),
    UNIQUE (chat_id, sender_id, client_msg_id)
);

-- Страница истории листается по seq...
CREATE INDEX messages_chat_seq_idx ON messages (chat_id, seq DESC);
-- ...а дельта после реконнекта добирается по updated_seq.
CREATE INDEX messages_chat_updated_idx ON messages (chat_id, updated_seq);

CREATE TABLE attachments (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- NULL, пока файл загружен, но сообщение ещё не отправлено.
    message_id uuid        REFERENCES messages(id) ON DELETE CASCADE,
    owner_id   uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind       text        NOT NULL CHECK (kind IN ('image', 'video', 'audio', 'file')),
    object_key text        NOT NULL,
    file_name  text        NOT NULL DEFAULT '',
    mime       text        NOT NULL DEFAULT 'application/octet-stream',
    size       bigint      NOT NULL DEFAULT 0,
    width      int,
    height     int,
    duration   int,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX attachments_message_idx ON attachments (message_id);
CREATE INDEX attachments_orphan_idx  ON attachments (created_at) WHERE message_id IS NULL;

CREATE TABLE contacts (
    user_id         uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            text        NOT NULL DEFAULT '',
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, contact_user_id)
);
