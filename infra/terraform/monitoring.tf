########################################
# シンプル監視: /api/healthz の応答時間計測
########################################
# バックエンドが実装するヘルスチェックエンドポイント (GET /healthz, DB疎通確認込み)
# に対して、proxy (nginx) が公開するサーバー公開IP:80 経由で定期的にリクエストを送り、
# アクセスから応答までの時間・死活状態を計測する。
# nginx は /api/ プレフィックスを剥がして backend の /healthz へプロキシするため、
# 外部からは /api/healthz を叩く (DBまで含めた死活監視になる)。
# 結果は monitoring_suite.enabled によりさくらのモニタリングスイートへ連携され、
# ダッシュボードでの可視化・アラート設定が可能になる。

resource "sakura_simple_monitor" "healthz" {
  target      = sakura_server.docker_host.ip_address
  description = "backend API /api/healthz 死活・応答時間監視"
  delay_loop  = var.healthz_check_delay_loop
  enabled     = true

  health_check = {
    protocol = "http"
    port     = 80
    path     = "/api/healthz"
    status   = 200
  }

  monitoring_suite = {
    enabled = true
  }

  depends_on = [sakura_server.docker_host]
}
