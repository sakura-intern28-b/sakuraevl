package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	appdb "sakuravel/internal/db"
	"sakuravel/internal/handler"
	"sakuravel/internal/middleware"
	"sakuravel/internal/realtime"
	"sakuravel/internal/telemetry"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	semconv "go.opentelemetry.io/otel/semconv/v1.43.0"
	"go.opentelemetry.io/otel/trace"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// トレースの送信先（さくらのモニタリングスイート）を初期化する
	shutdownTracer, err := telemetry.Init(ctx)
	if err != nil {
		log.Printf("tracing disabled: %v", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracer(shutdownCtx); err != nil {
			log.Printf("tracer shutdown: %v", err)
		}
	}()

	db := appdb.New()
	defer db.Close()

	h := &handler.Handler{
		DB:            db,
		CookieSecure:  os.Getenv("COOKIE_SECURE") == "true",
		Notifications: realtime.NewHub(),
		Threads:       realtime.NewHub(),
	}
	auth := &middleware.Auth{DB: db}

	mux := http.NewServeMux()

	// CORS → OpenTelemetry 計測 → ルーティング の順で通す。
	// otelhttp が各リクエストの所要時間をスパンとして記録する。
	mux.Handle("/", corsMiddleware(
		otelhttp.NewHandler(
			traceRoute(routes(h, auth)),
			"http.server",
			otelhttp.WithFilter(shouldTrace),
		),
	))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{Addr: ":" + port, Handler: mux}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			log.Printf("server shutdown: %v", err)
		}
	}()

	log.Printf("starting server on :%s", port)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

// traceRoute はマッチしたルートパターン（例: "GET /posts/{id}"）を
// スパン名と http.route 属性に反映させる。
// otelhttp はルーティング前に動くため、パターンはここで解決する。
func traceRoute(mux *http.ServeMux) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, pattern := mux.Handler(r); pattern != "" {
			span := trace.SpanFromContext(r.Context())
			span.SetName(pattern)
			span.SetAttributes(semconv.HTTPRoute(pattern))
		}
		mux.ServeHTTP(w, r)
	})
}

// shouldTrace は計測対象のリクエストを絞り込む。
// SSE は接続が張られ続けるため所要時間の指標にならず、除外する。
func shouldTrace(r *http.Request) bool {
	if r.Method == http.MethodOptions {
		return false
	}
	return !strings.HasSuffix(r.URL.Path, "/stream")
}

func routes(h *handler.Handler, auth *middleware.Auth) *http.ServeMux {
	mux := http.NewServeMux()

	// 認証
	mux.HandleFunc("POST /register", h.Register)
	mux.HandleFunc("POST /login", h.Login)
	mux.Handle("POST /logout", auth.Required(http.HandlerFunc(h.Logout)))

	// 自分のプロフィール
	mux.Handle("GET /me", auth.Required(http.HandlerFunc(h.GetMe)))

	// 足跡
	mux.Handle("GET /me/footprints", auth.Required(http.HandlerFunc(h.GetFootprints)))

	// ユーザー
	mux.Handle("GET /profile/{user_id}", auth.Optional(http.HandlerFunc(h.GetProfile)))
	mux.Handle("PUT /profile", auth.Required(http.HandlerFunc(h.UpdateProfile)))
	mux.Handle("GET /users/{user_id}/followers", auth.Optional(http.HandlerFunc(h.GetFollowers)))
	mux.Handle("GET /users/{user_id}/following", auth.Optional(http.HandlerFunc(h.GetFollowing)))
	mux.Handle("POST /users/{user_id}/follow", auth.Required(http.HandlerFunc(h.Follow)))
	mux.Handle("DELETE /users/{user_id}/follow", auth.Required(http.HandlerFunc(h.Unfollow)))

	// 投稿
	mux.Handle("GET /posts", auth.Required(http.HandlerFunc(h.GetTimeline)))
	mux.Handle("POST /posts", auth.Required(http.HandlerFunc(h.CreatePost)))
	mux.Handle("GET /posts/{id}", auth.Optional(http.HandlerFunc(h.GetPost)))
	mux.Handle("GET /users/{user_id}/posts", auth.Optional(http.HandlerFunc(h.GetUserPosts)))
	mux.Handle("DELETE /posts/{id}", auth.Required(http.HandlerFunc(h.DeletePost)))

	// 返信（スレッド）
	mux.Handle("POST /replies", auth.Required(http.HandlerFunc(h.CreateReply)))
	mux.Handle("GET /posts/{id}/thread", auth.Optional(http.HandlerFunc(h.GetThread)))
	mux.Handle("GET /posts/{id}/thread/stream", auth.Optional(http.HandlerFunc(h.ThreadStream)))

	// いいね
	mux.HandleFunc("GET /posts/{id}/likes", h.GetLikes)
	mux.Handle("POST /likes", auth.Required(http.HandlerFunc(h.Like)))
	mux.Handle("DELETE /likes/{post_id}", auth.Required(http.HandlerFunc(h.Unlike)))

	// リポスト
	mux.Handle("POST /reposts", auth.Required(http.HandlerFunc(h.Repost)))
	mux.Handle("DELETE /reposts/{post_id}", auth.Required(http.HandlerFunc(h.UnRepost)))

	// 検索
	mux.HandleFunc("GET /search", h.Search)

	// 通知
	mux.Handle("GET /notifications", auth.Required(http.HandlerFunc(h.GetNotifications)))
	mux.Handle("POST /notifications/read", auth.Required(http.HandlerFunc(h.MarkNotificationsRead)))
	mux.Handle("GET /notifications/unread_count", auth.Required(http.HandlerFunc(h.GetUnreadCount)))
	mux.Handle("GET /notifications/stream", auth.Required(http.HandlerFunc(h.NotificationStream)))

	// トレンド
	mux.Handle("GET /trending", auth.Optional(http.HandlerFunc(h.GetTrending)))

	return mux
}

func corsMiddleware(next http.Handler) http.Handler {
	allowedOrigin := os.Getenv("ALLOWED_ORIGIN")
	if allowedOrigin == "" {
		allowedOrigin = "http://localhost:3000"
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
