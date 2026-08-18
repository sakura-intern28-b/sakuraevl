########################################
# シンプル監視: /healthz の応答時間計測
########################################
# バックエンドが実装するヘルスチェックエンドポイント (GET /healthz, DB疎通確認込み)
# に対してサーバー公開IP:8080 経由で定期的にリクエストを送り、
# アクセスから応答までの時間・死活状態を計測する。
# 結果は monitoring_suite.enabled によりさくらのモニタリングスイートへ連携され、
# ダッシュボードでの可視化・アラート設定が可能になる。

resource "sakura_simple_monitor" "healthz" {
  target      = sakura_server.docker_host.ip_address
  description = "backend API /healthz 死活・応答時間監視"
  delay_loop  = var.healthz_check_delay_loop
  enabled     = true

  health_check = {
    protocol = "http"
    port     = 8080
    path     = "/healthz"
    status   = 200
  }

  monitoring_suite = {
    enabled = true
  }

  depends_on = [sakura_server.docker_host]
}
