########################################
# パケットフィルタ (セキュリティ)
########################################

resource "sakura_packet_filter" "web" {
  name        = "${var.server_name}-filter"
  description = "Packet filter for application server"
  zone        = var.zone
}

resource "sakura_packet_filter_rules" "web_rules" {
  packet_filter_id = sakura_packet_filter.web.id
  zone             = var.zone

  expression = [
    # 1. SSH (Port 22)
    {
      protocol         = "tcp"
      destination_port = "22"
      allow            = true
      description      = "Allow SSH"
    },
    # 2. HTTP (Port 80)
    {
      protocol         = "tcp"
      destination_port = "80"
      allow            = true
      description      = "Allow HTTP"
    },
    # 3. HTTPS (Port 443)
    {
      protocol         = "tcp"
      destination_port = "443"
      allow            = true
      description      = "Allow HTTPS"
    },
    # 4. Frontend (Port 3000)
    {
      protocol         = "tcp"
      destination_port = "3000"
      allow            = true
      description      = "Allow App Frontend"
    },
    # 5. HTTPS Proxy (Port 4430)
    {
      protocol         = "tcp"
      destination_port = "4430"
      allow            = true
      description      = "Allow HTTPS Proxy"
    },
      # 5. Backend API (Port 8080)
    {
      protocol         = "tcp"
      destination_port = "8080"
      allow            = true
      description      = "Allow App Backend API"
    },
    # 7. ICMP (Ping)
    {
      protocol    = "icmp"
      allow       = true
      description = "Allow ICMP"
    },
    # 今回IPアドレスはDHCP経由で取得しているので、DHCPパケットを許可しなきゃダメ
    {
      protocol         = "udp"
      destination_port = "68"
      allow            = true
      description      = "Allow DHCPv4 client response"
    },
    # v6も同じ
    {
      protocol         = "udp"
      destination_port = "546"
      allow            = true
      description      = "Allow DHCPv6 client response"
    },
    # 7. Fragment
    {
      protocol    = "fragment"
      allow       = true
      description = "Allow Fragment"
    },
    # 11. 戻りパケット (Linux/macOS Ephemeral Ports TCP)
    {
      protocol         = "tcp"
      source_port      = "32768-65535"
      allow            = true
      description      = "Allow Return TCP (Source Port)"
    },
    # 12. 戻りパケット (Linux/macOS Ephemeral Ports UDP)
    {
      protocol         = "udp"
      source_port      = "32768-65535"
      allow            = true
      description      = "Allow Return UDP (Source Port)"
    },
    # 13. 戻りパケット (TCP Ephemeral Destination)
    {
      protocol         = "tcp"
      destination_port = "32768-65535"
      allow            = true
      description      = "Allow Return TCP (Dest Port)"
    },
    # 14. 戻りパケット (UDP Ephemeral Destination)
    {
      protocol         = "udp"
      destination_port = "32768-65535"
      allow            = true
      description      = "Allow Return UDP (Dest Port)"
    },
    # 12. DHCP応答 (共有セグメントのIPアドレス取得)
    {
      protocol         = "udp"
      source_port      = "67"
      destination_port = "68"
      allow            = true
      description      = "Allow DHCP Response"
    },
    # 13. Deny All (最後に配置)
    {
      protocol    = "ip"
      allow       = false
      description = "Deny All"
    }
  ]
}
