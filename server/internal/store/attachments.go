package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
)

const attachmentColumns = `id, kind, object_key, file_name, mime, size, width, height, duration`

type NewAttachment struct {
	OwnerID   uuid.UUID
	Kind      domain.AttachmentKind
	ObjectKey string
	FileName  string
	Mime      string
	Size      int64
	Width     *int
	Height    *int
	Duration  *int
}

// CreateAttachment регистрирует загруженный файл до того, как отправлено
// сообщение. Пока message_id пуст, вложение считается черновиком.
func (s *Store) CreateAttachment(ctx context.Context, in NewAttachment) (domain.Attachment, error) {
	var a domain.Attachment
	err := s.pool.QueryRow(ctx, `
		INSERT INTO attachments (owner_id, kind, object_key, file_name, mime, size, width, height, duration)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING `+attachmentColumns,
		in.OwnerID, in.Kind, in.ObjectKey, in.FileName, in.Mime, in.Size, in.Width, in.Height, in.Duration,
	).Scan(&a.ID, &a.Kind, &a.ObjectKey, &a.FileName, &a.Mime, &a.Size, &a.Width, &a.Height, &a.Duration)
	if err != nil {
		return domain.Attachment{}, fmt.Errorf("регистрация вложения: %w", err)
	}
	return a, nil
}

// bindAttachments привязывает черновики вложений к отправленному сообщению.
//
// Условие owner_id и message_id IS NULL защищает от подстановки чужого файла:
// по угаданному id прицепить чужое вложение к своему сообщению не выйдет.
func bindAttachments(ctx context.Context, tx pgx.Tx, messageID, ownerID uuid.UUID, ids []uuid.UUID) error {
	if len(ids) == 0 {
		return nil
	}
	tag, err := tx.Exec(ctx, `
		UPDATE attachments SET message_id = $1
		WHERE id = ANY($2) AND owner_id = $3 AND message_id IS NULL`, messageID, ids, ownerID)
	if err != nil {
		return fmt.Errorf("привязка вложений: %w", err)
	}
	if int(tag.RowsAffected()) != len(ids) {
		return fmt.Errorf("%w: вложение не найдено или уже использовано", ErrForbidden)
	}
	return nil
}

func (s *Store) attachmentsFor(ctx context.Context, messageIDs []uuid.UUID) ([]domain.Attachment, error) {
	byMessage, err := s.attachmentsByMessage(ctx, messageIDs)
	if err != nil || len(messageIDs) == 0 {
		return nil, err
	}
	return byMessage[messageIDs[0]], nil
}

func (s *Store) attachmentsByMessage(ctx context.Context, messageIDs []uuid.UUID) (map[uuid.UUID][]domain.Attachment, error) {
	if len(messageIDs) == 0 {
		return nil, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT message_id, `+attachmentColumns+`
		FROM attachments WHERE message_id = ANY($1) ORDER BY created_at`, messageIDs)
	if err != nil {
		return nil, fmt.Errorf("выборка вложений: %w", err)
	}
	defer rows.Close()

	out := make(map[uuid.UUID][]domain.Attachment)
	for rows.Next() {
		var messageID uuid.UUID
		var a domain.Attachment
		if err := rows.Scan(&messageID, &a.ID, &a.Kind, &a.ObjectKey, &a.FileName,
			&a.Mime, &a.Size, &a.Width, &a.Height, &a.Duration); err != nil {
			return nil, fmt.Errorf("чтение вложения: %w", err)
		}
		out[messageID] = append(out[messageID], a)
	}
	return out, rows.Err()
}

// AttachmentOwned проверяет, что вложение принадлежит человеку и ещё не
// привязано к сообщению.
func (s *Store) AttachmentOwned(ctx context.Context, id, ownerID uuid.UUID) (domain.Attachment, error) {
	var a domain.Attachment
	err := s.pool.QueryRow(ctx, `
		SELECT `+attachmentColumns+` FROM attachments
		WHERE id = $1 AND owner_id = $2`, id, ownerID,
	).Scan(&a.ID, &a.Kind, &a.ObjectKey, &a.FileName, &a.Mime, &a.Size, &a.Width, &a.Height, &a.Duration)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Attachment{}, ErrNotFound
	}
	if err != nil {
		return domain.Attachment{}, fmt.Errorf("чтение вложения: %w", err)
	}
	return a, nil
}
