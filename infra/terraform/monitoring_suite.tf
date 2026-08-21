########################################
# モニタリングスイート: ログ / メトリック / トレース ストレージ
########################################
# 3種類のストレージと送信用アクセスキーを Terraform が作成し、
# その値を cloud-init の sacloud-otel-collector 設定へ直接流し込む。
# (以前は secret.auto.tfvars に monitoring_*_endpoint / monitoring_*_token を
#  手で書き写す方式だったが、コンパネでの手作業が必要なため廃止した)
#
# sacloud-otel-collector の exporters.sacloud.<signal> は
#   endpoint: ストレージのリソースID (例: 113801940282)
#   token:    アクセスキーのトークン (例: log-xxxxxxxx)
# を取る。
#
# 注意: cloud-init (user_data) はVMの初回起動時にしか実行されない。
# ストレージを作り直して endpoint/token が変わった場合、apply は
# サーバーを in-place 更新するだけで Collector の設定は古いままになる。
# 反映するには -replace でVMを作り直すこと。

variable "monitoring_suite_name_prefix" {
  description = "作成するモニタリングスイート各ストレージの名前プレフィックス"
  type        = string
  default     = "sakuraevl"
}

variable "monitoring_logs_retention_days" {
  description = "ログストレージの保持日数"
  type        = number
  default     = 30
}

variable "monitoring_traces_retention_days" {
  description = "トレースストレージの保持日数"
  type        = number
  default     = 14
}

########################################
# ログストレージ
########################################

resource "sakura_monitoring_suite_log_storage" "app" {
  name                  = "${var.monitoring_suite_name_prefix}-logs"
  description           = "アプリケーションログ (sacloud-otel-collector から送信)"
  retention_period_days = var.monitoring_logs_retention_days
}

resource "sakura_monitoring_suite_log_storage_access_key" "app" {
  storage_id  = sakura_monitoring_suite_log_storage.app.id
  description = "sacloud-otel-collector からのログ送信用"
}

########################################
# メトリックストレージ
########################################
# メトリックストレージには retention_period_days が無い (プロバイダー未対応)

resource "sakura_monitoring_suite_metric_storage" "app" {
  name        = "${var.monitoring_suite_name_prefix}-metrics"
  description = "アプリケーション/ホストメトリック (sacloud-otel-collector から送信)"
}

resource "sakura_monitoring_suite_metric_storage_access_key" "app" {
  storage_id  = sakura_monitoring_suite_metric_storage.app.id
  description = "sacloud-otel-collector からのメトリック送信用"
}

########################################
# トレースストレージ
########################################

resource "sakura_monitoring_suite_trace_storage" "app" {
  name                  = "${var.monitoring_suite_name_prefix}-traces"
  description           = "分散トレース (sacloud-otel-collector から送信)"
  retention_period_days = var.monitoring_traces_retention_days
}

resource "sakura_monitoring_suite_trace_storage_access_key" "app" {
  storage_id  = sakura_monitoring_suite_trace_storage.app.id
  description = "sacloud-otel-collector からのトレース送信用"
}

########################################
# 参考出力 (コンパネで突き合わせるとき用)
########################################

output "monitoring_suite_log_storage_id" {
  value = sakura_monitoring_suite_log_storage.app.resource_id
}

output "monitoring_suite_metric_storage_id" {
  value = sakura_monitoring_suite_metric_storage.app.resource_id
}

output "monitoring_suite_trace_storage_id" {
  value = sakura_monitoring_suite_trace_storage.app.resource_id
}
