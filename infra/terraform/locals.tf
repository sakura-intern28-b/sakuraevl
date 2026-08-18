########################################
# 共通ローカル値
########################################

locals {
  # CIDR 表記 (例: "192.168.1.30/24") からホスト部分の IP アドレスのみを取り出す
  db_private_ip     = element(split("/", var.db_private_net_cidr), 0)
  server_private_ip = element(split("/", var.server_private_net_cidr), 0)
}
