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

variable "server_password" {
  description = "サーバーの初期パスワード (SSH 公開鍵認証を使用する場合でも必要)"
  type        = string
  sensitive   = true
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

variable "domain_name" {
  description = "さくらのクラウド DNS で管理するドメイン名"
  type        = string
  default     = ""
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
    アプリを公開するドメイン名。backend_env.tf が ALLOWED_ORIGIN / API_URL を
    ここから導出する。
    注意: app/backend/nginx/nginx.conf (server_name, 証明書パス) と
    app/backend/init-ssl.sh にも同じドメインが書かれているため、
    変更する場合はそちらも合わせて修正すること。
  EOT
  type        = string
  default     = "teamb.intern28.sakuraha.jp"
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
