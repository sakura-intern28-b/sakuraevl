terraform {
  required_version = ">= 1.11"

  required_providers {
    sakura = {
      source  = "sacloud/sakura"
      version = "~> 3.8"
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

provider "sakura" {
  token  = var.sakura_access_token
  secret = var.sakura_access_token_secret
  zone   = "tk1a"
}

data "sakura_object_storage_site" "tfstate" {
  id = "tky01"
}

resource "sakura_object_storage_bucket" "tfstate" {
  name    = var.tfstate_bucket_name
  site_id = data.sakura_object_storage_site.tfstate.id

  lifecycle {
    prevent_destroy = true
  }
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

output "access_key" {
  value     = sakura_object_storage_permission.tfstate.access_key
  sensitive = true
}

output "secret_key" {
  value     = sakura_object_storage_permission.tfstate.secret_key
  sensitive = true
}
