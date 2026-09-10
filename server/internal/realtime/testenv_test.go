package realtime_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/media"
	"github.com/salimastrakhan-ast/main/server/internal/push"
	"github.com/salimastrakhan-ast/main/server/internal/ratelimit"
	"github.com/salimastrakhan-ast/main/server/internal/realtime"
	"github.com/salimastrakhan-ast/main/server/internal/store"
	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Тесты работают против реальных Postgres и Redis из deploy/docker-compose.yml.
//
// Подменять базу заглушкой здесь бессмысленно: проверяем мы ровно то, что
// делает Postgres — выделение номера под блокировкой строки, откат номера при
// конфликте и уникальные индексы. На моках всё это прошло бы «успешно» и в
// сломанном виде.
const (
	defaultTestDB    = "postgres://mayak:mayak@localhost:5433/mayak_test?sslmode=disable"
	defaultAdminDB   = "postgres://mayak:mayak@localhost:5433/mayak?sslmode=disable"
	defaultTestRedis = "redis://localhost:6380/1"
)

type env struct {
	t      *testing.T
	store  *store.Store
	tokens *auth.TokenIssuer
	hub    *realtime.Hub
	server *httptest.Server
	rdb    *redis.Client
	pushes *recordingPusher
}

// recordingPusher запоминает уведомления вместо отправки: проверять надо,
// кому и когда сервер решил отправить пуш, а не как устроен провайдер.
type recordingPusher struct {
	mu   sync.Mutex
	sent []push.Notification
}

func (p *recordingPusher) Push(_ context.Context, n push.Notification) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.sent = append(p.sent, n)
	return nil
}

func (p *recordingPusher) all() []push.Notification {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]push.Notification(nil), p.sent...)
}

func newEnv(t *testing.T) *env {
	t.Helper()
	ctx := context.Background()

	pool := openTestDB(t, ctx)
	truncate(t, ctx, pool)

	rdb := openTestRedis(t, ctx)
	if err := rdb.FlushDB(ctx).Err(); err != nil {
		t.Fatalf("очистка Redis: %v", err)
	}

	st := store.New(pool)
	tokens := auth.NewTokenIssuer([]byte("test-secret-test-secret"), 15*time.Minute)

	// Логи хаба в тестах не нужны, кроме случаев отладки.
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	pushes := &recordingPusher{}
	hub := realtime.NewHub(st, rdb, pushes, tokens, media.NoopResolver{}, logger)

	hubCtx, stopHub := context.WithCancel(ctx)
	hubDone := make(chan struct{})
	go func() {
		defer close(hubDone)
		hub.Run(hubCtx)
	}()
	// Хаб подписывается на каналы Redis не мгновенно; дать ему стартовать.
	waitFor(t, time.Second, func() bool { return hub.OnlineUsersCount() >= 0 })

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/ws", hub.Serve)
	server := httptest.NewServer(mux)

	t.Cleanup(func() {
		server.Close()
		stopHub()
		<-hubDone
		_ = rdb.Close()
		pool.Close()
	})

	return &env{t: t, store: st, tokens: tokens, hub: hub, server: server, rdb: rdb, pushes: pushes}
}

func openTestDB(t *testing.T, ctx context.Context) *pgxpool.Pool {
	t.Helper()
	dsn := envOr("MAYAK_TEST_DATABASE_URL", defaultTestDB)

	// Создание базы идемпотентно и стоит один запрос, зато первый прогон на
	// чистой машине не спотыкается об отсутствующую базу.
	if !createTestDatabase(t, ctx, dsn) {
		t.Skip("Postgres недоступен. Поднимите инфраструктуру: make up")
	}
	pool, err := store.Connect(ctx, dsn)
	if err != nil {
		t.Skipf("Postgres недоступен: %v", err)
	}
	if err := store.Migrate(ctx, pool); err != nil {
		t.Fatalf("миграции: %v", err)
	}
	return pool
}

func createTestDatabase(t *testing.T, ctx context.Context, dsn string) bool {
	t.Helper()
	name := dsn[strings.LastIndexByte(dsn, '/')+1:]
	if i := strings.IndexByte(name, '?'); i >= 0 {
		name = name[:i]
	}

	admin, err := store.Connect(ctx, envOr("MAYAK_TEST_ADMIN_URL", defaultAdminDB))
	if err != nil {
		return false
	}
	defer admin.Close()

	if _, err := admin.Exec(ctx, "CREATE DATABASE "+name); err != nil &&
		!strings.Contains(err.Error(), "already exists") {
		return false
	}
	return true
}

func openTestRedis(t *testing.T, ctx context.Context) *redis.Client {
	t.Helper()
	rdb, err := ratelimit.Connect(ctx, envOr("MAYAK_TEST_REDIS_URL", defaultTestRedis))
	if err != nil {
		t.Skipf("Redis недоступен (%v). Поднимите инфраструктуру: make up", err)
	}
	return rdb
}

func truncate(t *testing.T, ctx context.Context, pool *pgxpool.Pool) {
	t.Helper()
	_, err := pool.Exec(ctx, `TRUNCATE attachments, messages, chat_members, chats,
		contacts, devices, auth_codes, users RESTART IDENTITY CASCADE`)
	if err != nil && !strings.Contains(err.Error(), "does not exist") {
		t.Fatalf("очистка базы: %v", err)
	}
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// newUser заводит пользователя и выдаёт ему токен, минуя SMS.
func (e *env) newUser(phone string) (domain.User, string) {
	e.t.Helper()
	ctx := context.Background()

	user, err := e.store.EnsureUserByPhone(ctx, phone)
	if err != nil {
		e.t.Fatalf("создание пользователя: %v", err)
	}
	device, err := e.store.CreateDevice(ctx, user.ID, "test", "test", auth.HashToken(uuid.NewString()))
	if err != nil {
		e.t.Fatalf("создание устройства: %v", err)
	}
	token, err := e.tokens.Issue(user.ID, device.ID, time.Now())
	if err != nil {
		e.t.Fatalf("выпуск токена: %v", err)
	}
	return user, token
}

// client — тестовый клиент поверх того же протокола, что и у приложения.
type client struct {
	t     *testing.T
	sock  *websocket.Conn
	codec ws.Codec
	seq   int
}

func (e *env) connect(token string) *client {
	e.t.Helper()
	url := "ws" + strings.TrimPrefix(e.server.URL, "http") + "/v1/ws"

	sock, _, err := websocket.Dial(context.Background(), url, nil)
	if err != nil {
		e.t.Fatalf("подключение: %v", err)
	}
	c := &client{t: e.t, sock: sock, codec: ws.JSONCodec{}}

	c.sendRaw(ws.CmdAuth, "", ws.AuthData{Token: token})
	if env := c.await(ws.EventReady, 3*time.Second); env.T != ws.EventReady {
		e.t.Fatalf("не дождались ready, пришло %s", env.T)
	}
	return c
}

func (c *client) close() { _ = c.sock.Close(websocket.StatusNormalClosure, "") }

// tryConnect подключается с произвольным токеном и говорит, пережило ли
// соединение рукопожатие.
func (e *env) tryConnect(token string) bool {
	e.t.Helper()
	url := "ws" + strings.TrimPrefix(e.server.URL, "http") + "/v1/ws"

	sock, _, err := websocket.Dial(context.Background(), url, nil)
	if err != nil {
		return false
	}
	defer func() { _ = sock.Close(websocket.StatusNormalClosure, "") }()

	frame, err := ws.Reply(ws.JSONCodec{}, "", ws.CmdAuth, ws.AuthData{Token: token})
	if err != nil {
		e.t.Fatalf("сборка кадра: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := sock.Write(ctx, websocket.MessageText, frame); err != nil {
		return false
	}
	// Сервер либо пришлёт ready, либо закроет соединение.
	_, _, err = sock.Read(ctx)
	return err == nil
}

func (c *client) sendRaw(typ, id string, payload any) {
	c.t.Helper()
	frame, err := ws.Reply(c.codec, id, typ, payload)
	if err != nil {
		c.t.Fatalf("сборка кадра: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := c.sock.Write(ctx, websocket.MessageText, frame); err != nil {
		c.t.Fatalf("отправка %s: %v", typ, err)
	}
}

// call шлёт команду и ждёт ответ именно на неё.
func (c *client) call(typ string, payload any) ws.Envelope {
	c.t.Helper()
	c.seq++
	id := fmt.Sprintf("c-%d", c.seq)
	c.sendRaw(typ, id, payload)

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		env := c.read(time.Until(deadline))
		if env.ID == id {
			return env
		}
		// События, прилетевшие между командой и ответом, пропускаем.
	}
	c.t.Fatalf("не дождались ответа на %s", typ)
	return ws.Envelope{}
}

func (c *client) read(timeout time.Duration) ws.Envelope {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	_, data, err := c.sock.Read(ctx)
	if err != nil {
		c.t.Fatalf("чтение: %v", err)
	}
	env, err := c.codec.Decode(data)
	if err != nil {
		c.t.Fatalf("разбор кадра: %v", err)
	}
	return env
}

// await ждёт событие нужного типа, пропуская всё остальное.
func (c *client) await(typ string, timeout time.Duration) ws.Envelope {
	c.t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		env := c.read(time.Until(deadline))
		if env.T == typ {
			return env
		}
	}
	c.t.Fatalf("не дождались события %s", typ)
	return ws.Envelope{}
}

// expectNothing убеждается, что за отведённое время ничего не пришло.
func (c *client) expectNothing(timeout time.Duration) {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	_, data, err := c.sock.Read(ctx)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			return
		}
		c.t.Fatalf("чтение: %v", err)
	}
	c.t.Fatalf("пришло лишнее событие: %s", data)
}

func decode[T any](t *testing.T, env ws.Envelope) T {
	t.Helper()
	var out T
	if err := json.Unmarshal(env.D, &out); err != nil {
		t.Fatalf("разбор данных события %s: %v", env.T, err)
	}
	return out
}

func waitFor(t *testing.T, timeout time.Duration, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("условие не выполнилось за отведённое время")
}
