########################################
# データベースの初期化 (migrations/*.sql の適用)
########################################
# sakura_database はマネージドアプライアンスのため、Terraform (sacloud
# プロバイダー) から直接 SQL を実行する手段がない。
# 同じプライベートネットワークに接続している docker_host VM 経由で、
# mariadb クライアント (Docker コンテナ) を使って migrations 配下の
# SQL をファイル名の昇順ですべて流し込む。
# CREATE TABLE IF NOT EXISTS 等を基本としているため、何度適用しても安全 (冪等)。

locals {
  migrations_dir  = "${path.module}/../../app/backend/migrations"
  migration_files = sort(fileset(local.migrations_dir, "*.sql"))
}

resource "null_resource" "db_init" {
  triggers = {
    migrations_sha1 = sha1(join("", [for f in local.migration_files : filesha1("${local.migrations_dir}/${f}")]))
    db_id           = sakura_database.db.id
  }

  connection {
    type     = "ssh"
    host     = sakura_server.docker_host.ip_address
    user     = var.server_ssh_user
    password = var.server_password
    agent    = false
    timeout  = "3m"
  }

  # migrations ディレクトリの中身をまるごと転送
  provisioner "file" {
    source      = "${local.migrations_dir}/"
    destination = "/tmp/migrations"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      set -e
      for f in /tmp/migrations/*.sql; do
        echo "applying $${f}"
        docker run --rm -i --network=host \
          -v "$${f}":/init.sql:ro \
          -e MYSQL_PWD='${var.db_password}' \
          mariadb:10.11 \
          mariadb -h ${local.db_private_ip} -P 3306 -u ${var.db_username} ${var.db_name} < /init.sql
      done
      EOT
      ,
      "rm -rf /tmp/migrations",
    ]
  }

  depends_on = [
    sakura_server.docker_host,
    sakura_database.db,
  ]
}
