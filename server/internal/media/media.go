// Package media — хранение вложений в S3-совместимом хранилище.
//
// Локально это MinIO из docker-compose, в проде — объектное хранилище
// российского облака (Yandex Object Storage, VK Cloud, Selectel): все они
// говорят на протоколе S3, и код между ними не меняется.
package media

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/url"
	"path"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
)

// linkTTL — сколько живёт ссылка на файл.
//
// Ссылки подписанные и временные: постоянный публичный адрес означал бы,
// что утёкшая из истории браузера ссылка открывает чужое вложение навсегда.
const linkTTL = 6 * time.Hour

var ErrTooLarge = errors.New("файл слишком большой")

type Storage struct {
	client *minio.Client
	bucket string
}

type Config struct {
	Endpoint  string
	AccessKey string
	SecretKey string
	Bucket    string
	UseSSL    bool
}

func NewStorage(ctx context.Context, cfg Config) (*Storage, error) {
	client, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("подключение к хранилищу: %w", err)
	}

	exists, err := client.BucketExists(ctx, cfg.Bucket)
	if err != nil {
		return nil, fmt.Errorf("проверка бакета: %w", err)
	}
	if !exists {
		if err := client.MakeBucket(ctx, cfg.Bucket, minio.MakeBucketOptions{}); err != nil {
			return nil, fmt.Errorf("создание бакета %s: %w", cfg.Bucket, err)
		}
	}
	return &Storage{client: client, bucket: cfg.Bucket}, nil
}

type Upload struct {
	OwnerID  uuid.UUID
	FileName string
	Mime     string
	Size     int64
	Body     io.Reader
}

// Put кладёт файл и возвращает ключ объекта.
//
// Ключ строится из идентификатора владельца и случайного имени: угадать
// чужой ключ нельзя, а по префиксу видно, чьи файлы удалять при удалении
// аккаунта.
func (s *Storage) Put(ctx context.Context, up Upload) (string, error) {
	key := path.Join(up.OwnerID.String(), uuid.NewString()+extension(up.FileName, up.Mime))

	_, err := s.client.PutObject(ctx, s.bucket, key, up.Body, up.Size, minio.PutObjectOptions{
		ContentType: up.Mime,
		// Имя файла отдаётся при скачивании, но в ключе не участвует:
		// в него легко положить путь вида ../../ или чужие данные.
		ContentDisposition: contentDisposition(up.FileName),
	})
	if err != nil {
		return "", fmt.Errorf("загрузка файла: %w", err)
	}
	return key, nil
}

// Link выдаёт временную подписанную ссылку на объект.
func (s *Storage) Link(ctx context.Context, objectKey string) (string, error) {
	u, err := s.client.PresignedGetObject(ctx, s.bucket, objectKey, linkTTL, url.Values{})
	if err != nil {
		return "", fmt.Errorf("ссылка на файл: %w", err)
	}
	return u.String(), nil
}

// Resolve проставляет ссылки вложениям перед отдачей клиенту.
func (s *Storage) Resolve(ctx context.Context, attachments []domain.Attachment) []domain.Attachment {
	for i := range attachments {
		link, err := s.Link(ctx, attachments[i].ObjectKey)
		if err != nil {
			continue // Без ссылки вложение всё равно видно по имени и типу.
		}
		attachments[i].URL = link
	}
	return attachments
}

func (s *Storage) Remove(ctx context.Context, objectKey string) error {
	if err := s.client.RemoveObject(ctx, s.bucket, objectKey, minio.RemoveObjectOptions{}); err != nil {
		return fmt.Errorf("удаление файла: %w", err)
	}
	return nil
}

// KindOf определяет вид вложения по типу содержимого — от него зависит,
// как клиент его нарисует.
func KindOf(mime string) domain.AttachmentKind {
	switch {
	case strings.HasPrefix(mime, "image/"):
		return domain.AttachmentImage
	case strings.HasPrefix(mime, "video/"):
		return domain.AttachmentVideo
	case strings.HasPrefix(mime, "audio/"):
		return domain.AttachmentAudio
	default:
		return domain.AttachmentFile
	}
}

func extension(fileName, mime string) string {
	if ext := path.Ext(fileName); ext != "" && len(ext) <= 10 {
		return strings.ToLower(ext)
	}
	switch mime {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	case "video/mp4":
		return ".mp4"
	case "audio/ogg":
		return ".ogg"
	}
	return ""
}

// contentDisposition отдаёт исходное имя файла при скачивании.
//
// Имя приходит от клиента, поэтому кавычки и переводы строк из него надо
// убрать: иначе в заголовок ответа можно подставить что угодно.
func contentDisposition(fileName string) string {
	clean := strings.Map(func(r rune) rune {
		if r < 32 || r == '"' || r == '\\' {
			return -1
		}
		return r
	}, fileName)
	if clean == "" {
		return ""
	}
	return `attachment; filename*=UTF-8''` + url.PathEscape(clean)
}

// Resolver проставляет вложениям временные ссылки.
//
// Отдельный интерфейс нужен, чтобы realtime и HTTP-слой не тянули за собой
// само хранилище: им достаточно уметь превратить ключ объекта в ссылку.
type Resolver interface {
	Resolve(ctx context.Context, attachments []domain.Attachment) []domain.Attachment
}

// NoopResolver оставляет вложения как есть. Используется там, где хранилище
// не поднято, — например, в тестах доставки.
type NoopResolver struct{}

func (NoopResolver) Resolve(_ context.Context, attachments []domain.Attachment) []domain.Attachment {
	return attachments
}

// ResolveMessages проставляет ссылки вложениям пачки сообщений.
func ResolveMessages(ctx context.Context, r Resolver, messages []domain.Message) {
	if r == nil {
		return
	}
	for i := range messages {
		if len(messages[i].Attachments) == 0 {
			continue
		}
		messages[i].Attachments = r.Resolve(ctx, messages[i].Attachments)
	}
}

// ResolveMessage — то же самое для одного сообщения.
//
// Указатель может быть пустым: у только что созданного чата последнего
// сообщения ещё нет.
func ResolveMessage(ctx context.Context, r Resolver, message *domain.Message) {
	if r == nil || message == nil || len(message.Attachments) == 0 {
		return
	}
	message.Attachments = r.Resolve(ctx, message.Attachments)
}

// ResolveSummaries проставляет ссылки последним сообщениям в списке диалогов:
// в ленте чатов тоже видно превью присланной картинки.
func ResolveSummaries(ctx context.Context, r Resolver, summaries []domain.ChatSummary) {
	if r == nil {
		return
	}
	for i := range summaries {
		if summaries[i].LastMessage != nil {
			ResolveMessage(ctx, r, summaries[i].LastMessage)
		}
	}
}
