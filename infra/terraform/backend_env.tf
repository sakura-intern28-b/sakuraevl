########################################
# app/backend/.env の自動生成
########################################
# terraform apply のたびに、作成したVM・データベースのIPアドレスを
# もとに app/backend/.env を上書き生成する。
# 手動での編集は次の apply で失われるため注意。

resource "local_file" "backend_env" {
  filename        = "${path.module}/../../app/backend/.env"
  file_permission = "0600"

  content = <<-EOT
    # このファイルは infra/terraform (backend_env.tf) により自動生成されます。
    # 手動で編集しても、次の `terraform apply` で上書きされます。

    # api コンテナがDBアプライアンス(プライベートネットワーク経由)に接続するためのDSN
    DATABASE_URL=${var.db_username}:${var.db_password}@tcp(${local.db_private_ip}:3306)/${var.db_name}?parseTime=true&charset=utf8mb4
    PORT=8080

    # フロントエンドがVMのグローバルIP経由でAPIを叩く場合のCORS許可オリジン
    ALLOWED_ORIGIN=http://${sakura_server.docker_host.ip_address}:3000

    # 参考: terraform で作成したVM・DBのIPアドレス
    SERVER_PUBLIC_IP=${sakura_server.docker_host.ip_address}
    SERVER_PRIVATE_IP=${local.server_private_ip}
    DB_PRIVATE_IP=${local.db_private_ip}
  EOT
}
