########################################
# データベースの初期化 (migrations/001_init.sql の適用)
########################################
# sakura_database はマネージドアプライアンスのため、Terraform (sacloud
# プロバイダー) から直接 SQL を実行する手段がない。
# 同じプライベートネットワークに接続している docker_host VM 経由で、
# mariadb クライアント (Docker コンテナ) を使って初期化SQLを流し込む。
# CREATE TABLE IF NOT EXISTS のみのため、何度適用しても安全 (冪等)。

resource "null_resource" "db_init" {
  triggers = {
    migration_sha1 = filesha1("${path.module}/../../app/backend/migrations/001_init.sql")
    db_id          = sakura_database.db.id
  }

  connection {
    type     = "ssh"
    host     = sakura_server.docker_host.ip_address
    user     = var.server_ssh_user
    password = var.server_password
    agent    = false
    timeout  = "3m"
  }

  provisioner "file" {
    source      = "${path.module}/../../app/backend/migrations/001_init.sql"
    destination = "/tmp/001_init.sql"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      docker run --rm -i --network=host \
        -v /tmp/001_init.sql:/init.sql:ro \
        -e MYSQL_PWD='${var.db_password}' \
        mariadb:10.11 \
        mariadb -h ${local.db_private_ip} -P 3306 -u ${var.db_username} ${var.db_name} < /init.sql
      EOT
      ,
      "rm -f /tmp/001_init.sql",
    ]
  }

  depends_on = [
    sakura_server.docker_host,
    sakura_database.db,
  ]
}
