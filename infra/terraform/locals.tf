########################################
# 共通ローカル値
########################################

locals {
  # CIDR 表記 (例: "192.168.1.30/24") からホスト部分の IP アドレスのみを取り出す
  db_private_ip     = element(split("/", var.db_private_net_cidr), 0)
  server_private_ip = element(split("/", var.server_private_net_cidr), 0)

  ########################################
  # 公開URLの導出
  ########################################
  # app_domain にドメイン名が設定されていれば HTTPS + Let's Encrypt 構成、
  # 空ならサーバーの公開IPアドレスを使った HTTP 構成になる
  # (IPアドレスには Let's Encrypt の証明書を発行できないため)。
  # サービスのポートは app_http_port / app_https_port で別途指定する。
  app_domain      = trimspace(var.app_domain)
  app_use_tls     = local.app_domain != ""
  app_host        = local.app_use_tls ? local.app_domain : sakura_server.docker_host.ip_address
  app_scheme      = local.app_use_tls ? "https" : "http"
  app_public_port = local.app_use_tls ? var.app_https_port : var.app_http_port

  # 標準ポート (https:443 / http:80) のときだけ URL からポート表記を省く
  app_default_port = local.app_use_tls ? 443 : 80
  app_port_suffix  = local.app_public_port == local.app_default_port ? "" : ":${local.app_public_port}"

  # ブラウザからアクセスする際のオリジン (例: https://example.jp:4430, http://203.0.113.10:8080)
  app_origin = "${local.app_scheme}://${local.app_host}${local.app_port_suffix}"

  # Let's Encrypt の証明書取得に使うメールアドレス
  certbot_email = var.certbot_email != "" ? var.certbot_email : (local.app_use_tls ? "admin@${local.app_domain}" : "")
}
