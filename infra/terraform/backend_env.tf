########################################
# app/backend/.env の自動生成
########################################
# terraform apply のたびに、作成したVM・データベースのIPアドレスを
# もとに app/backend/.env をローカルに生成する（開発用の控え）。
# 遠隔サーバーへの配置は deploy.tf の null_resource.deploy_app_files が行う。
# 手動での編集は次の apply で失われるため注意。

resource "local_file" "backend_env" {
  filename        = "${path.module}/../../app/backend/.env"
  file_permission = "0600"

  content = <<-EOT
    # このファイルは infra/terraform (backend_env.tf) により自動生成されます。
    # 手動で編集しても、次の `terraform apply` で上書きされます。

    # api コンテナがDBアプライアンス(プライベートネットワーク経由)に接続するためのDSN
    DATABASE_URL=${var.db_username}:${var.db_password}@tcp(${local.db_private_ip}:${sakura_database.db.network_interface.port})/${var.db_name}?parseTime=true&charset=utf8mb4
    PORT=8080
    # compose.reg.yml が api コンテナの PORT に渡す値 (proxy の proxy_pass 先と揃える)
    API_PORT=8080

    # フロントエンドがAPIを叩く場合のCORS許可オリジン
    # (app_domain 未設定時はサーバーの公開IP + app_http_port から導出される)
    ALLOWED_ORIGIN=${local.app_origin}


    # 参考: terraform で作成したVM・DBのIPアドレス
    SERVER_PUBLIC_IP=${sakura_server.docker_host.ip_address}
    SERVER_PRIVATE_IP=${local.server_private_ip}
    DB_PRIVATE_IP=${local.db_private_ip}

    # compose.reg.yml の migrate ワンショットrunner用
    DB_HOST=${local.db_private_ip}
    DB_PORT=${sakura_database.db.network_interface.port}
    DB_NAME=${var.db_name}
    DB_USERNAME=${var.db_username}
    DB_PASSWORD=${var.db_password}

    # ブラウザがAPIを叩くURL (proxy の /api/ 経由)
    API_URL=${local.app_origin}/api

    # 公開ホストとサービスポート (compose.reg.yml の proxy と init-ssl.sh が参照する)
    APP_DOMAIN=${local.app_domain}
    APP_HOST=${local.app_host}
    APP_ORIGIN=${local.app_origin}
    APP_HTTP_PORT=${var.app_http_port}
    APP_HTTPS_PORT=${var.app_https_port}
    CERTBOT_EMAIL=${local.certbot_email}


    CR_URL=${var.cr_url}

    # トレース送信先。未設定だと telemetry.Init() が no-op になり
    # モニタリングスイートへトレースが一切届かないため必ず出力する。
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=${var.otel_exporter_otlp_traces_endpoint}
    OTEL_SERVICE_NAME=${var.otel_service_name}
    DEPLOY_ENV=production

    # 性能比較用の backend イメージタグ（switch-variant.sh が .env.variant で上書きする）
    BACKEND_TAG=${var.backend_image_tag}
  EOT
}
