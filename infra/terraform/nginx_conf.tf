########################################
# proxy (nginx) 設定ファイルの自動生成
########################################
# app/backend/nginx/nginx.conf.tftpl を app_domain / app_https_port の値で
# レンダリングし、generated/nginx.conf として出力する。
# 実際のサーバーへの配置は deploy.tf の null_resource が行う。
#
# app_domain を指定した場合   : server_name と証明書パスにドメインを埋め込み、
#                               80 は ACME + HTTPSリダイレクト、443 で配信する。
# app_domain が空の場合       : 証明書を発行できないため、80 のみで配信する
#                               (公開URLは http://<サーバー公開IP>:<app_http_port>)。

resource "local_file" "nginx_conf" {
  filename        = "${path.module}/generated/nginx.conf"
  file_permission = "0644"

  content = templatefile("${path.module}/../../app/backend/nginx/nginx.conf.tftpl", {
    use_tls = local.app_use_tls
    # ドメインなしのときは任意のホスト名 (IPアドレス直打ち) を受けるため "_"
    server_name = local.app_use_tls ? local.app_domain : "_"
    cert_domain = local.app_domain
    # 443 以外で公開する場合、HTTPSへのリダイレクト先にポート番号が必要
    https_port_suffix = var.app_https_port == 443 ? "" : ":${var.app_https_port}"
  })
}
