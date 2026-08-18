########################################
# app/backend/.env と compose.reg.yml をVMへ配置
########################################
# SSH (パスワード認証) 経由で、生成した .env と compose.reg.yml を
# サーバー上の var.app_remote_dir (デフォルト /opt/app) へ転送する。
# .env の内容や compose.reg.yml が変わるたびに再転送される。

resource "null_resource" "deploy_app_files" {
  triggers = {
    env_sha1     = sha1(local_file.backend_env.content)
    compose_sha1 = filesha1("${path.module}/../../app/backend/compose.reg.yml")
    server_id    = sakura_server.docker_host.id
  }

  connection {
    type     = "ssh"
    host     = sakura_server.docker_host.ip_address
    user     = var.server_ssh_user
    password = var.server_password
    agent    = false
    timeout  = "3m"
  }

  # 転送先ディレクトリを ubuntu ユーザーが書き込めるように準備
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p ${var.app_remote_dir}",
      "sudo chown ${var.server_ssh_user}:${var.server_ssh_user} ${var.app_remote_dir}",
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

  # .env は DB パスワードを含むため転送後にパーミッションを絞る
  provisioner "remote-exec" {
    inline = [
      "chmod 600 ${var.app_remote_dir}/.env",
    ]
  }

  depends_on = [
    sakura_server.docker_host,
    sakura_database.db,
    local_file.backend_env,
  ]
}
