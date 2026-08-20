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

provider "sakura" {
  token  = var.sakura_access_token
  secret = var.sakura_access_token_secret
  zone   = "tk1a"
}

data "sakura_object_storage_site" "tfstate" {
  id = "tky01"
}

resource "sakura_object_storage_bucket" "tfstate" {
  name    = "sakuraevl-terraform-state"
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
