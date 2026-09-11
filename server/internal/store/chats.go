package store

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
)

// privateKey строит детерминированный ключ личного чата.
//
// Пара отсортирована, поэтому «Аня пишет Боре» и «Боря пишет Ане» дают один
// и тот же ключ, а UNIQUE не даёт создать второй чат между теми же людьми.
func privateKey(a, b uuid.UUID) string {
	pair := []string{a.String(), b.String()}
	sort.Strings(pair)
	return pair[0] + ":" + pair[1]
}

const chatColumns = `id, type, title, COALESCE(avatar_url, ''), COALESCE(created_by, '00000000-0000-0000-0000-000000000000'::uuid), created_at, last_seq`

func scanChat(row pgx.Row) (domain.Chat, error) {
	var c domain.Chat
	err := row.Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedBy, &c.CreatedAt, &c.LastSeq)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Chat{}, ErrNotFound
	}
	if err != nil {
		return domain.Chat{}, fmt.Errorf("чтение чата: %w", err)
	}
	return c, nil
}

// EnsurePrivateChat возвращает личный чат двух людей, создавая его при первом
// сообщении. Отдельной кнопки «создать диалог» в мессенджере нет.
func (s *Store) EnsurePrivateChat(ctx context.Context, a, b uuid.UUID) (domain.Chat, error) {
	if a == b {
		// Чат с самим собой — это «Избранное», отдельная механика; пока нет.
		return domain.Chat{}, fmt.Errorf("%w: нельзя создать личный чат с самим собой", ErrConflict)
	}
	key := privateKey(a, b)

	var chat domain.Chat
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		// ON CONFLICT DO NOTHING не вернёт строку, если чат уже есть, —
		// тогда просто читаем существующий.
		row := tx.QueryRow(ctx, `
			INSERT INTO chats (type, private_key, created_by)
			VALUES ('private', $1, $2)
			ON CONFLICT (private_key) DO NOTHING
			RETURNING `+chatColumns, key, a)

		c, err := scanChat(row)
		if errors.Is(err, ErrNotFound) {
			chat, err = scanChat(tx.QueryRow(ctx, `SELECT `+chatColumns+` FROM chats WHERE private_key = $1`, key))
			return err
		}
		if err != nil {
			return err
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO chat_members (chat_id, user_id, role)
			VALUES ($1, $2, 'member'), ($1, $3, 'member')`, c.ID, a, b); err != nil {
			if isForeignKeyViolation(err) {
				return fmt.Errorf("%w: собеседник не существует", ErrNotFound)
			}
			return fmt.Errorf("добавление участников: %w", err)
		}
		chat = c
		return nil
	})
	return chat, err
}

func (s *Store) CreateGroup(ctx context.Context, owner uuid.UUID, title string, members []uuid.UUID) (domain.Chat, error) {
	var chat domain.Chat
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		c, err := scanChat(tx.QueryRow(ctx, `
			INSERT INTO chats (type, title, created_by)
			VALUES ('group', $1, $2)
			RETURNING `+chatColumns, title, owner))
		if err != nil {
			return err
		}

		rows := [][]any{{c.ID, owner, string(domain.RoleOwner)}}
		seen := map[uuid.UUID]bool{owner: true}
		for _, m := range members {
			if seen[m] {
				continue
			}
			seen[m] = true
			rows = append(rows, []any{c.ID, m, string(domain.RoleMember)})
		}

		_, err = tx.CopyFrom(ctx,
			pgx.Identifier{"chat_members"},
			[]string{"chat_id", "user_id", "role"},
			pgx.CopyFromRows(rows))
		if err != nil {
			if isForeignKeyViolation(err) {
				return fmt.Errorf("%w: среди участников есть несуществующий пользователь", ErrNotFound)
			}
			return fmt.Errorf("добавление участников: %w", err)
		}
		chat = c
		return nil
	})
	return chat, err
}

func (s *Store) ChatByID(ctx context.Context, chatID uuid.UUID) (domain.Chat, error) {
	return scanChat(s.pool.QueryRow(ctx, `SELECT `+chatColumns+` FROM chats WHERE id = $1`, chatID))
}

// Membership проверяет, что человек состоит в чате. Вызывается перед любой
// операцией с чатом — иначе по угаданному id можно читать чужую переписку.
func (s *Store) Membership(ctx context.Context, chatID, userID uuid.UUID) (domain.Member, error) {
	var m domain.Member
	err := s.pool.QueryRow(ctx, `
		SELECT chat_id, user_id, role, joined_at, last_read_seq
		FROM chat_members WHERE chat_id = $1 AND user_id = $2`, chatID, userID,
	).Scan(&m.ChatID, &m.UserID, &m.Role, &m.JoinedAt, &m.LastReadSeq)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Member{}, ErrForbidden
	}
	if err != nil {
		return domain.Member{}, fmt.Errorf("проверка участия: %w", err)
	}
	return m, nil
}

func (s *Store) ChatMembers(ctx context.Context, chatID uuid.UUID) ([]domain.Member, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT chat_id, user_id, role, joined_at, last_read_seq
		FROM chat_members WHERE chat_id = $1 ORDER BY joined_at`, chatID)
	if err != nil {
		return nil, fmt.Errorf("выборка участников: %w", err)
	}
	defer rows.Close()

	var out []domain.Member
	for rows.Next() {
		var m domain.Member
		if err := rows.Scan(&m.ChatID, &m.UserID, &m.Role, &m.JoinedAt, &m.LastReadSeq); err != nil {
			return nil, fmt.Errorf("чтение участника: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// MemberIDs — адресаты рассылки события. Отдельный лёгкий запрос, потому что
// на каждое сообщение тянуть полные строки участников незачем.
func (s *Store) MemberIDs(ctx context.Context, chatID uuid.UUID) ([]uuid.UUID, error) {
	rows, err := s.pool.Query(ctx, `SELECT user_id FROM chat_members WHERE chat_id = $1`, chatID)
	if err != nil {
		return nil, fmt.Errorf("выборка адресатов: %w", err)
	}
	defer rows.Close()

	var out []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("чтение адресата: %w", err)
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func (s *Store) AddMembers(ctx context.Context, chatID uuid.UUID, members []uuid.UUID) error {
	if len(members) == 0 {
		return nil
	}
	batch := &pgx.Batch{}
	for _, m := range members {
		batch.Queue(`
			INSERT INTO chat_members (chat_id, user_id, role)
			VALUES ($1, $2, 'member')
			ON CONFLICT (chat_id, user_id) DO NOTHING`, chatID, m)
	}
	if err := s.pool.SendBatch(ctx, batch).Close(); err != nil {
		if isForeignKeyViolation(err) {
			return fmt.Errorf("%w: пользователь не существует", ErrNotFound)
		}
		return fmt.Errorf("добавление участников: %w", err)
	}
	return nil
}

func (s *Store) RemoveMember(ctx context.Context, chatID, userID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM chat_members WHERE chat_id = $1 AND user_id = $2`, chatID, userID)
	if err != nil {
		return fmt.Errorf("удаление участника: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// MarkRead двигает курсор прочитанного только вперёд: сообщение, помеченное
// прочитанным, не должно становиться непрочитанным из-за приехавшего не в том
// порядке события.
func (s *Store) MarkRead(ctx context.Context, chatID, userID uuid.UUID, seq int64) (int64, bool, error) {
	var current int64
	err := s.pool.QueryRow(ctx, `
		UPDATE chat_members SET last_read_seq = GREATEST(last_read_seq, $3)
		WHERE chat_id = $1 AND user_id = $2
		RETURNING last_read_seq`, chatID, userID, seq).Scan(&current)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, false, ErrForbidden
	}
	if err != nil {
		return 0, false, fmt.Errorf("отметка прочитанного: %w", err)
	}
	return current, current == seq, nil
}

// ChatPartners — все, с кем человек состоит хотя бы в одном чате.
// Это адресаты его presence: только им интересно, в сети он или нет.
func (s *Store) ChatPartners(ctx context.Context, userID uuid.UUID, limit int) ([]uuid.UUID, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT DISTINCT other.user_id
		FROM chat_members mine
		JOIN chat_members other ON other.chat_id = mine.chat_id AND other.user_id <> mine.user_id
		WHERE mine.user_id = $1
		LIMIT $2`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("выборка собеседников: %w", err)
	}
	defer rows.Close()

	var out []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("чтение собеседника: %w", err)
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// SetPinned закрепляет чат для одного участника.
//
// Проверка членства встроена в условие: не участник просто не найдёт строку,
// и отдельный запрос «а можно ли» не нужен.
func (s *Store) SetPinned(ctx context.Context, chatID, userID uuid.UUID, pinned bool) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE chat_members SET pinned = $3
		WHERE chat_id = $1 AND user_id = $2`, chatID, userID, pinned)
	if err != nil {
		return fmt.Errorf("закрепление чата: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrForbidden
	}
	return nil
}

// SetMuted выключает звук чата до указанного момента.
//
// Со сроком, а не навсегда: «выключить на час» просят чаще, а вечное
// молчание человек потом не может объяснить и ищет, где же он его включил.
// Нулевой срок означает «звук вернуть».
func (s *Store) SetMuted(ctx context.Context, chatID, userID uuid.UUID, until time.Time) error {
	var value *time.Time
	if !until.IsZero() {
		value = &until
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE chat_members SET muted_until = $3
		WHERE chat_id = $1 AND user_id = $2`, chatID, userID, value)
	if err != nil {
		return fmt.Errorf("беззвучный режим: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrForbidden
	}
	return nil
}
