########################################
# app/backend/.env・compose.reg.yml・migrations・migrate.sh をVMへ配置
########################################
# SSH (パスワード認証) 経由で、アプリの実行に必要なファイル一式を
# サーバー上の var.app_remote_dir (デフォルト /opt/app) へ転送するだけの役割。
# 外部DB(さくらのクラウド DBアプライアンス)へのSQL適用は Terraform では行わず、
# 転送された compose.reg.yml の migrate ワンショットrunner (migrate.sh) が
# schema_migrations テーブルを見ながら未適用分だけ適用する。
# 内容が変わるたびに再転送される。

locals {
  migrations_dir = "${path.module}/../../app/backend/migrations"
}

resource "null_resource" "deploy_app_files_and_setup_container_registry" {
  triggers = {
    env_sha1        = sha1(local_file.backend_env.content)
    compose_sha1    = filesha1("${path.module}/../../app/backend/compose.reg.yml")
    migrate_sh_sha1 = filesha1("${path.module}/../../app/backend/migrate.sh")
    init_ssl_sha1   = filesha1("${path.module}/../../app/backend/init-ssl.sh")
    migrations_sha1 = sha1(join("", [for f in sort(fileset(local.migrations_dir, "*.sql")) : filesha1("${local.migrations_dir}/${f}")]))
    nginx_conf_sha1 = filesha1("${path.module}/../../app/backend/nginx/nginx.conf")
    switch_sh_sha1  = filesha1("${path.module}/../../app/backend/scripts/switch-variant.sh")
    server_id       = sakura_server.docker_host.id
  }

  connection {
    type     = "ssh"
    host     = sakura_server.docker_host.ip_address
    user     = var.server_ssh_user
    password = var.server_password
    agent    = false
    timeout  = "3m"
  }

  # 転送先ディレクトリを ubuntu ユーザーが書き込めるように準備。
  # migrations/ や nginx/ は docker compose がバインドマウント先として先に
  # 空ディレクトリを root 所有で作ってしまっているケースがあるため、
  # (例: nginx.conf が未転送のまま docker compose up した場合など)
  # 転送前に作り直しておく。放置すると nginx.conf をファイルとして転送しても
  # 既存ディレクトリの中に配置されてしまい、コンテナ起動時に
  # 「ディレクトリをファイルにマウントしようとしている」エラーになる。
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p ${var.app_remote_dir}",
      "sudo rm -rf ${var.app_remote_dir}/migrations",
      "sudo mkdir -p ${var.app_remote_dir}/migrations",
      "sudo rm -rf ${var.app_remote_dir}/nginx",
      "sudo mkdir -p ${var.app_remote_dir}/nginx",
      "sudo mkdir -p ${var.app_remote_dir}/scripts",
      "sudo chown -R ${var.server_ssh_user}:${var.server_ssh_user} ${var.app_remote_dir}",
      "docker login -u ${var.cr_username} -p ${var.cr_password} ${var.cr_url}",
    ]
  }

  provisioner "file" {
    source      = local_file.backend_env.filename
    destination = "${var.app_remote_dir}/.env"
  }

  provisioner "file" {
    source      = "${path.module}/../../app/backend/compose.reg.yml"
    destination = "${var.app_remote_dir}/compose.reg.yml"
  }

  provisioner "file" {
    source      = "${path.module}/../../app/backend/init-ssl.sh"
    destination = "${var.app_remote_dir}/init-ssl.sh"
  }

  provisioner "file" {
    source      = "${path.module}/../../app/backend/nginx/nginx.conf"
    destination = "${var.app_remote_dir}/nginx/nginx.conf"
  }

  # 性能比較用に api コンテナのイメージタグを切り替えるスクリプト。
  # サーバー上で ./scripts/switch-variant.sh baseline のように使う。
  provisioner "file" {
    source      = "${path.module}/../../app/backend/scripts/switch-variant.sh"
    destination = "${var.app_remote_dir}/scripts/switch-variant.sh"
  }

  # migrate ワンショットrunner が読む migration ファイル一式
  provisioner "file" {
    source      = "${local.migrations_dir}/"
    destination = "${var.app_remote_dir}/migrations"
  }

  # migrate ワンショットrunner の実体スクリプト
  provisioner "file" {
    source      = "${path.module}/../../app/backend/migrate.sh"
    destination = "${var.app_remote_dir}/migrate.sh"
  }

  # .env は DB パスワードを含むため転送後にパーミッションを絞る
  provisioner "remote-exec" {
    inline = [
      "chmod 600 ${var.app_remote_dir}/.env",
      "chmod +x ${var.app_remote_dir}/scripts/switch-variant.sh",
    ]
  }

  # ファイル転送が完了した後に起動する
  # (compose.reg.yml / .env / migrations が揃っていないと migrate が失敗するため)
  provisioner "remote-exec" {
    inline = [
      "docker compose -f ${var.app_remote_dir}/compose.reg.yml down",
      "docker compose -f ${var.app_remote_dir}/compose.reg.yml pull",
      "docker compose -f ${var.app_remote_dir}/compose.reg.yml up -d",
    ]
  }

  depends_on = [
    sakura_server.docker_host,
    sakura_database.db,
    local_file.backend_env,
  ]
}
