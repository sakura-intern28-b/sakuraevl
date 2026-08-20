########################################
# Terraform state 用 Object Storage のブートストラップ
########################################
# ここは「stateを置くバケットとアクセスキーを作るためだけ」の小さな構成。
# バケットを作る前は、そのバケットにstateを置けない (鶏と卵) ため、
# この構成のstateだけはローカル (tfstate/terraform.tfstate) に置く。
#
#   terraform -chdir=infra/tfstate init
#   terraform -chdir=infra/tfstate apply -var-file=../terraform/secret.auto.tfvars
#
# apply が成功すると、本体構成 (infra/terraform) の backend 設定
# backend_override.tf が自動生成される。
# 以降は infra/terraform で init / apply するだけでよい。
#
# 2人目以降が同じバケットを使う場合は、作成ではなくimportする:
#   terraform -chdir=infra/tfstate import -var-file=../terraform/secret.auto.tfvars \
#     sakura_object_storage_bucket.tfstate tky01/<バケット名>

terraform {
  required_version = ">= 1.11"

  required_providers {
    sakura = {
      source  = "sacloud/sakura"
      version = "~> 3.8"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "sakura_access_token" {
  type      = string
  default   = null
  sensitive = true
}

variable "sakura_access_token_secret" {
  type      = string
  default   = null
  sensitive = true
}

variable "tfstate_bucket_name" {
  description = "Terraform stateを保存する、アカウント・環境ごとに一意なObject Storageバケット名"
  type        = string

  validation {
    condition = (
      length(var.tfstate_bucket_name) >= 3 &&
      length(var.tfstate_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.tfstate_bucket_name)) &&
      !strcontains(var.tfstate_bucket_name, "..") &&
      !strcontains(var.tfstate_bucket_name, ".-") &&
      !strcontains(var.tfstate_bucket_name, "-.")
    )
    error_message = "tfstate_bucket_nameは3-63文字の小文字英数字、ドット、ハイフンで指定してください。"
  }
}

variable "tfstate_object_storage_site" {
  description = "Object Storage のサイトID"
  type        = string
  default     = "tky01"
}

variable "tfstate_key" {
  description = "本体構成のstateを保存するオブジェクトキー"
  type        = string
  default     = "sakuraevl/infra/terraform.tfstate"
}

provider "sakura" {
  token  = var.sakura_access_token
  secret = var.sakura_access_token_secret
  zone   = "tk1a"
}

data "sakura_object_storage_site" "tfstate" {
  id = var.tfstate_object_storage_site
}

resource "sakura_object_storage_bucket" "tfstate" {
  name    = var.tfstate_bucket_name
  site_id = data.sakura_object_storage_site.tfstate.id

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "sakura_object_storage_permission" "tfstate" {
  name    = "sakuraevl-tfstate-rw"
  site_id = data.sakura_object_storage_site.tfstate.id

  bucket_controls = [{
    bucket    = sakura_object_storage_bucket.tfstate.name
    can_read  = true
    can_write = true
  }]

  lifecycle {
    prevent_destroy = true
  }
}

# stateを誤って壊したときに巻き戻せるようにバージョニングを有効化する
resource "sakura_object_storage_bucket_versioning" "tfstate" {
  bucket     = sakura_object_storage_bucket.tfstate.name
  region     = data.sakura_object_storage_site.tfstate.region
  endpoint   = data.sakura_object_storage_site.tfstate.s3_endpoint
  access_key = sakura_object_storage_permission.tfstate.access_key
  secret_key = sakura_object_storage_permission.tfstate.secret_key

  versioning_configuration = {
    status = "Enabled"
  }
}

########################################
# 本体構成の backend 設定を自動生成
########################################
# backend ブロックには変数を書けないので、値が確定した後に
# override ファイル (*_override.tf) として書き出す。
# Terraform は *_override.tf の backend ブロックで元の backend ブロックを
# 丸ごと置き換えるため、infra/terraform では追加のオプションなしで
# `terraform init` するだけで済む。
# 生成物はアクセスキーを含むので .gitignore 済み (*_override.tf)。

resource "local_sensitive_file" "backend_override" {
  filename        = "${path.module}/../terraform/backend_override.tf"
  file_permission = "0600"

  content = <<-EOT
    # このファイルは infra/tfstate の terraform apply が自動生成します。
    # 手で編集しないでください (アクセスキーを含むためgit管理外)。
    terraform {
      backend "s3" {
        bucket = "${sakura_object_storage_bucket.tfstate.name}"
        key    = "${var.tfstate_key}"
        region = "${data.sakura_object_storage_site.tfstate.region}"

        endpoints = {
          s3 = "https://${data.sakura_object_storage_site.tfstate.s3_endpoint}"
        }

        access_key = "${sakura_object_storage_permission.tfstate.access_key}"
        secret_key = "${sakura_object_storage_permission.tfstate.secret_key}"

        # さくらのオブジェクトストレージはAWSではないため、
        # AWS固有の検証とEC2メタデータ(IMDS)へのフォールバックを無効化する
        skip_credentials_validation = true
        skip_metadata_api_check     = true
        skip_region_validation      = true
        skip_requesting_account_id  = true
        skip_s3_checksum            = true
      }
    }
  EOT
}

output "tfstate_bucket_name" {
  value = sakura_object_storage_bucket.tfstate.name
}

output "backend_override_path" {
  description = "自動生成された本体構成のbackend設定"
  value       = local_sensitive_file.backend_override.filename
}

output "access_key" {
  value     = sakura_object_storage_permission.tfstate.access_key
  sensitive = true
}

output "secret_key" {
  value     = sakura_object_storage_permission.tfstate.secret_key
  sensitive = true
}
