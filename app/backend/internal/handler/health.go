package handler

import "net/http"

// Healthz はシンプル監視からの疎通確認用エンドポイント。
// DBへの接続確認を含め、依存先まで含めた死活状態を返す。
func (h *Handler) Healthz(w http.ResponseWriter, r *http.Request) {
	var dbOK int
	if err := h.DB.QueryRowContext(r.Context(), "SELECT 1").Scan(&dbOK); err != nil {
		h.respondJSON(w, http.StatusServiceUnavailable, healthResponse{DB: 0})
		return
	}
	h.respondJSON(w, http.StatusOK, healthResponse{DB: dbOK})
}
