########################################
# 認証・ゾーン
########################################

variable "sakura_access_token" {
  description = "さくらのクラウド API アクセストークン。環境変数 SAKURA_ACCESS_TOKEN でも供給可。"
  type        = string
  default     = null
  sensitive   = true
}

variable "sakura_access_token_secret" {
  description = "さくらのクラウド API アクセストークンシークレット。環境変数 SAKURA_ACCESS_TOKEN_SECRET でも供給可。"
  type        = string
  default     = null
  sensitive   = true
}

variable "zone" {
  description = "リソースを作成するゾーン。"
  type        = string
  default     = "tk1a" # 東京第1ゾーン。tk1a / tk1b / is1a / is1b / is1c から選択
}

########################################
# サーバー
########################################

variable "server_name" {
  description = "作成するサーバーの名前"
  type        = string
  default     = "docker-host"
}

variable "server_private_net_cidr" {
  description = "サーバーが接続するプライベートネットワークの CIDR"
  type        = string
  default     = "192.168.1.40/24"
}

variable "server_ssh_public_key_path" {
  description = "サーバーへの SSH 公開鍵認証で使用する公開鍵ファイルのパス"
  type        = string
  default     = ""
}

variable "server_ssh_user" {
  description = "サーバーへの SSH 接続で使用するユーザー名 (Ubuntu cloudimg のデフォルトユーザー)"
  type        = string
  default     = "ubuntu"
}

variable "app_remote_dir" {
  description = "アプリ関連ファイル (.env, compose.reg.yml) を配置するリモートサーバー上のディレクトリ"
  type        = string
  default     = "/opt/app"
}

variable "cr_url" {
  description = "さくらのクラウド コンテナレジストリの URL"
  type        = string
  default     = ""
}

variable "cr_username" {
  description = "さくらのクラウド コンテナレジストリのユーザー名"
  type        = string
  default     = ""
}

variable "cr_password" {
  description = "さくらのクラウド コンテナレジストリのパスワード"
  type        = string
  default     = ""
  sensitive   = true
}


########################################
# データベースアプライアンス
########################################

variable "db_username" {
  description = "データベースのユーザー名"
  type        = string
  default     = "sakuravel_app"
}

variable "db_password" {
  description = "データベースのパスワード"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "作成するデータベース名"
  type        = string
  default     = "sakuravel_app"
}

variable "db_private_net_cidr" {
  description = "データベースアプライアンスが接続するプライベートネットワークの CIDR"
  type        = string
  default     = "192.168.1.30/24"
}

variable "db_private_net_gateway" {
  description = "データベースアプライアンスが使用するプライベートネットワークのデフォルトゲートウェイ"
  type        = string
  default     = "192.168.1.1"
}

variable "db_private_net_allow_cidr" {
  description = "データベースアプライアンスへのアクセスを許可するネットワークアドレスの CIDR"
  type        = string
  default     = "192.168.1.0/24"
}

########################################
# 公開ドメイン
########################################

variable "app_domain" {
  description = <<-EOT
    アプリを公開するドメイン名。ポート番号は含めない (例: "example.jp")。
    空文字にするとサーバーの公開IPアドレスで公開する構成になり、
    Let's Encrypt の証明書は取得できないため HTTP (app_http_port) で公開される。
    ドメインを指定した場合は HTTPS (app_https_port) + Let's Encrypt 構成になる。
    ALLOWED_ORIGIN / API_URL・nginx の server_name と証明書パス・
    init-ssl.sh の取得対象ドメインは、すべてこの値から自動的に導出される。
  EOT
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("[:/]", var.app_domain))
    error_message = "app_domain にはホスト名のみを指定してください (スキームやポート番号は app_http_port / app_https_port で指定します)。"
  }
}

variable "app_http_port" {
  description = <<-EOT
    proxy (nginx) の HTTP をホスト側で公開するポート。
    app_domain が空の場合はこのポートがサービスの公開ポートになる。
    ドメイン指定時は HTTPS へのリダイレクトと Let's Encrypt の更新用。
  EOT
  type        = number
  default     = 8080
}

variable "app_https_port" {
  description = <<-EOT
    proxy (nginx) の HTTPS をホスト側で公開するポート。
    app_domain を指定した場合のサービスの公開ポート。
  EOT
  type        = number
  default     = 4430
}

variable "certbot_email" {
  description = <<-EOT
    Let's Encrypt の証明書取得に使うメールアドレス。
    空の場合は admin@<app_domain> を使用する。app_domain が空なら証明書は取得しない。
  EOT
  type        = string
  default     = ""
}

########################################
# sacloud-otel-collector (モニタリングスイート連携)
########################################
# トークンを secret.auto.tfvars に設定すると、cloud-init がVM作成時に
# Collector をインストールし、トレース(OTLP:4318)とnginxアクセスログの
# 転送をセットアップする。トークン未設定なら何もしない。
# 注意: cloud-init はVM作成時に一度だけ実行されるため、あとからトークンを
# 設定・変更した場合はVMの再作成 (taint) が必要。

variable "otel_collector_version" {
  description = "インストールする sacloud-otel-collector のバージョン"
  type        = string
  default     = "0.7.6"
}

variable "monitoring_metrics_endpoint" {
  description = "モニタリングスイートのメトリクス送信先ID (例 123456789012)"
  type        = string
  default     = ""
}

variable "monitoring_metrics_token" {
  description = "モニタリングスイートのメトリクス書き込みトークン (met-*)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "monitoring_traces_endpoint" {
  description = "モニタリングスイートのトレース送信先ID (例 123456789012)"
  type        = string
  default     = ""
}

variable "monitoring_traces_token" {
  description = "モニタリングスイートのトレース書き込みトークン (trc-*)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "monitoring_logs_endpoint" {
  description = "モニタリングスイートのログ送信先ID (例 123456789012)"
  type        = string
  default     = ""
}

variable "monitoring_logs_token" {
  description = "モニタリングスイートのログ書き込みトークン (log-*)"
  type        = string
  default     = ""
  sensitive   = true
}

########################################
# モニタリングスイート (シンプル監視)
########################################

variable "healthz_check_delay_loop" {
  description = "/healthz シンプル監視のチェック間隔 (秒)。60-3600 の範囲。"
  type        = number
  default     = 60
}

########################################
# トレース (OpenTelemetry)
########################################

variable "otel_exporter_otlp_traces_endpoint" {
  description = <<-EOT
    api コンテナがトレースを送信する OTLP/HTTP の受信口。
    ホスト側で動く sacloud-otel-collector を指す。
    空文字にするとトレース送信を無効化できる。
  EOT
  type        = string
  default     = "http://host.docker.internal:4318/v1/traces"
}

variable "otel_service_name" {
  description = "トレースの service.name"
  type        = string
  default     = "sakuravel-api"
}

variable "backend_image_tag" {
  description = <<-EOT
    起動する backend イメージの既定タグ。
    サーバー上で app/backend/scripts/switch-variant.sh を使うと
    .env.variant が優先されるため、性能比較中の切り替えは上書きされない。
  EOT
  type        = string
  default     = "latest"
}
