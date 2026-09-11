package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
)

const userColumns = `id, phone, COALESCE(username, ''), display_name, COALESCE(avatar_url, ''), COALESCE(avatar_key, ''), created_at, last_seen_at`

func scanUser(row pgx.Row) (domain.User, error) {
	var u domain.User
	err := row.Scan(&u.ID, &u.Phone, &u.Username, &u.DisplayName, &u.AvatarURL, &u.AvatarKey,
		&u.CreatedAt, &u.LastSeenAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, ErrNotFound
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("чтение пользователя: %w", err)
	}
	return u, nil
}

// EnsureUserByPhone возвращает пользователя с этим телефоном, создавая его при
// первом входе. Регистрации как отдельного шага нет — как в Телеграме.
func (s *Store) EnsureUserByPhone(ctx context.Context, phone string) (domain.User, error) {
	row := s.pool.QueryRow(ctx, `
		INSERT INTO users (phone, display_name)
		VALUES ($1, $2)
		ON CONFLICT (phone) DO UPDATE SET last_seen_at = now()
		RETURNING `+userColumns, phone, defaultDisplayName(phone))
	return scanUser(row)
}

// defaultDisplayName прячет середину номера: пока человек не заполнил профиль,
// его имя видят собеседники, и светить весь номер незачем.
func defaultDisplayName(phone string) string {
	if len(phone) < 6 {
		return phone
	}
	return phone[:len(phone)-7] + "***" + phone[len(phone)-4:]
}

func (s *Store) UserByID(ctx context.Context, id uuid.UUID) (domain.User, error) {
	return scanUser(s.pool.QueryRow(ctx, `SELECT `+userColumns+` FROM users WHERE id = $1`, id))
}

func (s *Store) UserByPhone(ctx context.Context, phone string) (domain.User, error) {
	return scanUser(s.pool.QueryRow(ctx, `SELECT `+userColumns+` FROM users WHERE phone = $1`, phone))
}

func (s *Store) UsersByIDs(ctx context.Context, ids []uuid.UUID) ([]domain.User, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT `+userColumns+` FROM users WHERE id = ANY($1)`, ids)
	if err != nil {
		return nil, fmt.Errorf("выборка пользователей: %w", err)
	}
	defer rows.Close()

	var out []domain.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// UsersByPhones — синхронизация адресной книги: клиент присылает номера,
// сервер отвечает теми, кто уже зарегистрирован.
func (s *Store) UsersByPhones(ctx context.Context, phones []string) ([]domain.User, error) {
	if len(phones) == 0 {
		return nil, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT `+userColumns+` FROM users WHERE phone = ANY($1)`, phones)
	if err != nil {
		return nil, fmt.Errorf("выборка по телефонам: %w", err)
	}
	defer rows.Close()

	var out []domain.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

type UserPatch struct {
	DisplayName *string
	Username    *string
	AvatarURL   *string

	// AvatarKey: пустая строка снимает аватар. Поэтому COALESCE здесь не
	// годится — он не отличит «не меняли» от «убрали».
	AvatarKey *string
}

func (s *Store) UpdateUser(ctx context.Context, id uuid.UUID, p UserPatch) (domain.User, error) {
	row := s.pool.QueryRow(ctx, `
		UPDATE users SET
			display_name = COALESCE($2, display_name),
			username     = COALESCE($3, username),
			avatar_url   = COALESCE($4, avatar_url),
			avatar_key   = CASE
				WHEN $5::text IS NULL THEN avatar_key
				WHEN $5 = '' THEN NULL
				ELSE $5
			END
		WHERE id = $1
		RETURNING `+userColumns, id, p.DisplayName, p.Username, p.AvatarURL, p.AvatarKey)

	u, err := scanUser(row)
	if isUniqueViolation(err) {
		return domain.User{}, ErrConflict
	}
	return u, err
}

func (s *Store) TouchUser(ctx context.Context, id uuid.UUID) error {
	_, err := s.pool.Exec(ctx, `UPDATE users SET last_seen_at = now() WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("обновление last_seen_at: %w", err)
	}
	return nil
}

func (s *Store) SearchUsers(ctx context.Context, query string, limit int) ([]domain.User, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT `+userColumns+`
		FROM users
		WHERE username ILIKE $1 OR display_name ILIKE $1
		ORDER BY display_name
		LIMIT $2`, "%"+query+"%", limit)
	if err != nil {
		return nil, fmt.Errorf("поиск пользователей: %w", err)
	}
	defer rows.Close()

	var out []domain.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// --- Контакты ---

func (s *Store) UpsertContacts(ctx context.Context, userID uuid.UUID, contacts map[uuid.UUID]string) error {
	if len(contacts) == 0 {
		return nil
	}
	batch := &pgx.Batch{}
	for contactID, name := range contacts {
		if contactID == userID {
			continue
		}
		batch.Queue(`
			INSERT INTO contacts (user_id, contact_user_id, name)
			VALUES ($1, $2, $3)
			ON CONFLICT (user_id, contact_user_id) DO UPDATE SET name = EXCLUDED.name`,
			userID, contactID, name)
	}
	if batch.Len() == 0 {
		return nil
	}
	if err := s.pool.SendBatch(ctx, batch).Close(); err != nil {
		return fmt.Errorf("сохранение контактов: %w", err)
	}
	return nil
}

func (s *Store) Contacts(ctx context.Context, userID uuid.UUID) ([]domain.User, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT u.id, u.phone, COALESCE(u.username, ''),
		       -- Имя из адресной книги важнее того, что человек поставил
		       -- себе сам: в списке контактов ищут по своей подписи.
		       COALESCE(NULLIF(c.name, ''), u.display_name),
		       COALESCE(u.avatar_url, ''), COALESCE(u.avatar_key, ''),
		       u.created_at, u.last_seen_at
		FROM contacts c
		JOIN users u ON u.id = c.contact_user_id
		WHERE c.user_id = $1
		ORDER BY 4`, userID)
	if err != nil {
		return nil, fmt.Errorf("выборка контактов: %w", err)
	}
	defer rows.Close()

	var out []domain.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// --- Устройства ---

func (s *Store) CreateDevice(ctx context.Context, userID uuid.UUID, platform, name string, refreshHash []byte) (domain.Device, error) {
	var d domain.Device
	err := s.pool.QueryRow(ctx, `
		INSERT INTO devices (user_id, platform, name, refresh_token_hash)
		VALUES ($1, $2, $3, $4)
		RETURNING id, user_id, platform, name, created_at, last_seen_at`,
		userID, platform, name, refreshHash,
	).Scan(&d.ID, &d.UserID, &d.Platform, &d.Name, &d.CreatedAt, &d.LastSeenAt)
	if err != nil {
		return domain.Device{}, fmt.Errorf("создание устройства: %w", err)
	}
	return d, nil
}

// RotateRefresh обменивает старый refresh на новый одним UPDATE.
//
// Условие WHERE на старый хэш делает операцию атомарной: два параллельных
// обновления с одним и тем же токеном не выдадут два валидных новых — второй
// не найдёт строку.
func (s *Store) RotateRefresh(ctx context.Context, oldHash, newHash []byte, ttl time.Duration) (domain.Device, error) {
	var d domain.Device
	err := s.pool.QueryRow(ctx, `
		UPDATE devices SET refresh_token_hash = $2, last_seen_at = now()
		WHERE refresh_token_hash = $1
		  AND revoked_at IS NULL
		  AND last_seen_at > now() - $3::interval
		RETURNING id, user_id, platform, name, created_at, last_seen_at`,
		oldHash, newHash, ttl.String(),
	).Scan(&d.ID, &d.UserID, &d.Platform, &d.Name, &d.CreatedAt, &d.LastSeenAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Device{}, ErrNotFound
	}
	if err != nil {
		return domain.Device{}, fmt.Errorf("ротация refresh-токена: %w", err)
	}
	return d, nil
}

func (s *Store) RevokeDevice(ctx context.Context, deviceID uuid.UUID) error {
	_, err := s.pool.Exec(ctx, `UPDATE devices SET revoked_at = now() WHERE id = $1`, deviceID)
	if err != nil {
		return fmt.Errorf("отзыв устройства: %w", err)
	}
	return nil
}

func (s *Store) SetPushToken(ctx context.Context, deviceID uuid.UUID, token string) error {
	_, err := s.pool.Exec(ctx, `UPDATE devices SET push_token = NULLIF($2, '') WHERE id = $1`, deviceID, token)
	if err != nil {
		return fmt.Errorf("сохранение push-токена: %w", err)
	}
	return nil
}

// PushTokensFor отдаёт токены живых устройств пользователей — вход для
// отправки пуша тем, кто сейчас офлайн.
func (s *Store) PushTokensFor(ctx context.Context, userIDs []uuid.UUID) (map[uuid.UUID][]string, error) {
	if len(userIDs) == 0 {
		return nil, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT user_id, push_token FROM devices
		WHERE user_id = ANY($1) AND revoked_at IS NULL AND push_token IS NOT NULL`, userIDs)
	if err != nil {
		return nil, fmt.Errorf("выборка push-токенов: %w", err)
	}
	defer rows.Close()

	out := make(map[uuid.UUID][]string)
	for rows.Next() {
		var userID uuid.UUID
		var token string
		if err := rows.Scan(&userID, &token); err != nil {
			return nil, fmt.Errorf("чтение push-токена: %w", err)
		}
		out[userID] = append(out[userID], token)
	}
	return out, rows.Err()
}

// --- Коды подтверждения ---

type AuthCode struct {
	Phone     string
	CodeHash  []byte
	Attempts  int
	ExpiresAt time.Time
}

func (s *Store) PutAuthCode(ctx context.Context, phone string, hash []byte, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO auth_codes (phone, code_hash, attempts, created_at, expires_at)
		VALUES ($1, $2, 0, now(), $3)
		ON CONFLICT (phone) DO UPDATE
		SET code_hash = EXCLUDED.code_hash, attempts = 0,
		    created_at = now(), expires_at = EXCLUDED.expires_at`,
		phone, hash, expiresAt)
	if err != nil {
		return fmt.Errorf("сохранение кода: %w", err)
	}
	return nil
}

// TakeAuthCodeAttempt считает попытку и возвращает состояние кода. Счётчик
// растёт до сверки, поэтому перебор упирается в лимит даже при гонке.
func (s *Store) TakeAuthCodeAttempt(ctx context.Context, phone string) (AuthCode, error) {
	var c AuthCode
	err := s.pool.QueryRow(ctx, `
		UPDATE auth_codes SET attempts = attempts + 1
		WHERE phone = $1
		RETURNING phone, code_hash, attempts, expires_at`, phone,
	).Scan(&c.Phone, &c.CodeHash, &c.Attempts, &c.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return AuthCode{}, ErrNotFound
	}
	if err != nil {
		return AuthCode{}, fmt.Errorf("проверка кода: %w", err)
	}
	return c, nil
}

func (s *Store) DeleteAuthCode(ctx context.Context, phone string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM auth_codes WHERE phone = $1`, phone)
	if err != nil {
		return fmt.Errorf("удаление кода: %w", err)
	}
	return nil
}
