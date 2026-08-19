########################################
# サーバー
########################################

data "sakura_archive" "ubuntu" {
  name = "Ubuntu Server 24.04.2 LTS 64bit (cloudimg)"
  zone = var.zone
}

resource "sakura_disk" "docker_host" {
  name              = "${var.server_name}-disk"
  plan              = "ssd"
  size              = 20
  source_archive_id = data.sakura_archive.ubuntu.id
}

resource "sakura_server" "docker_host" {
  name   = var.server_name
  disks  = [sakura_disk.docker_host.id]
  core   = 1
  memory = 2

  # 共有セグメント接続
  network_interface = [
    {
      upstream         = "shared"
      packet_filter_id = sakura_packet_filter.web.id
    },
    { upstream = sakura_vswitch.private_net.id },
  ]

  # cloud-init user-data
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname          = var.server_name
    password          = var.server_password
    ssh_public_key    = var.server_ssh_public_key_path != "" ? file(pathexpand(var.server_ssh_public_key_path)) : ""
    private_ip_cidr   = var.server_private_net_cidr

    # sacloud-otel-collector (トークンが1つでも設定されていればセットアップする)
    otel_collector_enabled     = var.monitoring_traces_token != "" || var.monitoring_logs_token != ""
    otel_collector_version     = var.otel_collector_version
    monitoring_traces_endpoint = var.monitoring_traces_endpoint
    monitoring_traces_token    = var.monitoring_traces_token
    monitoring_logs_endpoint   = var.monitoring_logs_endpoint
    monitoring_logs_token      = var.monitoring_logs_token
    app_remote_dir             = var.app_remote_dir
  })
}

output "server_ip_address" {
  description = "サーバーのグローバルIPアドレス (共有セグメント)"
  value       = sakura_server.docker_host.ip_address
}

output "server_private_ip_address" {
  description = "サーバーのプライベートIPアドレス"
  value       = local.server_private_ip
}


