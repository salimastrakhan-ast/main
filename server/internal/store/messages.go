package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
)

// errDuplicate — внутренний сигнал «такое сообщение уже есть».
// Возврат его из транзакции откатывает выданный номер, поэтому дырок в
// нумерации после повторной отправки не остаётся.
var errDuplicate = errors.New("сообщение уже существует")

const messageColumns = `id, chat_id, seq, updated_seq, COALESCE(sender_id, '00000000-0000-0000-0000-000000000000'::uuid),
	text, reply_to_id, client_msg_id, created_at, edited_at, deleted_at`

type scannedMessage struct {
	domain.Message
	UpdatedSeq int64
}

func scanMessage(row pgx.Row) (scannedMessage, error) {
	var m scannedMessage
	err := row.Scan(&m.ID, &m.ChatID, &m.Seq, &m.UpdatedSeq, &m.SenderID,
		&m.Text, &m.ReplyToID, &m.ClientMsgID, &m.CreatedAt, &m.EditedAt, &m.DeletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return scannedMessage{}, ErrNotFound
	}
	if err != nil {
		return scannedMessage{}, fmt.Errorf("чтение сообщения: %w", err)
	}
	return m, nil
}

type NewMessage struct {
	ChatID        uuid.UUID
	SenderID      uuid.UUID
	Text          string
	ReplyToID     *uuid.UUID
	ClientMsgID   uuid.UUID
	AttachmentIDs []uuid.UUID
}

// SendMessage кладёт сообщение в чат и возвращает его вместе с признаком
// «создано впервые».
//
// Вся работа идёт в одной транзакции:
//   - проверка участия — чтобы между проверкой и вставкой человека не успели
//     выкинуть из чата;
//   - UPDATE ... RETURNING на строке чата выдаёт следующий номер и заодно
//     сериализует параллельные отправки в этот чат;
//   - вставка с ON CONFLICT DO NOTHING ловит повтор.
//
// Повторная отправка с тем же client_msg_id возвращает уже лежащее в базе
// сообщение, а не создаёт второе: клиент ретраит при каждом обрыве связи.
func (s *Store) SendMessage(ctx context.Context, in NewMessage) (domain.Message, bool, error) {
	var msg scannedMessage

	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var exists bool
		if err := tx.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM chat_members WHERE chat_id = $1 AND user_id = $2)`,
			in.ChatID, in.SenderID).Scan(&exists); err != nil {
			return fmt.Errorf("проверка участия: %w", err)
		}
		if !exists {
			return ErrForbidden
		}

		seq, err := nextSeq(ctx, tx, in.ChatID)
		if err != nil {
			return err
		}

		row := tx.QueryRow(ctx, `
			INSERT INTO messages (chat_id, seq, updated_seq, sender_id, text, reply_to_id, client_msg_id)
			VALUES ($1, $2, $2, $3, $4, $5, $6)
			ON CONFLICT (chat_id, sender_id, client_msg_id) DO NOTHING
			RETURNING `+messageColumns,
			in.ChatID, seq, in.SenderID, in.Text, in.ReplyToID, in.ClientMsgID)

		msg, err = scanMessage(row)
		if errors.Is(err, ErrNotFound) {
			return errDuplicate
		}
		if err != nil {
			return err
		}

		return bindAttachments(ctx, tx, msg.ID, in.SenderID, in.AttachmentIDs)
	})

	switch {
	case errors.Is(err, errDuplicate):
		existing, err := s.messageByClientID(ctx, in.ChatID, in.SenderID, in.ClientMsgID)
		return existing, false, err
	case err != nil:
		return domain.Message{}, false, err
	}

	msg.Message.Attachments, err = s.attachmentsFor(ctx, []uuid.UUID{msg.ID})
	if err != nil {
		return domain.Message{}, false, err
	}
	return msg.Message, true, nil
}

// nextSeq выдаёт следующий номер изменения в чате.
//
// Номер получают и новое сообщение, и правка, и удаление — один счётчик на
// все изменения. Клиент хранит его как курсор и после обрыва связи узнаёт не
// только о пропущенных сообщениях, но и о том, что кто-то отредактировал
// старое.
func nextSeq(ctx context.Context, tx pgx.Tx, chatID uuid.UUID) (int64, error) {
	var seq int64
	err := tx.QueryRow(ctx,
		`UPDATE chats SET last_seq = last_seq + 1 WHERE id = $1 RETURNING last_seq`, chatID).Scan(&seq)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrNotFound
	}
	if err != nil {
		return 0, fmt.Errorf("выделение номера: %w", err)
	}
	return seq, nil
}

func (s *Store) messageByClientID(ctx context.Context, chatID, senderID, clientMsgID uuid.UUID) (domain.Message, error) {
	m, err := scanMessage(s.pool.QueryRow(ctx, `
		SELECT `+messageColumns+` FROM messages
		WHERE chat_id = $1 AND sender_id = $2 AND client_msg_id = $3`, chatID, senderID, clientMsgID))
	if err != nil {
		return domain.Message{}, err
	}
	m.Message.Attachments, err = s.attachmentsFor(ctx, []uuid.UUID{m.ID})
	return m.Message, err
}

func (s *Store) MessageByID(ctx context.Context, chatID, messageID uuid.UUID) (domain.Message, error) {
	m, err := scanMessage(s.pool.QueryRow(ctx,
		`SELECT `+messageColumns+` FROM messages WHERE chat_id = $1 AND id = $2`, chatID, messageID))
	if err != nil {
		return domain.Message{}, err
	}
	m.Message.Attachments, err = s.attachmentsFor(ctx, []uuid.UUID{m.ID})
	return m.Message, err
}

// EditMessage меняет текст и выдаёт правке новый номер изменения, чтобы о ней
// узнали клиенты, которых в этот момент не было в сети.
func (s *Store) EditMessage(ctx context.Context, chatID, messageID, editorID uuid.UUID, text string) (domain.Message, error) {
	var msg scannedMessage
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		seq, err := nextSeq(ctx, tx, chatID)
		if err != nil {
			return err
		}
		row := tx.QueryRow(ctx, `
			UPDATE messages SET text = $4, edited_at = now(), updated_seq = $5
			WHERE chat_id = $1 AND id = $2 AND sender_id = $3 AND deleted_at IS NULL
			RETURNING `+messageColumns, chatID, messageID, editorID, text, seq)

		msg, err = scanMessage(row)
		if errors.Is(err, ErrNotFound) {
			// Либо сообщения нет, либо оно чужое — не различаем в ответе,
			// чтобы по коду ошибки нельзя было проверять существование чужих
			// сообщений.
			return ErrForbidden
		}
		return err
	})
	if err != nil {
		return domain.Message{}, err
	}
	msg.Message.Attachments, err = s.attachmentsFor(ctx, []uuid.UUID{msg.ID})
	return msg.Message, err
}

// DeleteMessage помечает сообщение удалённым и стирает текст.
//
// Строка остаётся, потому что на неё могут ссылаться ответы, а её номер
// держит порядок ленты. Удалять может автор или админ группы.
func (s *Store) DeleteMessage(ctx context.Context, chatID, messageID, actorID uuid.UUID) (domain.Message, error) {
	var msg scannedMessage
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var role domain.Role
		if err := tx.QueryRow(ctx,
			`SELECT role FROM chat_members WHERE chat_id = $1 AND user_id = $2`,
			chatID, actorID).Scan(&role); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrForbidden
			}
			return fmt.Errorf("проверка прав: %w", err)
		}
		canModerate := role == domain.RoleOwner || role == domain.RoleAdmin

		seq, err := nextSeq(ctx, tx, chatID)
		if err != nil {
			return err
		}
		row := tx.QueryRow(ctx, `
			UPDATE messages SET deleted_at = now(), text = '', updated_seq = $4
			WHERE chat_id = $1 AND id = $2 AND deleted_at IS NULL
			  AND (sender_id = $3 OR $5)
			RETURNING `+messageColumns, chatID, messageID, actorID, seq, canModerate)

		msg, err = scanMessage(row)
		if errors.Is(err, ErrNotFound) {
			return ErrForbidden
		}
		return err
	})
	if err != nil {
		return domain.Message{}, err
	}
	return msg.Message, nil
}

// History отдаёт страницу ленты вверх от beforeSeq. beforeSeq == 0 — с конца.
func (s *Store) History(ctx context.Context, chatID uuid.UUID, beforeSeq int64, limit int) ([]domain.Message, error) {
	if beforeSeq <= 0 {
		beforeSeq = int64(1) << 62
	}
	rows, err := s.pool.Query(ctx, `
		SELECT `+messageColumns+` FROM messages
		WHERE chat_id = $1 AND seq < $2
		ORDER BY seq DESC
		LIMIT $3`, chatID, beforeSeq, limit)
	if err != nil {
		return nil, fmt.Errorf("выборка истории: %w", err)
	}
	return s.collectMessages(ctx, rows, true)
}

// MessagesSince отдаёт то, что клиент пропустил в чате, пока был офлайн.
//
// Выборка идёт по updated_seq, поэтому сюда попадают и новые сообщения, и
// правки со стиранием старых. Второе возвращаемое значение — признак того,
// что пропущено больше лимита и остальное надо дочитать через историю.
func (s *Store) MessagesSince(ctx context.Context, chatID uuid.UUID, sinceSeq int64, limit int) ([]domain.Message, bool, error) {
	// Берём на одну строку больше лимита: если она пришла, значит пропущено
	// больше, чем мы готовы отдать одним куском.
	rows, err := s.pool.Query(ctx, `
		SELECT `+messageColumns+` FROM messages
		WHERE chat_id = $1 AND updated_seq > $2
		ORDER BY updated_seq
		LIMIT $3`, chatID, sinceSeq, limit+1)
	if err != nil {
		return nil, false, fmt.Errorf("выборка дельты: %w", err)
	}
	msgs, err := s.collectMessages(ctx, rows, false)
	if err != nil {
		return nil, false, err
	}
	if len(msgs) > limit {
		return msgs[:limit], true, nil
	}
	return msgs, false, nil
}

func (s *Store) collectMessages(ctx context.Context, rows pgx.Rows, reverse bool) ([]domain.Message, error) {
	defer rows.Close()

	var out []domain.Message
	var ids []uuid.UUID
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m.Message)
		ids = append(ids, m.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("чтение сообщений: %w", err)
	}
	if reverse {
		for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
			out[i], out[j] = out[j], out[i]
		}
	}

	// Вложения одним запросом на всю страницу, а не по запросу на сообщение.
	byMessage, err := s.attachmentsByMessage(ctx, ids)
	if err != nil {
		return nil, err
	}
	for i := range out {
		out[i].Attachments = byMessage[out[i].ID]
	}
	return out, nil
}

// ChatSummaries собирает список диалогов: чаты, участники, последнее
// сообщение и счётчик непрочитанного.
func (s *Store) ChatSummaries(ctx context.Context, userID uuid.UUID) ([]domain.ChatSummary, error) {
	return s.chatSummaries(ctx, userID, nil)
}

// ChatSummary — то же самое про один чат. Нужен, когда о появлении или
// изменении чата надо рассказать каждому участнику: непрочитанное и курсор
// чтения у всех свои.
func (s *Store) ChatSummary(ctx context.Context, chatID, userID uuid.UUID) (domain.ChatSummary, error) {
	list, err := s.chatSummaries(ctx, userID, []uuid.UUID{chatID})
	if err != nil {
		return domain.ChatSummary{}, err
	}
	if len(list) == 0 {
		return domain.ChatSummary{}, ErrNotFound
	}
	return list[0], nil
}

// chatSummaries: only == nil — все чаты пользователя, иначе только указанные.
func (s *Store) chatSummaries(ctx context.Context, userID uuid.UUID, only []uuid.UUID) ([]domain.ChatSummary, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT c.id, c.type, c.title, COALESCE(c.avatar_url, ''),
		       COALESCE(c.created_by, '00000000-0000-0000-0000-000000000000'::uuid),
		       c.created_at, c.last_seq,
		       me.last_read_seq,
		       (SELECT count(*) FROM messages m
		         WHERE m.chat_id = c.id AND m.seq > me.last_read_seq
		           AND m.sender_id <> $1 AND m.deleted_at IS NULL) AS unread,
		       me.pinned,
		       me.muted_until IS NOT NULL AND me.muted_until > now() AS muted
		FROM chat_members me
		JOIN chats c ON c.id = me.chat_id
		WHERE me.user_id = $1 AND ($2::uuid[] IS NULL OR c.id = ANY($2))
		ORDER BY me.pinned DESC, c.last_seq DESC`, userID, only)
	if err != nil {
		return nil, fmt.Errorf("выборка диалогов: %w", err)
	}
	defer rows.Close()

	var summaries []domain.ChatSummary
	var chatIDs []uuid.UUID
	for rows.Next() {
		var summary domain.ChatSummary
		c := &summary.Chat
		if err := rows.Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedBy,
			&c.CreatedAt, &c.LastSeq, &summary.LastReadSeq, &summary.UnreadCount,
			&summary.Pinned, &summary.Muted); err != nil {
			return nil, fmt.Errorf("чтение диалога: %w", err)
		}
		summaries = append(summaries, summary)
		chatIDs = append(chatIDs, c.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("чтение диалогов: %w", err)
	}
	if len(summaries) == 0 {
		return nil, nil
	}

	members, err := s.membersByChat(ctx, chatIDs)
	if err != nil {
		return nil, err
	}
	last, err := s.lastMessages(ctx, chatIDs)
	if err != nil {
		return nil, err
	}

	// Профили всех участников — одним запросом, чтобы клиент мог нарисовать
	// список диалогов без похода за каждым собеседником отдельно.
	userSet := map[uuid.UUID]bool{}
	for _, ms := range members {
		for _, m := range ms {
			userSet[m.UserID] = true
		}
	}
	userIDs := make([]uuid.UUID, 0, len(userSet))
	for id := range userSet {
		userIDs = append(userIDs, id)
	}
	users, err := s.UsersByIDs(ctx, userIDs)
	if err != nil {
		return nil, err
	}
	byID := make(map[uuid.UUID]domain.User, len(users))
	for _, u := range users {
		byID[u.ID] = u.Public()
	}

	for i := range summaries {
		id := summaries[i].Chat.ID
		summaries[i].Members = members[id]
		if msg, ok := last[id]; ok {
			m := msg
			summaries[i].LastMessage = &m
		}
		for _, m := range members[id] {
			if u, ok := byID[m.UserID]; ok {
				summaries[i].Users = append(summaries[i].Users, u)
			}
		}
	}
	return summaries, nil
}

func (s *Store) membersByChat(ctx context.Context, chatIDs []uuid.UUID) (map[uuid.UUID][]domain.Member, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT chat_id, user_id, role, joined_at, last_read_seq
		FROM chat_members WHERE chat_id = ANY($1) ORDER BY joined_at`, chatIDs)
	if err != nil {
		return nil, fmt.Errorf("выборка участников: %w", err)
	}
	defer rows.Close()

	out := make(map[uuid.UUID][]domain.Member)
	for rows.Next() {
		var m domain.Member
		if err := rows.Scan(&m.ChatID, &m.UserID, &m.Role, &m.JoinedAt, &m.LastReadSeq); err != nil {
			return nil, fmt.Errorf("чтение участника: %w", err)
		}
		out[m.ChatID] = append(out[m.ChatID], m)
	}
	return out, rows.Err()
}

// lastMessages — по последнему сообщению на чат. DISTINCT ON — расширение
// Postgres, которое делает это одним проходом по индексу (chat_id, seq DESC).
func (s *Store) lastMessages(ctx context.Context, chatIDs []uuid.UUID) (map[uuid.UUID]domain.Message, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT DISTINCT ON (chat_id) `+messageColumns+`
		FROM messages
		WHERE chat_id = ANY($1)
		ORDER BY chat_id, seq DESC`, chatIDs)
	if err != nil {
		return nil, fmt.Errorf("выборка последних сообщений: %w", err)
	}
	defer rows.Close()

	out := make(map[uuid.UUID]domain.Message)
	var ids []uuid.UUID
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		out[m.ChatID] = m.Message
		ids = append(ids, m.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("чтение последних сообщений: %w", err)
	}

	byMessage, err := s.attachmentsByMessage(ctx, ids)
	if err != nil {
		return nil, err
	}
	for chatID, m := range out {
		m.Attachments = byMessage[m.ID]
		out[chatID] = m
	}
	return out, nil
}

// UnreadCount — сколько чужих непрочитанных сообщений в чате. Нужен для
// бейджа в пуше.
func (s *Store) UnreadCount(ctx context.Context, chatID, userID uuid.UUID) (int64, error) {
	var n int64
	err := s.pool.QueryRow(ctx, `
		SELECT count(*) FROM messages m
		JOIN chat_members me ON me.chat_id = m.chat_id AND me.user_id = $2
		WHERE m.chat_id = $1 AND m.seq > me.last_read_seq
		  AND m.sender_id <> $2 AND m.deleted_at IS NULL`, chatID, userID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("подсчёт непрочитанного: %w", err)
	}
	return n, nil
}
