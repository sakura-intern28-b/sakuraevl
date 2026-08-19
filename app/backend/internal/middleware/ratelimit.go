package middleware

import (
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// RateLimiter はIPアドレスごとにレート制限を行うミドルウェアです。
type RateLimiter struct {
	mu       sync.Mutex
	limiters map[string]*visitor
	r        rate.Limit
	b        int
}

type visitor struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// NewRateLimiter は指定されたレート（r: 1秒あたりの許可数、b: 最大バースト数）の
// レートリミッターを作成します。
func NewRateLimiter(r rate.Limit, b int) *RateLimiter {
	rl := &RateLimiter{
		limiters: make(map[string]*visitor),
		r:        r,
		b:        b,
	}

	// 定期的に古いIPの履歴を削除し、メモリリークを防ぎます
	go rl.cleanupVisitors()

	return rl
}

func (rl *RateLimiter) cleanupVisitors() {
	for {
		time.Sleep(time.Minute)
		rl.mu.Lock()
		for ip, v := range rl.limiters {
			if time.Since(v.lastSeen) > 3*time.Minute {
				delete(rl.limiters, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func (rl *RateLimiter) getVisitor(ip string) *rate.Limiter {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	v, exists := rl.limiters[ip]
	if !exists {
		limiter := rate.NewLimiter(rl.r, rl.b)
		rl.limiters[ip] = &visitor{limiter, time.Now()}
		return limiter
	}

	v.lastSeen = time.Now()
	return v.limiter
}

// getIP はリクエストからクライアントのIPアドレスを取得します
func getIP(r *http.Request) string {
	ip := r.Header.Get("X-Forwarded-For")
	if ip == "" {
		ip = r.Header.Get("X-Real-IP")
	}
	if ip == "" {
		ip = r.RemoteAddr
	}
	// "IP:port" 形式の場合はIPのみを抽出
	if colon := strings.LastIndex(ip, ":"); colon != -1 {
		ip = ip[:colon]
	}
	return ip
}

// Limit はレート制限を適用するミドルウェア関数です
func (rl *RateLimiter) Limit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := getIP(r)
		limiter := rl.getVisitor(ip)

		if !limiter.Allow() {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "too many requests. please try again later.",
			})
			return
		}

		next.ServeHTTP(w, r)
	})
}
